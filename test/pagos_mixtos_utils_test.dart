// Pruebas puras (sin base de datos) de validarPagosMixtos: la regla de
// negocio central de Pagos Mixtos. Casos derivados directamente de los
// ejemplos dados para una venta de $850: el cambio solo puede originarse de
// efectivo, y en cuanto hay un método no-efectivo en la mezcla, la suma debe
// coincidir exactamente con el total.
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/core/utils/pagos_mixtos.dart';

void main() {
  group('un solo método', () {
    test('efectivo exacto es válido, sin cambio', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Efectivo', monto: 850)],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 0);
      expect(r.restante, 0);
    });

    test('efectivo con exceso es válido y calcula el cambio', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Efectivo', monto: 1000)],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 150);
    });

    test('tarjeta exacta es válida, sin cambio', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Tarjeta', monto: 850)],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 0);
    });

    test('tarjeta con exceso es inválida (no puede generar cambio)', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Tarjeta', monto: 1000)],
      );
      expect(r.esValido, isFalse);
      expect(r.cambio, 0);
    });

    test('tarjeta insuficiente es inválida', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Tarjeta', monto: 900 - 950)],
      );
      expect(r.esValido, isFalse);
    });

    test('tarjeta por 900 sobre una venta de 850 es inválida', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Tarjeta', monto: 900)],
      );
      expect(r.esValido, isFalse);
    });
  });

  group('varios métodos', () {
    test('efectivo + tarjeta que suman exacto el total es válido, sin cambio', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 500),
          PagoIngresado(metodoPago: 'Tarjeta', monto: 350),
        ],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 0);
      expect(r.totalPagado, 850);
    });

    test('efectivo + tarjeta + transferencia que suman exacto es válido', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 300),
          PagoIngresado(metodoPago: 'Tarjeta', monto: 200),
          PagoIngresado(metodoPago: 'Transferencia', monto: 350),
        ],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 0);
    });

    test('efectivo con exceso + tarjeta es inválido aunque el exceso "sea" del lado efectivo', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 1000),
          PagoIngresado(metodoPago: 'Tarjeta', monto: 100),
        ],
      );
      expect(r.esValido, isFalse);
      expect(r.cambio, 0);
    });

    test('mixto que no cubre el total queda incompleto (restante > 0)', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 300),
          PagoIngresado(metodoPago: 'Tarjeta', monto: 200),
        ],
      );
      expect(r.esValido, isFalse);
      expect(r.restante, 350);
    });
  });

  group('validaciones estructurales', () {
    test('lista vacía es inválida', () {
      final r = validarPagosMixtos(total: 850, pagos: const []);
      expect(r.esValido, isFalse);
    });

    test('monto negativo es inválido', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [PagoIngresado(metodoPago: 'Efectivo', monto: -10)],
      );
      expect(r.esValido, isFalse);
    });

    test('método duplicado es inválido', () {
      final r = validarPagosMixtos(
        total: 850,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 400),
          PagoIngresado(metodoPago: 'efectivo', monto: 450),
        ],
      );
      expect(r.esValido, isFalse);
    });

    test('redondea centavos consistentemente (sin falsos "restante" por error de punto flotante)', () {
      final r = validarPagosMixtos(
        total: 10.1,
        pagos: const [
          PagoIngresado(metodoPago: 'Efectivo', monto: 3.3),
          PagoIngresado(metodoPago: 'Tarjeta', monto: 6.8),
        ],
      );
      expect(r.esValido, isTrue);
      expect(r.cambio, 0);
    });
  });

  test('esMetodoEfectivo es insensible a mayúsculas (compatibilidad con datos legacy)', () {
    expect(esMetodoEfectivo('efectivo'), isTrue);
    expect(esMetodoEfectivo('Efectivo'), isTrue);
    expect(esMetodoEfectivo('EFECTIVO'), isTrue);
    expect(esMetodoEfectivo('Tarjeta'), isFalse);
  });
}
