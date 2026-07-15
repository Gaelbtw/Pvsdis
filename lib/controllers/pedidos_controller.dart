import '../core/database/database_helper.dart';
import '../models/pedidos_model.dart';
import 'producto_controller.dart';

class PedidosController {
  final _productoService = ProductoController();

  /*Future<int> crearPedido(Pedidos pedido) async {
    final db = await DatabaseHelper().database;
    return await db.insert('Pedidos', pedido.toMap());
  }*/

  Future<int> crearPedido(Pedidos pedido) async {

  final db = await DatabaseHelper().database;
  return await db.insert('Pedidos',pedido.toMap(),);
}

  Future<List<Pedidos>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query('Pedidos');

    return result.map((e) => Pedidos.fromMap(e)).toList();
  }

  Future<List<Map<String, dynamic>>> obtenerPedidosConCliente() async {
    final db = await DatabaseHelper().database;

    return await db.rawQuery('''
      SELECT 
        p.*,
        c.nombre as cliente_nombre,
        c.telefono as cliente_telefono
      FROM Pedidos p
      LEFT JOIN Clientes c
        ON p.id_cliente = c.id_cliente
      ORDER BY p.id_pedido DESC
    ''');
  }

  Future<int> cambiarEstado(int id, String estado) async {
    final db = await DatabaseHelper().database;

    return await db.update(
      'Pedidos',
      {"estado": estado},
      where: "id_pedido = ?",
      whereArgs: [id],
    );
  }

  Future<int> actualizar(Pedidos pedido) async {
    final db = await DatabaseHelper().database;

    return await db.update(
      'Pedidos',
      pedido.toMap(),
      where: 'id_pedido = ?',
      whereArgs: [pedido.idPedido],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;

    return await db.delete(
      'Pedidos',
      where: 'id_pedido = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertarDetalle(
    int idPedido,
    int idProducto,
    int cantidad,
    double precio,
  ) async {
    final db = await DatabaseHelper().database;
    await db.insert('Detalle_Pedido', {
      'id_pedido': idPedido,
      'id_producto': idProducto,
      'cantidad': cantidad,
      'precio': precio,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerDetalle(int idPedido) async {
    final db = await DatabaseHelper().database;
    return await db.query(
      'Detalle_Pedido',
      where: 'id_pedido = ?',
      whereArgs: [idPedido],
    );
  }

  /// Crea el pedido y todas sus líneas de detalle como una sola operación
  /// atómica: si falla a la mitad (por ejemplo en la línea 3 de 10), no
  /// queda un pedido a medio guardar.
  Future<int> crearPedidoCompleto(
    Pedidos pedido,
    List<Map<String, dynamic>> itemsDetalle,
  ) async {
    final db = await DatabaseHelper().database;

    return await db.transaction((txn) async {
      final idPedido = await txn.insert('Pedidos', pedido.toMap());

      for (final item in itemsDetalle) {
        await txn.insert('Detalle_Pedido', {
          'id_pedido': idPedido,
          'id_producto': item['id_producto'],
          'cantidad': item['cantidad'],
          'precio': item['precio'],
        });
      }

      return idPedido;
    });
  }

  /// Actualiza el pedido y, si el cambio de estado implica entregar o
  /// cancelar una entrega ya hecha, ajusta el inventario de cada producto
  /// del detalle — todo en una sola transacción, para no dejar el
  /// inventario ajustado solo parcialmente si algo falla a la mitad.
  Future<void> cambiarEstadoConAjusteInventario(
    Pedidos pedidoActualizado,
    String estadoAnterior,
  ) async {
    final db = await DatabaseHelper().database;

    await db.transaction((txn) async {
      await txn.update(
        'Pedidos',
        pedidoActualizado.toMap(),
        where: 'id_pedido = ?',
        whereArgs: [pedidoActualizado.idPedido],
      );

      final seEntrego = pedidoActualizado.estado == 'Entregado' &&
          estadoAnterior != 'Entregado';
      final seCanceloUnaEntrega = pedidoActualizado.estado == 'Cancelado' &&
          estadoAnterior == 'Entregado';

      if (!seEntrego && !seCanceloUnaEntrega) return;

      final detalle = await txn.query(
        'Detalle_Pedido',
        where: 'id_pedido = ?',
        whereArgs: [pedidoActualizado.idPedido],
      );

      for (final item in detalle) {
        final idProducto = item['id_producto'] as int;
        final cantidad = item['cantidad'] as int;

        if (seEntrego) {
          await _productoService.deducirStockPedido(
            idProducto,
            cantidad,
            executor: txn,
          );
        } else {
          await _productoService.restaurarStockPedido(
            idProducto,
            cantidad,
            executor: txn,
          );
        }
      }
    });
  }
}
