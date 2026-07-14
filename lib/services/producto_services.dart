
import '../core/database/database_helper.dart';
import '../models/producto_model.dart';

class ProductoService {
  final dbHelper = DatabaseHelper();

  Future<int> insertar(Producto producto, int stockInicial) async {
    final db = await dbHelper.database;

    if (producto.nombre.isEmpty) {
      throw Exception("El nombre es obligatorio");
    }

    if (producto.precio <= 0) {
      throw Exception("Precio inválido");
    }

    if (producto.categoriaId == null) {
      throw Exception("Selecciona una categoría");
    }

    if (stockInicial < 0) {
      throw Exception("Stock inválido");
    }
    int id = await db.insert('Producto', producto.toMap());

    await db.insert('Inventario', {
      'id_producto': id,
      'cantidad': stockInicial,
    });

    return id;
  }

  Future<List<Producto>> obtenerTodos() async {
    final db = await dbHelper.database;

    final res = await db.query('Producto');

    return res.map((e) => Producto.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> obtenerConStock() async {
    final db = await dbHelper.database;

    final res = await db.rawQuery('''
      SELECT
        p.id_producto,
        p.nombre,
        p.descripcion,
        p.precio,
        p.precio_compra,
        p.id_categoria,
        c.nombre as categoria_nombre,
        p.estado,
        p.stock_minimo,
        IFNULL(i.cantidad, 0) as cantidad
      FROM Producto p
      LEFT JOIN Inventario i
        ON p.id_producto = i.id_producto
      LEFT JOIN Categoria c
        ON p.id_categoria = c.id_categoria
    ''');

    return res;
  }

  // 🔥 ACTUALIZAR
  Future<int> actualizar(Producto producto) async {
    final db = await dbHelper.database;

    return await db.update(
      'Producto',
      producto.toMap(),
      where: 'id_producto = ?',
      whereArgs: [producto.idProducto],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await dbHelper.database;

    await db.delete('Inventario', where: 'id_producto = ?', whereArgs: [id]);

    return await db.delete('Producto', where: 'id_producto = ?', whereArgs: [id]);
  }

  Future<void> agregarStock(int idProducto, int cantidad) async {
    final db = await dbHelper.database;

    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = cantidad + ?
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  Future<void> actualizarStock(
    int idProducto,
    int nuevaCantidad,
  ) async {
    final db = await dbHelper.database;

    await db.update(
      'Inventario',
      {
        'cantidad': nuevaCantidad,
      },
      where: 'id_producto = ?',
      whereArgs: [idProducto],
    );
  }

  /// Descuenta stock sin lanzar excepción. Si no hay suficiente, deja en 0.
  Future<void> deducirStockPedido(int idProducto, int cantidad) async {
    final db = await dbHelper.database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = MAX(0, cantidad - ?)
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  /// Restaura stock (usado al cancelar un pedido ya entregado).
  Future<void> restaurarStockPedido(int idProducto, int cantidad) async {
    final db = await dbHelper.database;
    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = cantidad + ?
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }

  Future<Map<int, int>> obtenerStockMap() async {
    final db = await dbHelper.database;
    final res = await db.query('Inventario');
    return {
      for (var row in res)
        (row['id_producto'] as int): (row['cantidad'] as int? ?? 0)
    };
  }

  Future<void> restarStock(int idProducto, int cantidad) async {
    final db = await dbHelper.database;

    final res = await db.rawQuery(
        'SELECT cantidad FROM Inventario WHERE id_producto = ?', [idProducto]);

    int actual = res.first['cantidad'] as int;

    if (actual < cantidad) throw Exception("Stock insuficiente");

    await db.rawUpdate('''
      UPDATE Inventario
      SET cantidad = cantidad - ?
      WHERE id_producto = ?
    ''', [cantidad, idProducto]);
  }
}