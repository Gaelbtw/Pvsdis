import '../core/utils/descuento_utils.dart';
import 'producto_model.dart';

/// Lógica de negocio del carrito de una venta: agregar productos, cambiar
/// cantidades, aplicar descuentos y calcular el total. Antes esto vivía
/// mezclado directamente en los métodos del `State` de `ventas_view.dart`.
class CarritoVenta {
  final List<Map<String, dynamic>> items = [];

  /// Descuento global de la venta completa (además de los descuentos por
  /// producto que pueda traer cada línea de [items]).
  TipoDescuento? descuentoGlobalTipo;
  double descuentoGlobalValor = 0;

  int indexDeProducto(int? idProducto) =>
      items.indexWhere((i) => i['id_producto'] == idProducto);

  bool contieneProducto(int? idProducto) => indexDeProducto(idProducto) >= 0;

  int cantidadEnCarrito(int? idProducto) {
    final index = indexDeProducto(idProducto);
    return index >= 0 ? items[index]['cantidad'] as int : 0;
  }

  void agregar(Producto producto) {
    final index = indexDeProducto(producto.idProducto);

    if (index >= 0) {
      items[index]['cantidad']++;
    } else {
      items.add({
        "id_producto": producto.idProducto,
        "nombre": producto.nombre,
        "precio": producto.precio,
        "cantidad": 1,
        "descuento_tipo": null,
        "descuento_valor": 0.0,
      });
    }
  }

  /// Aplica (o reemplaza) el descuento de un producto específico del
  /// carrito. La validación de reglas (negativos, %>100, fijo>subtotal)
  /// vive en `calcularVenta`/`calcularMontoDescuento`, no aquí.
  void aplicarDescuentoLinea(int index, TipoDescuento tipo, double valor) {
    items[index]['descuento_tipo'] = tipo;
    items[index]['descuento_valor'] = valor;
  }

  void quitarDescuentoLinea(int index) {
    items[index]['descuento_tipo'] = null;
    items[index]['descuento_valor'] = 0.0;
  }

  void aplicarDescuentoGlobal(TipoDescuento tipo, double valor) {
    descuentoGlobalTipo = tipo;
    descuentoGlobalValor = valor;
  }

  void quitarDescuentoGlobal() {
    descuentoGlobalTipo = null;
    descuentoGlobalValor = 0;
  }

  /// Ajusta la cantidad del ítem en [index]. Devuelve `true` si el ítem se
  /// eliminó del carrito (la cantidad llegó a 0 o menos).
  bool cambiarCantidad(int index, int delta) {
    items[index]['cantidad'] += delta;

    if (items[index]['cantidad'] <= 0) {
      items.removeAt(index);
      return true;
    }

    return false;
  }

  double get total {
    return items.fold(
      0,
      (sum, item) => sum + (item['precio'] * item['cantidad']),
    );
  }

  bool get estaVacio => items.isEmpty;

  void limpiar() {
    items.clear();
    quitarDescuentoGlobal();
  }
}
