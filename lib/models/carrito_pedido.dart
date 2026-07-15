import 'producto_model.dart';

/// Datos del carrito al armar un pedido: agregar productos, ajustar
/// cantidades y calcular el total. Antes vivía mezclado directamente en los
/// métodos del `State` de `crearPedido_view.dart`.
///
/// A diferencia de [CarritoVenta]/[CarritoCompra] (que guardan campos
/// planos), aquí cada ítem conserva el [Producto] completo porque la vista
/// lo necesita para mostrar stock, descripción, etc. Las validaciones de
/// stock disponible (mostrar diálogos de advertencia) se quedan en la
/// vista, ya que son de presentación, no de datos.
class CarritoPedido {
  final List<Map<String, dynamic>> items = [];

  int indexDeProducto(int? idProducto) => items.indexWhere(
        (e) => (e['producto'] as Producto).idProducto == idProducto,
      );

  int cantidadEnCarrito(int? idProducto) {
    final index = indexDeProducto(idProducto);
    return index >= 0 ? items[index]['cantidad'] as int : 0;
  }

  void agregar(Producto producto) {
    final index = indexDeProducto(producto.idProducto);

    if (index >= 0) {
      items[index]['cantidad'] += 1;
    } else {
      items.add({'producto': producto, 'cantidad': 1});
    }
  }

  void aumentar(int index) => items[index]['cantidad']++;

  /// Devuelve `true` si el ítem se eliminó del carrito (cantidad llegó a 0).
  bool disminuir(int index) {
    if (items[index]['cantidad'] > 1) {
      items[index]['cantidad']--;
      return false;
    }

    items.removeAt(index);
    return true;
  }

  double get total {
    double nuevo = 0;
    for (final item in items) {
      final producto = item['producto'] as Producto;
      final cantidad = item['cantidad'] as int;
      nuevo += producto.precio * cantidad;
    }
    return nuevo;
  }

  bool get estaVacio => items.isEmpty;

  List<Map<String, dynamic>> paraGuardar() {
    return items.map((item) {
      final producto = item['producto'] as Producto;
      final cantidad = item['cantidad'] as int;
      return {
        'id_producto': producto.idProducto,
        'cantidad': cantidad,
        'precio': producto.precio,
      };
    }).toList();
  }
}
