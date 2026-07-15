// Pruebas del motor de cálculo de descuentos (puro, sin base de datos ni
// Flutter): porcentaje/fijo por línea, descuento global, combinación de
// ambos, límites inválidos y que el total nunca sea negativo.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/descuento_utils.dart';

void main() {
  Map<String, dynamic> item({
    required int id,
    required String nombre,
    required double precio,
    required int cantidad,
    TipoDescuento? tipo,
    double valor = 0,
  }) {
    return {
      'id_producto': id,
      'nombre': nombre,
      'precio': precio,
      'cantidad': cantidad,
      'descuento_tipo': tipo,
      'descuento_valor': valor,
    };
  }

  group('calcularMontoDescuento', () {
    test('sin tipo o valor 0 no aplica descuento', () {
      final r = calcularMontoDescuento(tipo: null, valor: 0, base: 100);
      expect(r.monto, 0);
      expect(r.porcentajeEfectivo, 0);
    });

    test('porcentaje calcula correctamente el monto y el % efectivo', () {
      final r = calcularMontoDescuento(tipo: TipoDescuento.porcentaje, valor: 25, base: 200);
      expect(r.monto, 50.0);
      expect(r.porcentajeEfectivo, 25.0);
    });

    test('fijo calcula el % efectivo respecto a la base', () {
      final r = calcularMontoDescuento(tipo: TipoDescuento.fijo, valor: 30, base: 200);
      expect(r.monto, 30.0);
      expect(r.porcentajeEfectivo, 15.0);
    });

    test('rechaza porcentaje mayor a 100', () {
      expect(
        () => calcularMontoDescuento(tipo: TipoDescuento.porcentaje, valor: 101, base: 100),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza fijo mayor a la base', () {
      expect(
        () => calcularMontoDescuento(tipo: TipoDescuento.fijo, valor: 150, base: 100),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza valores negativos', () {
      expect(
        () => calcularMontoDescuento(tipo: TipoDescuento.porcentaje, valor: -5, base: 100),
        throwsA(isA<Exception>()),
      );
      expect(
        () => calcularMontoDescuento(tipo: TipoDescuento.fijo, valor: -5, base: 100),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('calcularVenta', () {
    test('sin descuentos: total == subtotal', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 3)],
        descuentoMaximoPorcentaje: 20,
      );
      expect(v.subtotal, 30.0);
      expect(v.descuentoTotal, 0);
      expect(v.total, 30.0);
      expect(v.requiereAutorizacion, isFalse);
    });

    test('descuento porcentual por producto', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 2, tipo: TipoDescuento.porcentaje, valor: 10)],
        descuentoMaximoPorcentaje: 50,
      );
      // subtotalLinea 20, 10% = 2
      expect(v.subtotal, 20.0);
      expect(v.lineas.first.descuentoMonto, 2.0);
      expect(v.descuentoTotal, 2.0);
      expect(v.total, 18.0);
      expect(v.lineas.first.precioNetoUnitario, 9.0); // (20-2)/2
    });

    test('descuento fijo por producto', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 2, tipo: TipoDescuento.fijo, valor: 5)],
        descuentoMaximoPorcentaje: 50,
      );
      expect(v.subtotal, 20.0);
      expect(v.lineas.first.descuentoMonto, 5.0);
      expect(v.total, 15.0);
    });

    test('descuento global porcentual', () {
      final v = calcularVenta(
        carrito: [
          item(id: 1, nombre: 'A', precio: 10, cantidad: 2),
          item(id: 2, nombre: 'B', precio: 5, cantidad: 2),
        ],
        descuentoGlobalTipo: TipoDescuento.porcentaje,
        descuentoGlobalValor: 10,
        descuentoMaximoPorcentaje: 50,
      );
      // subtotal = 20 + 10 = 30; 10% global = 3
      expect(v.subtotal, 30.0);
      expect(v.descuentoGlobalMonto, 3.0);
      expect(v.total, 27.0);
      // Se reparte proporcionalmente: línea A (20/30) -> 2.0, línea B (10/30) -> 1.0
      expect(v.lineas[0].precioNetoUnitario, 9.0); // (20-2)/2
      expect(v.lineas[1].precioNetoUnitario, 4.5); // (10-1)/2
    });

    test('descuento global fijo', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 4)],
        descuentoGlobalTipo: TipoDescuento.fijo,
        descuentoGlobalValor: 8,
        descuentoMaximoPorcentaje: 50,
      );
      expect(v.subtotal, 40.0);
      expect(v.descuentoGlobalMonto, 8.0);
      expect(v.total, 32.0);
    });

    test('combinación de descuento por producto y global', () {
      final v = calcularVenta(
        carrito: [
          item(id: 1, nombre: 'A', precio: 100, cantidad: 1, tipo: TipoDescuento.porcentaje, valor: 10), // -10
        ],
        descuentoGlobalTipo: TipoDescuento.fijo,
        descuentoGlobalValor: 9,
        descuentoMaximoPorcentaje: 50,
      );
      // subtotal 100, línea -10 -> baseGlobal 90, global fijo -9 -> total 81
      expect(v.subtotal, 100.0);
      expect(v.lineas.first.descuentoMonto, 10.0);
      expect(v.descuentoGlobalMonto, 9.0);
      expect(v.descuentoTotal, 19.0);
      expect(v.total, 81.0);
      expect(v.lineas.first.precioNetoUnitario, 81.0);
    });

    test('el remanente de redondeo del reparto global lo absorbe la última línea', () {
      final v = calcularVenta(
        carrito: [
          item(id: 1, nombre: 'A', precio: 10, cantidad: 1),
          item(id: 2, nombre: 'B', precio: 10, cantidad: 1),
          item(id: 3, nombre: 'C', precio: 10, cantidad: 1),
        ],
        descuentoGlobalTipo: TipoDescuento.fijo,
        descuentoGlobalValor: 10,
        descuentoMaximoPorcentaje: 100,
      );
      final sumaAsignada = v.lineas.fold<double>(
        0,
        (s, l) => s + (l.subtotalLinea - l.montoNeto),
      );
      expect(sumaAsignada, 10.0); // cuadra exactamente con el descuento global
    });

    test('requiereAutorizacion se activa si una línea supera el umbral', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1, tipo: TipoDescuento.porcentaje, valor: 30)],
        descuentoMaximoPorcentaje: 20,
      );
      expect(v.requiereAutorizacion, isTrue);
    });

    test('requiereAutorizacion se activa si el descuento global supera el umbral', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1)],
        descuentoGlobalTipo: TipoDescuento.porcentaje,
        descuentoGlobalValor: 25,
        descuentoMaximoPorcentaje: 20,
      );
      expect(v.requiereAutorizacion, isTrue);
    });

    test('requiereAutorizacion permanece falso justo en el umbral', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1, tipo: TipoDescuento.porcentaje, valor: 20)],
        descuentoMaximoPorcentaje: 20,
      );
      expect(v.requiereAutorizacion, isFalse);
    });

    test('el total nunca es negativo incluso combinando descuentos altos', () {
      final v = calcularVenta(
        carrito: [item(id: 1, nombre: 'A', precio: 100, cantidad: 1, tipo: TipoDescuento.porcentaje, valor: 100)],
        descuentoGlobalTipo: TipoDescuento.porcentaje,
        descuentoGlobalValor: 100,
        descuentoMaximoPorcentaje: 100,
      );
      expect(v.total, greaterThanOrEqualTo(0));
      expect(v.total, 0.0);
    });

    test('carrito vacío no lanza y devuelve todo en cero', () {
      final v = calcularVenta(carrito: [], descuentoMaximoPorcentaje: 20);
      expect(v.subtotal, 0);
      expect(v.total, 0);
      expect(v.lineas, isEmpty);
    });

    test('propaga la excepción si un descuento de línea es inválido', () {
      expect(
        () => calcularVenta(
          carrito: [item(id: 1, nombre: 'A', precio: 10, cantidad: 1, tipo: TipoDescuento.fijo, valor: 50)],
          descuentoMaximoPorcentaje: 100,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
