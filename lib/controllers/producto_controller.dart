import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/database/db_exceptions.dart';
import '../models/producto_model.dart';
import 'auditoria_controller.dart';

/// Única fuente de verdad para operaciones sobre productos e inventario.
/// (Antes existían dos clases distintas con el mismo nombre en archivos
/// separados; se unificaron aquí.)
class ProductoController {
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Producto producto, int stockInicial) async {
    final db = await DatabaseHelper().database;

    if (producto.precio <= 0) {
      throw Exception("Precio inválido");
    }

    if (stockInicial < 0) {
      throw Exception("Stock inválido");
    }

    final id = await ejecutarConMensajeDeDuplicado(
      () => db.transaction((txn) async {
        final nuevoId = await DatabaseHelper.insertarConGuidSync(txn, 'Producto', producto.toMap());

        await DatabaseHelper.insertarConGuidSync(txn, 'Inventario', {
          "id_producto": nuevoId,
          "cantidad": stockInicial,
        });

        return nuevoId;
      }),
      'Ya existe un producto con ese código de barras.',
    );

    await _auditoriaController.registrar(
      tabla: 'Productos',
      accion: 'CREATE',
      idRegistro: id,
      descripcion: 'Producto ${producto.nombre} creado con stock $stockInicial',
    );

    return id;
  }

  Future<List<Producto>> obtenerProductosConPrecioCompra() async {
    final db = await DatabaseHelper().database;
    final result = await db.query('Producto');

    return result.map((e) => Producto.fromMap(e)).toList();
  }

  Future<List<Producto>> obtenerTodos() async {
    final db = await DatabaseHelper().database;

    final result = await db.rawQuery('''
      SELECT
        p.*,
        c.nombre as categoria_nombre
      FROM Producto p
      LEFT JOIN Categorias c
        ON p.id_categoria = c.id_categoria
    ''');

    return result.map((e) => Producto.fromMap(e)).toList();
  }

  Future<int> actualizar(Producto producto) async {
    final db = await DatabaseHelper().database;

    final rows = await ejecutarConMensajeDeDuplicado(
      () => db.update(
        'Producto',
        producto.toMap(),
        where: 'id_producto = ?',
        whereArgs: [producto.idProducto],
      ),
      'Ya existe un producto con ese código de barras.',
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Productos',
        accion: 'EDIT',
        idRegistro: producto.idProducto,
        descripcion: 'Producto ${producto.nombre} modificado',
      );
    }

    return rows;
  }

  Future<void> actualizarStock(
    int idProducto,
    int cantidadNueva,
  ) async {
    final db = await DatabaseHelper().database;
    final producto = await _obtenerNombreProducto(db, idProducto);
    final stockAnterior = await _obtenerStockActual(db, idProducto);

    await db.update(
      "Inventario",
      {
        "cantidad": cantidadNueva,
      },
      where: "id_producto = ?",
      whereArgs: [idProducto],
    );

    await _auditoriaController.registrar(
      tabla: 'Inventario',
      accion: 'EDIT',
      idRegistro: idProducto,
      descripcion:
          'Stock de $producto modificado de $stockAnterior a $cantidadNueva',
    );
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;
    final producto = await _obtenerNombreProducto(db, id);

    final rows = await ejecutarConMensajeDeIntegridad(
      () => db.delete(
        'Producto',
        where: 'id_producto = ?',
        whereArgs: [id],
      ),
      'No se puede eliminar: el producto tiene ventas, compras o pedidos registrados.',
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Productos',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: 'Producto $producto eliminado',
      );
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> obtenerConStock() async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT
        p.id_producto,
        p.nombre,
        p.precio,
        p.categoria,
        p.estado,
        p.stock_minimo,
        p.id_categoria,
        p.codigo_barras,
        IFNULL(i.cantidad, 0) as cantidad,
        IFNULL(i.cantidad_reservada, 0) as cantidad_reservada,
        IFNULL(i.cantidad, 0) - IFNULL(i.cantidad_reservada, 0) as disponible,
        c.nombre as categoria_nombre
      FROM Producto p
      LEFT JOIN Inventario i ON p.id_producto = i.id_producto
      LEFT JOIN Categorias c ON p.id_categoria = c.id_categoria
    ''');
  }

  /// Busca un producto por coincidencia exacta de código de barras (uso
  /// típico: lector USB). Devuelve `null` si no hay ninguno con ese código.
  Future<Producto?> buscarPorCodigoBarras(String codigo) async {
    final normalizado = Producto.normalizarCodigoBarras(codigo);
    if (normalizado == null) return null;

    final db = await DatabaseHelper().database;
    final result = await db.query(
      'Producto',
      where: 'codigo_barras = ?',
      whereArgs: [normalizado],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return Producto.fromMap(result.first);
  }

  /// Indica si ya existe un producto con ese código de barras. [excluirId]
  /// se usa al editar, para no contar el propio producto como duplicado.
  Future<bool> existeCodigoBarras(String codigo, {int? excluirId}) async {
    final normalizado = Producto.normalizarCodigoBarras(codigo);
    if (normalizado == null) return false;

    final db = await DatabaseHelper().database;
    final result = await db.query(
      'Producto',
      columns: ['id_producto'],
      where: excluirId == null
          ? 'codigo_barras = ?'
          : 'codigo_barras = ? AND id_producto != ?',
      whereArgs: excluirId == null ? [normalizado] : [normalizado, excluirId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  Future<void> agregarStock(int idProducto, int cantidadNueva) async {
    final db = await DatabaseHelper().database;

    if (cantidadNueva <= 0) {
      throw Exception("Cantidad inválida");
    }

    final producto = await _obtenerNombreProducto(db, idProducto);
    // Solo para el mensaje de auditoría; el incremento real se hace de
    // forma atómica abajo para evitar que dos ventas/compras concurrentes
    // sobre el mismo producto se pisen entre sí (lost update).
    final actual = await _obtenerStockActual(db, idProducto);

    final filas = await db.rawUpdate(
      'UPDATE Inventario SET cantidad = cantidad + ? WHERE id_producto = ?',
      [cantidadNueva, idProducto],
    );

    if (filas == 0) {
      throw Exception("El producto no tiene un registro de inventario");
    }

    final nuevo = actual + cantidadNueva;

    await _auditoriaController.registrar(
      tabla: 'Inventario',
      accion: 'EDIT',
      idRegistro: idProducto,
      descripcion:
          'Stock de $producto aumentado de $actual a $nuevo (+$cantidadNueva)',
    );
  }

  Future<Map<int, int>> obtenerStockMap() async {
    final db = await DatabaseHelper().database;
    final res = await db.query('Inventario');
    return {
      for (var row in res)
        (row['id_producto'] as int): (row['cantidad'] as int? ?? 0)
    };
  }

  /// Igual que [obtenerStockMap] pero resta lo ya reservado por Apartados
  /// (`cantidad - cantidad_reservada`): es lo que debe usarse para decidir
  /// cuánto se le puede vender a un cliente ahora mismo, para no ofrecer
  /// unidades que ya están comprometidas con otro cliente.
  Future<Map<int, int>> obtenerDisponibleMap() async {
    final db = await DatabaseHelper().database;
    final res = await db.query('Inventario');
    return {
      for (var row in res)
        (row['id_producto'] as int):
            (row['cantidad'] as int? ?? 0) - (row['cantidad_reservada'] as int? ?? 0)
    };
  }

  /// Descuenta stock sin lanzar excepción. Si no hay suficiente, deja en 0.
  /// Si [executor] se recibe (por ejemplo, una transacción de
  /// PedidosController), la operación participa en ella en vez de abrir su
  /// propia conexión.
  Future<void> deducirStockPedido(
    int idProducto,
    int cantidad, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper().database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = MAX(0, cantidad - ?)
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  /// Restaura stock (usado al cancelar un pedido ya entregado). Acepta
  /// [executor] por el mismo motivo que [deducirStockPedido].
  Future<void> restaurarStockPedido(
    int idProducto,
    int cantidad, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper().database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = cantidad + ?
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  /// Reserva stock para un Apartado recién creado: NO toca la existencia
  /// física (`cantidad`), solo marca esas unidades como comprometidas para
  /// que ninguna otra venta/apartado pueda ofrecerlas mientras tanto.
  Future<void> reservarStock(
    int idProducto,
    int cantidad, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper().database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad_reservada = cantidad_reservada + ?
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  /// Libera una reserva sin tocar la existencia física — se usa al cancelar
  /// un apartado o cuando uno vencido pierde su garantía de reserva.
  Future<void> liberarReserva(
    int idProducto,
    int cantidad, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper().database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad_reservada = MAX(0, cantidad_reservada - ?)
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  /// Convierte una reserva en una salida de stock definitiva (al liquidar
  /// un apartado): resta de la existencia física Y libera la reserva en el
  /// mismo `UPDATE`, para no duplicar movimientos de inventario (una reserva
  /// que se liquida nunca debe, además, volver a descontarse por separado).
  Future<void> confirmarReserva(
    int idProducto,
    int cantidad, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DatabaseHelper().database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = cantidad - ?,
          cantidad_reservada = MAX(0, cantidad_reservada - ?)
      WHERE id_producto = ?
    ''', [cantidad, cantidad, idProducto]);
  }

  Future<String> _obtenerNombreProducto(dynamic db, int idProducto) async {
    final result = await db.query(
      'Producto',
      columns: ['nombre'],
      where: 'id_producto = ?',
      whereArgs: [idProducto],
      limit: 1,
    );

    if (result.isEmpty) return 'Producto $idProducto';
    return result.first['nombre']?.toString() ?? 'Producto $idProducto';
  }

  Future<int> _obtenerStockActual(dynamic db, int idProducto) async {
    final result = await db.query(
      'Inventario',
      columns: ['cantidad'],
      where: 'id_producto = ?',
      whereArgs: [idProducto],
      limit: 1,
    );

    if (result.isEmpty) return 0;
    return int.tryParse(result.first['cantidad'].toString()) ?? 0;
  }
}
