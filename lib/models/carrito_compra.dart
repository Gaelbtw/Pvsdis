import 'producto_model.dart';

/// Lógica de negocio del carrito de una compra: agregar productos, cambiar
/// cantidades y calcular el total. Antes vivía mezclada directamente en los
/// métodos del `State` de `compras_view.dart` (análogo a `CarritoVenta`,
/// pero con la clave `precio_compra` en vez de `precio`).
class CarritoCompra {
  final List<Map<String, dynamic>> items = [];

  int indexDeProducto(int? idProducto) =>
      items.indexWhere((i) => i['id_producto'] == idProducto);

  void agregar(Producto producto) {
    final index = indexDeProducto(producto.idProducto);

    if (index >= 0) {
      items[index]['cantidad']++;
    } else {
      items.add({
        "id_producto": producto.idProducto,
        "nombre": producto.nombre,
        "precio_compra": producto.precioCompra ?? 0,
        "cantidad": 1,
      });
    }
  }

  void cambiarCantidad(int index, int delta) {
    items[index]['cantidad'] += delta;

    if (items[index]['cantidad'] <= 0) {
      items.removeAt(index);
    }
  }

  double get total => items.fold(
        0,
        (sum, item) => sum + ((item['precio_compra'] ?? 0) * item['cantidad']),
      );

  bool get estaVacio => items.isEmpty;

  void limpiar() => items.clear();
}
