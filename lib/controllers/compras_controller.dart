import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';

class ComprasController {
  // INSERTAR COMPRA COMPLETA
  Future<void> insertarCompraCompleta(
    List<Map<String, dynamic>> carrito,
    double total,
    int idProveedor,
  ) async {
    final db = await DatabaseHelper().database;

    // 1. INSERTAR COMPRA (CABECERA)
    final idCompra = await db.insert('Compras', {
      "fecha": DateTime.now().toIso8601String(),
      "total": total,
      "id_proveedor": idProveedor,
      "id_usuario": SessionManager.currentUserId ?? 1,
    });

    // INSERTAR DETALLE + ACTUALIZAR INVENTARIO
    for (var item in carrito) {

      // detalle compra
      await db.insert('Detalle_Compra', {
        "id_compra": idCompra,
        "id_producto": item['id_producto'],
        "cantidad": item['cantidad'],
        "precio": item['precio_compra'] ?? 0,
      });

      // actualizar inventario (SUMA STOCK)
      await db.rawUpdate(
        '''
        UPDATE Inventario 
        SET cantidad = cantidad + ? 
        WHERE id_producto = ?
        ''',
        [
          item['cantidad'],
          item['id_producto'],
        ],
      );
    }
  }

  // OBTENER TODAS LAS COMPRAS
  Future<List<Map<String, dynamic>>> obtenerCompras() async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT c.*, p.nombre as proveedor
      FROM Compras c
      LEFT JOIN Proveedores p ON c.id_proveedor = p.id_proveedor
      ORDER BY c.fecha DESC
    ''');
  }

  // DETALLE DE UNA COMPRA
  Future<List<Map<String, dynamic>>> detalleCompra(int idCompra) async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT d.*, pr.nombre
      FROM Detalle_Compra d
      INNER JOIN Producto pr ON d.id_producto = pr.id_producto
      WHERE d.id_compra = ?
    ''', [idCompra]);
  }

  // ELIMINAR COMPRA (opcional avanzado)
  Future<void> eliminarCompra(int idCompra) async {
    final db = await DatabaseHelper().database;

    // obtener detalles
    final detalles = await db.query(
      'Detalle_Compra',
      where: 'id_compra = ?',
      whereArgs: [idCompra],
    );

    // revertir inventario
    for (var item in detalles) {
      await db.rawUpdate(
        '''
        UPDATE Inventario 
        SET cantidad = cantidad - ? 
        WHERE id_producto = ?
        ''',
        [
          item['cantidad'] ?? 0,
          item['id_producto'],
        ],
      );
    }

    // borrar detalle
    await db.delete(
      'Detalle_Compra',
      where: 'id_compra = ?',
      whereArgs: [idCompra],
    );

    // borrar compra
    await db.delete(
      'Compras',
      where: 'id_compra = ?',
      whereArgs: [idCompra],
    );
  }
}
