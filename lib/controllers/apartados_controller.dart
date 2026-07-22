import 'package:sqflite/sqflite.dart';

import '../core/config/app_config.dart';
import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../core/utils/descuento_utils.dart';
import '../core/utils/money.dart';
import '../core/utils/pagos_mixtos.dart';
import '../core/utils/promociones_engine.dart';
import '../models/apartado_model.dart';
import 'producto_controller.dart';
import 'promociones_controller.dart';

/// Apartados (layaway): un cliente reserva productos con uno o varios
/// abonos y liquida el saldo después, sin que los precios/descuentos/
/// promociones se vuelvan a calcular cuando regresa. Reutiliza el mismo
/// motor de cálculo, promociones y pagos mixtos que `VentasController`; al
/// liquidar produce una fila real en `Ventas` para heredar gratis Reportes,
/// Tickets, Devoluciones y Auditoría ya existentes sobre esa tabla (ver
/// comentario en `_liquidar`).
class ApartadosController {
  final dbHelper = DatabaseHelper();
  final _promocionesController = PromocionesController();
  final _productoController = ProductoController();

  /// Crea el apartado: evalúa promociones + calcula subtotal/descuento/total
  /// exactamente como una venta (snapshot inmutable), reserva el stock de
  /// cada línea (sin tocar la existencia física) y, si se da un anticipo,
  /// lo registra con el mismo mecanismo que cualquier abono posterior — si
  /// ese anticipo cubre el total, el apartado queda liquidado de inmediato.
  Future<int> crear({
    required int idCliente,
    required List<Map<String, dynamic>> carrito,
    double montoAnticipo = 0,
    List<Map<String, dynamic>> pagosAnticipo = const [],
    TipoDescuento? descuentoGlobalTipo,
    double descuentoGlobalValor = 0,
    String? descuentoMotivo,
    int? descuentoAutorizadoPor,
    DateTime? fechaLimite,
    String? observaciones,
  }) async {
    if (carrito.isEmpty) {
      throw Exception('Agrega al menos un producto al apartado.');
    }

    final config = AppConfig.actual;

    final promocionesActivas = await _promocionesController.obtenerActivasVigentes();
    final resultadoPromociones = evaluarPromociones(
      carrito: carrito,
      promocionesActivas: promocionesActivas,
    );

    final calculo = calcularVenta(
      carrito: carrito,
      descuentosPromocionPorLinea: resultadoPromociones.descuentoPorLinea,
      descuentoGlobalTipo: descuentoGlobalTipo,
      descuentoGlobalValor: descuentoGlobalValor,
      descuentoMaximoPorcentaje: config.descuentoMaximoPorcentaje,
    );

    final esCajero = SessionManager.currentUserRole == 'Cajero';
    validarPermisoDescuento(
      calculo: calculo,
      esCajero: esCajero,
      cajeroPuedeAplicarDescuento: config.descuentoCajeroPuedeAplicar,
      cajeroRequiereAutorizacion: config.descuentoCajeroRequiereAutorizacion,
      descuentoMotivo: descuentoMotivo,
      descuentoAutorizadoPor: descuentoAutorizadoPor,
    );

    if (montoAnticipo < 0) {
      throw Exception('El anticipo no puede ser negativo.');
    }
    if (montoAnticipo > calculo.total) {
      throw Exception('El anticipo no puede superar el total del apartado.');
    }

    final db = await dbHelper.database;
    final idUsuario = SessionManager.currentUserId ?? 1;

    return db.transaction((txn) async {
      final idApartado = await txn.insert('Apartados', {
        'id_cliente': idCliente,
        'id_usuario': idUsuario,
        'fecha_creacion': DateTime.now().toIso8601String(),
        'fecha_limite': fechaLimite?.toIso8601String(),
        'estado': EstadoApartado.pendiente.nombreDb,
        'subtotal': calculo.subtotal,
        'descuento_total': calculo.descuentoTotal,
        'descuento_global_tipo': calculo.descuentoGlobalTipo?.nombre,
        'descuento_global_valor': calculo.descuentoGlobalValor,
        'descuento_motivo': descuentoMotivo?.trim(),
        'descuento_autorizado_por': descuentoAutorizadoPor,
        'total': calculo.total,
        'observaciones': observaciones?.trim(),
      });

      // Se guarda el id de cada Detalle_Apartado insertado, en el mismo
      // orden que las líneas del carrito, para enlazar el snapshot de
      // promociones (Apartado_Promociones_Detalle) más abajo.
      final idsDetalleApartado = <int>[];

      for (final linea in calculo.lineas) {
        final stock = await txn.rawQuery(
          'SELECT cantidad, cantidad_reservada FROM Inventario WHERE id_producto = ?',
          [linea.idProducto],
        );

        if (stock.isEmpty) {
          throw Exception('Producto sin inventario');
        }

        final disponible =
            (stock.first['cantidad'] as int) - (stock.first['cantidad_reservada'] as int? ?? 0);

        if (disponible < linea.cantidad) {
          throw Exception(
            'Stock insuficiente para "${linea.nombre}" (disponible: $disponible, solicitado: ${linea.cantidad})',
          );
        }

        final idDetalle = await txn.insert('Detalle_Apartado', {
          'id_apartado': idApartado,
          'id_producto': linea.idProducto,
          'cantidad': linea.cantidad,
          'precio': linea.precioOriginal,
          'descuento_tipo': linea.descuentoTipo?.nombre,
          'descuento_valor': linea.descuentoValor,
          'descuento_monto': linea.descuentoMonto,
          'precio_neto': linea.precioNetoUnitario,
        });
        idsDetalleApartado.add(idDetalle);

        await _productoController.reservarStock(linea.idProducto, linea.cantidad, executor: txn);
      }

      // Snapshot inmutable de las promociones aplicadas (mismo patrón que
      // VentasController): nombre/tipo se guardan tal como eran en este
      // momento, no una referencia viva a `Promociones`.
      for (final aplicacion in resultadoPromociones.aplicaciones) {
        final idApartadoPromocion = await txn.insert('Apartado_Promociones', {
          'id_apartado': idApartado,
          'id_promocion': aplicacion.idPromocion,
          'nombre_snapshot': aplicacion.nombre,
          'tipo_snapshot': aplicacion.tipo.nombreDb,
          'ahorro_total': aplicacion.ahorroTotal,
        });

        for (final linea in aplicacion.lineas) {
          await txn.insert('Apartado_Promociones_Detalle', {
            'id_apartado_promocion': idApartadoPromocion,
            'id_detalle_apartado': idsDetalleApartado[linea.indexLinea],
            'cantidad_afectada': linea.cantidadAfectada,
            'ahorro': linea.ahorro,
          });
        }
      }

      await txn.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': SessionManager.currentUserName,
        'tabla': 'Apartados',
        'accion': 'CREATE',
        'id_registro': idApartado,
        'descripcion': 'Apartado #$idApartado creado por \$${calculo.total.toStringAsFixed(2)} '
            '(anticipo: \$${montoAnticipo.toStringAsFixed(2)}).',
      });

      if (montoAnticipo > 0) {
        await _registrarAbonoInterno(
          txn,
          idApartado: idApartado,
          montoAbono: montoAnticipo,
          pagos: pagosAnticipo,
          tipoSolicitado: TipoAbonoApartado.anticipo,
        );
      }

      return idApartado;
    });
  }

  /// Registra un abono parcial. El monto debe ser mayor a 0 y no puede
  /// superar el saldo pendiente; si lo agota exactamente, el apartado queda
  /// liquidado automáticamente (mismo mecanismo que si se llama a [liquidar]
  /// directamente — cero lógica duplicada entre ambos).
  Future<int> registrarAbono({
    required int idApartado,
    required double montoAbono,
    required List<Map<String, dynamic>> pagos,
  }) async {
    final db = await dbHelper.database;
    await _liberarVencidos(db);

    return db.transaction((txn) => _registrarAbonoInterno(
          txn,
          idApartado: idApartado,
          montoAbono: montoAbono,
          pagos: pagos,
          tipoSolicitado: TipoAbonoApartado.abono,
        ));
  }

  /// Azúcar sobre [registrarAbono]: paga exactamente el saldo pendiente,
  /// liquidando el apartado en el mismo paso.
  Future<int> liquidar({
    required int idApartado,
    required List<Map<String, dynamic>> pagos,
  }) async {
    final saldoPendiente = await obtenerSaldoPendiente(idApartado);
    return registrarAbono(idApartado: idApartado, montoAbono: saldoPendiente, pagos: pagos);
  }

  /// Núcleo compartido de anticipo/abono/liquidación: valida estado, saldo,
  /// pagos y caja abierta; inserta el evento de pago y, si el saldo llega a
  /// 0, dispara [_liquidar] dentro de la misma transacción.
  Future<int> _registrarAbonoInterno(
    DatabaseExecutor txn, {
    required int idApartado,
    required double montoAbono,
    required List<Map<String, dynamic>> pagos,
    required TipoAbonoApartado tipoSolicitado,
  }) async {
    final apartadoRows = await txn.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado], limit: 1);
    if (apartadoRows.isEmpty) {
      throw Exception('El apartado no existe.');
    }

    final estado = EstadoApartado.desdeNombreDb(apartadoRows.first['estado'] as String);
    if (estado != EstadoApartado.pendiente) {
      throw Exception('Este apartado no admite pagos (estado: ${estado.nombreDb}).');
    }

    final total = (apartadoRows.first['total'] as num).toDouble();
    final abonadoRes = await txn.rawQuery(
      'SELECT IFNULL(SUM(monto), 0) as total FROM Apartado_Abonos WHERE id_apartado = ?',
      [idApartado],
    );
    final abonadoPrevio = (abonadoRes.first['total'] as num).toDouble();
    final saldoPendiente = redondearMoneda(total - abonadoPrevio);

    if (montoAbono <= 0) {
      throw Exception('El monto del abono debe ser mayor a 0.');
    }
    if (montoAbono > saldoPendiente) {
      throw Exception(
        'El abono (\$${montoAbono.toStringAsFixed(2)}) no puede superar el saldo pendiente '
        '(\$${saldoPendiente.toStringAsFixed(2)}).',
      );
    }

    for (final pago in pagos) {
      final metodo = pago['metodo_pago']?.toString() ?? '';
      final esConocido = metodosPagoDisponibles.any(
        (m) => m.toLowerCase() == metodo.trim().toLowerCase(),
      );
      if (!esConocido) {
        throw Exception('Método de pago no reconocido: "$metodo".');
      }
    }

    final resultadoPagos = validarPagosMixtos(
      total: montoAbono,
      pagos: pagos
          .map((p) => PagoIngresado(
                metodoPago: p['metodo_pago'] as String,
                monto: (p['monto'] as num).toDouble(),
              ))
          .toList(),
    );

    if (!resultadoPagos.esValido) {
      throw Exception(resultadoPagos.mensajeError ?? 'Los pagos no cubren el abono.');
    }

    final idUsuario = SessionManager.currentUserId ?? 1;
    final cajaAbierta = await txn.query(
      'Cajas',
      where: 'id_usuario = ? AND estado = ?',
      whereArgs: [idUsuario, 'Abierta'],
      limit: 1,
    );
    if (cajaAbierta.isEmpty) {
      throw Exception('Debes abrir la caja antes de registrar un pago de apartado.');
    }
    final idCaja = cajaAbierta.first['id_caja'] as int;

    final saldoRestante = redondearMoneda(saldoPendiente - montoAbono);
    final tipoFinal = saldoRestante <= 0 ? TipoAbonoApartado.liquidacion : tipoSolicitado;

    final idAbono = await txn.insert('Apartado_Abonos', {
      'id_apartado': idApartado,
      'id_caja': idCaja,
      'id_usuario': idUsuario,
      'fecha': DateTime.now().toIso8601String(),
      'tipo': tipoFinal.nombreDb,
      'monto': montoAbono,
      'cambio': resultadoPagos.cambio,
    });

    for (final pago in pagos) {
      await txn.insert('Apartado_Abono_Pagos', {
        'id_abono': idAbono,
        'metodo_pago': pago['metodo_pago'],
        'monto': redondearMoneda((pago['monto'] as num).toDouble()),
      });
    }

    final desglosePagos =
        pagos.map((p) => '${p['metodo_pago']}: \$${(p['monto'] as num).toStringAsFixed(2)}').join(', ');

    await txn.insert('Auditorias', {
      'fecha_hora': DateTime.now().toIso8601String(),
      'usuario': SessionManager.currentUserName,
      'tabla': 'Apartados',
      'accion': tipoFinal == TipoAbonoApartado.liquidacion ? 'LIQUIDACION' : 'ABONO',
      'id_registro': idApartado,
      'descripcion': '${tipoFinal == TipoAbonoApartado.liquidacion ? 'Liquidación' : 'Abono'} de '
          '\$${montoAbono.toStringAsFixed(2)} en apartado #$idApartado ($desglosePagos).',
    });

    if (saldoRestante <= 0) {
      await _liquidar(txn, idApartado);
    }

    return idAbono;
  }

  /// Convierte la reserva en una venta definitiva. La `Venta` resultante
  /// NO inserta filas en `Venta_Pagos` ni `Venta_Promociones`: ese historial
  /// sigue viviendo en `Apartado_Abonos`/`Apartado_Promociones` enlazado por
  /// `Ventas.id_apartado`, para no contar el dinero dos veces en Caja/
  /// Reportes (cada abono ya se contó en la caja que estaba abierta cuando
  /// se cobró, posiblemente días/semanas antes en un turno ya cerrado; ver
  /// `CajaController._computarResumen` y `ReporteController.obtenerPagosVenta`).
  /// `Detalle_Venta` se copia literalmente de `Detalle_Apartado` — sin
  /// recalcular precios/descuentos.
  Future<void> _liquidar(DatabaseExecutor txn, int idApartado) async {
    final apartadoRows = await txn.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado], limit: 1);
    final apartado = apartadoRows.first;

    final detalles = await txn.query('Detalle_Apartado', where: 'id_apartado = ?', whereArgs: [idApartado]);

    final idUsuario = SessionManager.currentUserId ?? 1;
    final ultimoAbono = await txn.query(
      'Apartado_Abonos',
      where: 'id_apartado = ?',
      whereArgs: [idApartado],
      orderBy: 'id_abono DESC',
      limit: 1,
    );
    final idCajaLiquidacion = ultimoAbono.isNotEmpty ? ultimoAbono.first['id_caja'] as int? : null;

    final idVenta = await DatabaseHelper.insertarConGuidSync(txn, 'Ventas', {
      'id_cliente': apartado['id_cliente'],
      'id_usuario': idUsuario,
      'id_caja': idCajaLiquidacion,
      'id_apartado': idApartado,
      'fecha': DateTime.now().toIso8601String(),
      'total': apartado['total'],
      'subtotal': apartado['subtotal'],
      'descuento_total': apartado['descuento_total'],
      'descuento_global_tipo': apartado['descuento_global_tipo'],
      'descuento_global_valor': apartado['descuento_global_valor'],
      'descuento_motivo': apartado['descuento_motivo'],
      'descuento_autorizado_por': apartado['descuento_autorizado_por'],
      'metodo_pago': 'Apartado',
      'cambio': 0,
    });

    for (final detalle in detalles) {
      await DatabaseHelper.insertarConGuidSync(txn, 'Detalle_Venta', {
        'id_venta': idVenta,
        'id_producto': detalle['id_producto'],
        'cantidad': detalle['cantidad'],
        'precio': detalle['precio'],
        'descuento_tipo': detalle['descuento_tipo'],
        'descuento_valor': detalle['descuento_valor'],
        'descuento_monto': detalle['descuento_monto'],
        'precio_neto': detalle['precio_neto'],
      });

      await _productoController.confirmarReserva(
        detalle['id_producto'] as int,
        detalle['cantidad'] as int,
        executor: txn,
      );
    }

    await txn.update(
      'Apartados',
      {'estado': EstadoApartado.liquidado.nombreDb, 'id_venta': idVenta},
      where: 'id_apartado = ?',
      whereArgs: [idApartado],
    );
  }

  /// Cancela el apartado: libera la reserva de stock (si aún la tenía —
  /// uno ya `Vencido` la liberó automáticamente) y lo marca `Cancelado`. No
  /// genera ningún movimiento de caja/devolución: si el negocio decide
  /// reembolsar abonos ya pagados, lo maneja fuera del sistema.
  Future<int> cancelar({required int idApartado, required String motivo}) async {
    final motivoLimpio = motivo.trim();
    if (motivoLimpio.isEmpty) {
      throw Exception('El motivo es obligatorio.');
    }

    final db = await dbHelper.database;
    await _liberarVencidos(db);

    return db.transaction((txn) async {
      final apartadoRows =
          await txn.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado], limit: 1);
      if (apartadoRows.isEmpty) {
        throw Exception('El apartado no existe.');
      }

      final estado = EstadoApartado.desdeNombreDb(apartadoRows.first['estado'] as String);
      if (estado != EstadoApartado.pendiente && estado != EstadoApartado.vencido) {
        throw Exception('Este apartado ya está ${estado.nombreDb.toLowerCase()} y no se puede cancelar.');
      }

      if (estado == EstadoApartado.pendiente) {
        final detalles =
            await txn.query('Detalle_Apartado', where: 'id_apartado = ?', whereArgs: [idApartado]);
        for (final detalle in detalles) {
          await _productoController.liberarReserva(
            detalle['id_producto'] as int,
            detalle['cantidad'] as int,
            executor: txn,
          );
        }
      }

      await txn.update(
        'Apartados',
        {'estado': EstadoApartado.cancelado.nombreDb},
        where: 'id_apartado = ?',
        whereArgs: [idApartado],
      );

      await txn.insert('Auditorias', {
        'fecha_hora': DateTime.now().toIso8601String(),
        'usuario': SessionManager.currentUserName,
        'tabla': 'Apartados',
        'accion': 'CANCEL',
        'id_registro': idApartado,
        'descripcion': 'Apartado #$idApartado cancelado. Motivo: $motivoLimpio.',
      });

      return idApartado;
    });
  }

  /// Transición perezosa (self-healing): cualquier apartado `Pendiente` cuya
  /// `fecha_limite` ya pasó libera su reserva de stock automáticamente y
  /// pasa a `Vencido`. Se llama al inicio de cada método de lectura/
  /// escritura para que ningún camino dependa de un scheduler en segundo
  /// plano (esta app de escritorio no tiene uno).
  Future<void> _liberarVencidos(Database db) async {
    await db.transaction((txn) async {
      final hoy = DateTime.now().toIso8601String();
      final vencidos = await txn.query(
        'Apartados',
        where: "estado = 'Pendiente' AND fecha_limite IS NOT NULL AND fecha_limite < ?",
        whereArgs: [hoy],
      );

      for (final apartado in vencidos) {
        final idApartado = apartado['id_apartado'] as int;
        final detalles =
            await txn.query('Detalle_Apartado', where: 'id_apartado = ?', whereArgs: [idApartado]);

        for (final detalle in detalles) {
          await _productoController.liberarReserva(
            detalle['id_producto'] as int,
            detalle['cantidad'] as int,
            executor: txn,
          );
        }

        await txn.update(
          'Apartados',
          {'estado': EstadoApartado.vencido.nombreDb},
          where: 'id_apartado = ?',
          whereArgs: [idApartado],
        );

        await txn.insert('Auditorias', {
          'fecha_hora': DateTime.now().toIso8601String(),
          'usuario': 'Sistema',
          'tabla': 'Apartados',
          'accion': 'VENCIDO',
          'id_registro': idApartado,
          'descripcion': 'Apartado #$idApartado marcado como vencido; reserva de stock liberada.',
        });
      }
    });
  }

  Future<double> obtenerSaldoPendiente(int idApartado) async {
    final db = await dbHelper.database;
    await _liberarVencidos(db);

    final apartadoRows = await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado], limit: 1);
    if (apartadoRows.isEmpty) {
      throw Exception('El apartado no existe.');
    }
    final total = (apartadoRows.first['total'] as num).toDouble();

    final abonadoRes = await db.rawQuery(
      'SELECT IFNULL(SUM(monto), 0) as total FROM Apartado_Abonos WHERE id_apartado = ?',
      [idApartado],
    );
    final abonado = (abonadoRes.first['total'] as num).toDouble();

    return redondearMoneda(total - abonado);
  }

  /// Historial completo de pagos de un apartado: cada abono con sus
  /// métodos de pago anidados (`pagos`), en orden cronológico.
  Future<List<Map<String, dynamic>>> obtenerHistorialPagos(int idApartado) async {
    final db = await dbHelper.database;

    final abonos = await db.query(
      'Apartado_Abonos',
      where: 'id_apartado = ?',
      whereArgs: [idApartado],
      orderBy: 'fecha ASC',
    );

    final resultado = <Map<String, dynamic>>[];
    for (final abono in abonos) {
      final pagos = await db.query(
        'Apartado_Abono_Pagos',
        where: 'id_abono = ?',
        whereArgs: [abono['id_abono']],
      );
      resultado.add({...abono, 'pagos': pagos});
    }
    return resultado;
  }

  /// Detalle completo para la pantalla de un apartado: cabecera + cliente,
  /// productos (con nombre), historial de pagos y saldo pendiente.
  Future<Map<String, dynamic>> obtenerDetalle(int idApartado) async {
    final db = await dbHelper.database;
    await _liberarVencidos(db);

    final rows = await db.rawQuery('''
      SELECT Apartados.*, Clientes.nombre as cliente_nombre
      FROM Apartados
      LEFT JOIN Clientes ON Clientes.id_cliente = Apartados.id_cliente
      WHERE Apartados.id_apartado = ?
    ''', [idApartado]);

    if (rows.isEmpty) {
      throw Exception('El apartado no existe.');
    }

    final items = await db.rawQuery('''
      SELECT Detalle_Apartado.*, Producto.nombre as producto_nombre
      FROM Detalle_Apartado
      INNER JOIN Producto ON Producto.id_producto = Detalle_Apartado.id_producto
      WHERE Detalle_Apartado.id_apartado = ?
    ''', [idApartado]);

    return {
      'apartado': rows.first,
      'items': items,
      'historial_pagos': await obtenerHistorialPagos(idApartado),
      'saldo_pendiente': await obtenerSaldoPendiente(idApartado),
    };
  }

  /// Lista todos los apartados, con el nombre del cliente y el saldo
  /// pendiente ya calculado (para no hacer N+1 consultas en la vista).
  Future<List<Map<String, dynamic>>> obtenerTodos() async {
    final db = await dbHelper.database;
    await _liberarVencidos(db);

    return db.rawQuery('''
      SELECT Apartados.*, Clientes.nombre as cliente_nombre,
        (Apartados.total - IFNULL(
          (SELECT SUM(monto) FROM Apartado_Abonos WHERE Apartado_Abonos.id_apartado = Apartados.id_apartado),
          0
        )) as saldo_pendiente
      FROM Apartados
      LEFT JOIN Clientes ON Clientes.id_cliente = Apartados.id_cliente
      ORDER BY Apartados.fecha_creacion DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> obtenerPorCliente(int idCliente) async {
    final db = await dbHelper.database;
    await _liberarVencidos(db);

    return db.rawQuery('''
      SELECT Apartados.*,
        (Apartados.total - IFNULL(
          (SELECT SUM(monto) FROM Apartado_Abonos WHERE Apartado_Abonos.id_apartado = Apartados.id_apartado),
          0
        )) as saldo_pendiente
      FROM Apartados
      WHERE Apartados.id_cliente = ?
      ORDER BY Apartados.fecha_creacion DESC
    ''', [idCliente]);
  }
}
