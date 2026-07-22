import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/outbox/sync_outbox_writer.dart';
import '../core/utils/descuento_utils.dart';
import '../models/promocion_model.dart';
import 'auditoria_controller.dart';

/// Única fuente de verdad para operaciones sobre promociones automáticas:
/// CRUD, activar/desactivar y la consulta de promociones vigentes que
/// consumen `ventas_view.dart` y `VentasController.insertarVentaCompleta`.
class PromocionesController {
  final _auditoriaController = AuditoriaController();
  final _outboxWriter = SyncOutboxWriter(authService: AuthService.instancia);

  Future<int> crear(Promocion promocion) async {
    _validar(promocion);
    final db = await DatabaseHelper().database;

    final id = await db.transaction((txn) async {
      final nuevoId = await _outboxWriter.crear(txn, entidad: 'Promocion', tabla: 'Promociones', values: promocion.toMap());
      await _guardarParticipantes(txn, nuevoId, promocion);
      return nuevoId;
    });

    await _auditoriaController.registrar(
      tabla: 'Promociones',
      accion: 'CREATE',
      idRegistro: id,
      descripcion: 'Promoción "${promocion.nombre}" (${promocion.tipo.nombreDb}) creada',
    );

    return id;
  }

  Future<int> actualizar(Promocion promocion) async {
    if (promocion.idPromocion == null) {
      throw Exception('La promoción no tiene ID.');
    }
    _validar(promocion);
    final db = await DatabaseHelper().database;
    final id = promocion.idPromocion!;

    final rows = await db.transaction((txn) async {
      final filas = await txn.update(
        'Promociones',
        promocion.toMap()..remove('id_promocion'),
        where: 'id_promocion = ?',
        whereArgs: [id],
      );

      if (filas > 0) {
        // Reemplazo completo de participantes: más simple y menos propenso
        // a errores que un diff incremental, y el volumen por promoción es
        // pequeño (unos pocos productos/categorías o items de combo).
        await txn.delete('Promocion_Productos', where: 'id_promocion = ?', whereArgs: [id]);
        await txn.delete('Promocion_Categorias', where: 'id_promocion = ?', whereArgs: [id]);
        await txn.delete('Promocion_Combo_Items', where: 'id_promocion = ?', whereArgs: [id]);
        await _guardarParticipantes(txn, id, promocion);
        await _outboxWriter.actualizar(txn, entidad: 'Promocion', tabla: 'Promociones', idLocal: id);
      }

      return filas;
    });

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Promociones',
        accion: 'EDIT',
        idRegistro: id,
        descripcion: 'Promoción "${promocion.nombre}" modificada',
      );
    }

    return rows;
  }

  Future<int> activar(int id) => _cambiarActivo(id, true);

  Future<int> desactivar(int id) => _cambiarActivo(id, false);

  Future<int> _cambiarActivo(int id, bool activo) async {
    final db = await DatabaseHelper().database;
    final rows = await db.update(
      'Promociones',
      {'activo': activo ? 1 : 0},
      where: 'id_promocion = ?',
      whereArgs: [id],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Promociones',
        accion: activo ? 'ACTIVAR' : 'DESACTIVAR',
        idRegistro: id,
        descripcion: 'Promoción #$id ${activo ? 'activada' : 'desactivada'}',
      );
      await _outboxWriter.actualizar(db, entidad: 'Promocion', tabla: 'Promociones', idLocal: id);
    }

    return rows;
  }

  /// Borra la definición de la promoción. Las ventas ya cerradas no se ven
  /// afectadas: `Venta_Promociones.id_promocion` es `ON DELETE SET NULL` y
  /// ya guarda su propio snapshot de nombre/tipo.
  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;
    final rows = await db.delete('Promociones', where: 'id_promocion = ?', whereArgs: [id]);

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Promociones',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: 'Promoción #$id eliminada',
      );
    }

    return rows;
  }

  Future<Promocion?> obtenerPorId(int id) async {
    final db = await DatabaseHelper().database;
    final filas = await db.query('Promociones', where: 'id_promocion = ?', whereArgs: [id], limit: 1);
    if (filas.isEmpty) return null;

    final promociones = await _construirPromociones(db, filas);
    return promociones.first;
  }

  Future<List<Promocion>> obtenerTodas() async {
    final db = await DatabaseHelper().database;
    final filas = await db.query('Promociones', orderBy: 'prioridad DESC, nombre');
    return _construirPromociones(db, filas);
  }

  /// Promociones activas y vigentes a [fecha] (por defecto, ahora). Es lo
  /// que consumen tanto la vista previa del carrito como el recálculo
  /// autoritativo de `VentasController` — nunca se confía en una lista de
  /// promociones armada por la UI.
  Future<List<Promocion>> obtenerActivasVigentes({DateTime? fecha}) async {
    final db = await DatabaseHelper().database;
    final fechaRef = (fecha ?? DateTime.now()).toIso8601String();

    final filas = await db.query(
      'Promociones',
      where: 'activo = 1 AND (fecha_inicio IS NULL OR fecha_inicio <= ?) '
          'AND (fecha_fin IS NULL OR fecha_fin >= ?)',
      whereArgs: [fechaRef, fechaRef],
      orderBy: 'prioridad DESC, nombre',
    );

    return _construirPromociones(db, filas);
  }

  Future<void> _guardarParticipantes(DatabaseExecutor txn, int idPromocion, Promocion promocion) async {
    for (final idProducto in promocion.productosIds) {
      await txn.insert('Promocion_Productos', {'id_promocion': idPromocion, 'id_producto': idProducto});
    }
    for (final idCategoria in promocion.categoriasIds) {
      await txn.insert('Promocion_Categorias', {'id_promocion': idPromocion, 'id_categoria': idCategoria});
    }
    for (final item in promocion.comboItems) {
      await txn.insert('Promocion_Combo_Items', item.toMap(idPromocion));
    }
  }

  Future<List<Promocion>> _construirPromociones(DatabaseExecutor db, List<Map<String, dynamic>> filas) async {
    if (filas.isEmpty) return [];

    final ids = filas.map((f) => f['id_promocion'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');

    final productos = await db.query('Promocion_Productos', where: 'id_promocion IN ($placeholders)', whereArgs: ids);
    final categorias =
        await db.query('Promocion_Categorias', where: 'id_promocion IN ($placeholders)', whereArgs: ids);
    final comboItems =
        await db.query('Promocion_Combo_Items', where: 'id_promocion IN ($placeholders)', whereArgs: ids);

    final productosPorPromo = <int, List<int>>{};
    for (final p in productos) {
      productosPorPromo.putIfAbsent(p['id_promocion'] as int, () => []).add(p['id_producto'] as int);
    }
    final categoriasPorPromo = <int, List<int>>{};
    for (final c in categorias) {
      categoriasPorPromo.putIfAbsent(c['id_promocion'] as int, () => []).add(c['id_categoria'] as int);
    }
    final comboItemsPorPromo = <int, List<ComboItem>>{};
    for (final item in comboItems) {
      comboItemsPorPromo.putIfAbsent(item['id_promocion'] as int, () => []).add(ComboItem.fromMap(item));
    }

    return filas
        .map((f) => Promocion.fromMap(
              f,
              productosIds: productosPorPromo[f['id_promocion']] ?? const [],
              categoriasIds: categoriasPorPromo[f['id_promocion']] ?? const [],
              comboItems: comboItemsPorPromo[f['id_promocion']] ?? const [],
            ))
        .toList();
  }

  /// Validaciones estructurales, análogas en espíritu a
  /// `calcularMontoDescuento`: mensajes en español, una excepción por la
  /// primera regla violada.
  void _validar(Promocion promocion) {
    if (promocion.nombre.trim().isEmpty) {
      throw Exception('El nombre de la promoción es obligatorio.');
    }

    if (promocion.fechaInicio != null &&
        promocion.fechaFin != null &&
        promocion.fechaFin!.isBefore(promocion.fechaInicio!)) {
      throw Exception('La fecha de fin no puede ser anterior a la fecha de inicio.');
    }

    switch (promocion.tipo) {
      case TipoPromocion.porcentajeProducto:
        final valor = promocion.valor ?? 0;
        if (valor <= 0 || valor > 100) {
          throw Exception('El porcentaje de descuento debe estar entre 0 y 100.');
        }
        _validarParticipantes(promocion);
        break;

      case TipoPromocion.montoFijoProducto:
        if ((promocion.valor ?? 0) <= 0) {
          throw Exception('El monto fijo de descuento debe ser mayor a 0.');
        }
        _validarParticipantes(promocion);
        break;

      case TipoPromocion.nxy:
        final lleva = promocion.nxLleva ?? 0;
        final paga = promocion.nxPaga ?? 0;
        if (lleva <= 0 || paga <= 0 || paga >= lleva) {
          throw Exception('En "Compra X y paga Y", X debe ser mayor a Y y ambos mayores a 0.');
        }
        _validarParticipantes(promocion);
        break;

      case TipoPromocion.descuentoCantidad:
        if ((promocion.cantidadMinima ?? 0) <= 0) {
          throw Exception('La cantidad mínima debe ser mayor a 0.');
        }
        final valor = promocion.valor ?? 0;
        if (valor <= 0) {
          throw Exception('El valor del descuento por cantidad debe ser mayor a 0.');
        }
        if (promocion.tipoValor == TipoDescuento.porcentaje && valor > 100) {
          throw Exception('El porcentaje de descuento debe estar entre 0 y 100.');
        }
        _validarParticipantes(promocion);
        break;

      case TipoPromocion.combo:
        if ((promocion.precioCombo ?? 0) <= 0) {
          throw Exception('El precio del combo debe ser mayor a 0.');
        }
        if (promocion.comboItems.length < 2) {
          throw Exception('Un combo debe tener al menos 2 productos.');
        }
        if (promocion.comboItems.any((i) => i.cantidad <= 0)) {
          throw Exception('La cantidad de cada producto del combo debe ser mayor a 0.');
        }
        break;
    }
  }

  void _validarParticipantes(Promocion promocion) {
    if (promocion.productosIds.isEmpty && promocion.categoriasIds.isEmpty) {
      throw Exception('La promoción debe tener al menos un producto o categoría participante.');
    }
  }
}
