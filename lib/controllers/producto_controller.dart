//import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../models/producto_model.dart';
import 'auditoria_controller.dart';

class ProductoService {
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Producto producto, int stockInicial) async {
  final db = await DatabaseHelper().database;

  if (producto.precio <= 0) {
    throw Exception("Precio inválido");
  }

  if (stockInicial < 0) {
    throw Exception("Stock inválido");
  }

  int id = await db.insert('Producto', producto.toMap());

  await db.insert('Inventario', {
    "id_producto": id,
    "cantidad": stockInicial,
  });

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

    final rows = await db.update(
      'Producto',
      producto.toMap(),
      where: 'id_producto = ?',
      whereArgs: [producto.idProducto],
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

    final rows = await db.delete(
      'Producto',
      where: 'id_producto = ?',
      whereArgs: [id],
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
        IFNULL(i.cantidad, 0) as cantidad,
        c.nombre as categoria_nombre
      FROM Producto p
      LEFT JOIN Inventario i ON p.id_producto = i.id_producto
      LEFT JOIN Categorias c ON p.id_categoria = c.id_categoria
    ''');
  }

  Future<void> agregarStock(int idProducto, int cantidadNueva) async {
    final db = await DatabaseHelper().database;
    final producto = await _obtenerNombreProducto(db, idProducto);

    if (cantidadNueva <= 0) {
      throw Exception("Cantidad inválida");
    }

    final result = await db.query(
      "Inventario",
      where: "id_producto = ?",
      whereArgs: [idProducto],
    );

    int actual = result.first["cantidad"] as int;
    int nuevo = actual + cantidadNueva;

    await db.update(
      "Inventario",
      {"cantidad": nuevo},
      where: "id_producto = ?",
      whereArgs: [idProducto],
    );

    await _auditoriaController.registrar(
      tabla: 'Inventario',
      accion: 'EDIT',
      idRegistro: idProducto,
      descripcion:
          'Stock de $producto aumentado de $actual a $nuevo (+$cantidadNueva)',
    );
  }

  Future<void> restarStock(int idProducto, int cantidad) async {
    final db = await DatabaseHelper().database;

    final result = await db.query(
      "Inventario",
      where: "id_producto = ?",
      whereArgs: [idProducto],
    );

    int actual = result.first["cantidad"] as int;

    if (cantidad > actual) {
      throw Exception("Stock insuficiente");
    }

    await db.update(
      "Inventario",
      {"cantidad": actual - cantidad},
      where: "id_producto = ?",
      whereArgs: [idProducto],
    );

    await _auditoriaController.registrar(
      tabla: 'Inventario',
      accion: 'EDIT',
      idRegistro: idProducto,
      descripcion:
          'Stock de ${await _obtenerNombreProducto(db, idProducto)} reducido de $actual a ${actual - cantidad} (-$cantidad)',
    );
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

