// Pruebas de la lógica de "poner en espera": el almacén en memoria
// (VentasEnEsperaStore) y los helpers del carrito (copiaItems/reemplazar) que
// permiten pausar una venta y retomarla sin que el snapshot se mute al seguir
// operando el carrito vivo.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/session/ventas_en_espera_store.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/models/carrito_venta.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  Producto producto(int id, {double precio = 10}) => Producto(
        idProducto: id,
        nombre: 'Producto $id',
        descripcion: '',
        precio: precio,
      );

  tearDown(() => VentasEnEsperaStore.instancia.limpiar());

  group('CarritoVenta.copiaItems', () {
    test('es una copia profunda: mutar el carrito no altera el snapshot', () {
      final carrito = CarritoVenta();
      carrito.agregar(producto(1));

      final copia = carrito.copiaItems();
      carrito.cambiarCantidad(0, 5); // ahora el carrito vivo tiene 6

      expect(copia.first['cantidad'], 1, reason: 'el snapshot no debe moverse');
      expect(carrito.items.first['cantidad'], 6);
    });
  });

  group('CarritoVenta.reemplazar', () {
    test('carga items y descuento global copiando las líneas', () {
      final origen = [
        {'id_producto': 1, 'nombre': 'A', 'precio': 10.0, 'cantidad': 2},
      ];
      final carrito = CarritoVenta();

      carrito.reemplazar(
        nuevosItems: origen,
        descuentoGlobalTipo: TipoDescuento.porcentaje,
        descuentoGlobalValor: 10,
      );

      expect(carrito.items, hasLength(1));
      expect(carrito.descuentoGlobalTipo, TipoDescuento.porcentaje);
      expect(carrito.descuentoGlobalValor, 10);

      // Mutar el carrito no debe tocar la lista de origen (se copió).
      carrito.cambiarCantidad(0, 3);
      expect(origen.first['cantidad'], 2);
    });
  });

  group('VentasEnEsperaStore', () {
    test('guarda con folios incrementales y permite retomar/descartar', () {
      final store = VentasEnEsperaStore.instancia;
      expect(store.hayVentas, isFalse);

      final v1 = store.guardar(items: [
        {'id_producto': 1, 'nombre': 'A', 'precio': 10.0, 'cantidad': 1},
      ]);
      final v2 = store.guardar(items: [
        {'id_producto': 2, 'nombre': 'B', 'precio': 20.0, 'cantidad': 2},
      ]);

      expect(v1.folio, 1);
      expect(v2.folio, 2);
      expect(store.cantidad, 2);
      expect(v2.totalUnidades, 2);
      expect(v2.subtotalAproximado, 40.0);

      store.eliminar(v1);
      expect(store.cantidad, 1);
      expect(store.ventas.single.folio, 2);
    });
  });
}
