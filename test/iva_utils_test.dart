// Pruebas del desglose de IVA por línea.
//
// El caso que motiva todo esto: un ticket que mezcla productos gravados y
// exentos. Aplicando la tasa general al total —como se hacía antes— el ticket
// cobra impuesto sobre lo exento y el desglose queda mal.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/iva_utils.dart';

void main() {
  group('con importes por línea', () {
    test('una sola tasa: base + IVA reconstruyen el total', () {
      final desglose = desglosarIva(
        lineas: [
          {'importe_neto': 116.0, 'iva_tasa': 16.0},
        ],
        tasaGeneral: 16,
        total: 116,
      );

      expect(desglose.base, 100);
      expect(desglose.iva, 16);
      expect(desglose.tasas, [16]);
      expect(desglose.tasasMixtas, isFalse);
    });

    test('una línea sin tasa propia usa la general', () {
      final desglose = desglosarIva(
        lineas: [
          {'importe_neto': 116.0},
        ],
        tasaGeneral: 16,
        total: 116,
      );

      expect(desglose.base, 100);
      expect(desglose.iva, 16);
    });

    test('mezcla de gravado y exento: el exento no paga impuesto', () {
      final desglose = desglosarIva(
        lineas: [
          {'importe_neto': 116.0, 'iva_tasa': 16.0}, // gravado
          {'importe_neto': 50.0, 'iva_tasa': 0.0}, // exento
        ],
        tasaGeneral: 16,
        total: 166,
      );

      expect(desglose.base, 150, reason: '100 del gravado + 50 del exento');
      expect(desglose.iva, 16, reason: 'solo el gravado aporta IVA');
      expect(desglose.base + desglose.iva, 166);
      expect(desglose.tasasMixtas, isTrue);
      expect(desglose.etiqueta, 'IVA (16.00%, 0.00%)');
    });

    test('el cálculo por línea no es el mismo que aplicar la tasa al total', () {
      const total = 166.0;
      final porLinea = desglosarIva(
        lineas: [
          {'importe_neto': 116.0, 'iva_tasa': 16.0},
          {'importe_neto': 50.0, 'iva_tasa': 0.0},
        ],
        tasaGeneral: 16,
        total: total,
      );

      final sobreElTotal = total - total / 1.16;
      expect(porLinea.iva, isNot(closeTo(sobreElTotal, 0.01)));
      expect(porLinea.iva, lessThan(sobreElTotal));
    });

    test('sin IVA en ninguna línea, no hay desglose que mostrar', () {
      final desglose = desglosarIva(
        lineas: [
          {'importe_neto': 50.0, 'iva_tasa': 0.0},
        ],
        tasaGeneral: 0,
        total: 50,
      );

      expect(desglose.hayIva, isFalse);
      expect(desglose.iva, 0);
    });
  });

  group('sin importes por línea (tickets viejos)', () {
    test('cae a la tasa general aplicada al total', () {
      final desglose = desglosarIva(
        lineas: [
          {'nombre': 'Algo', 'cantidad': 1},
        ],
        tasaGeneral: 16,
        total: 116,
      );

      expect(desglose.base, 100);
      expect(desglose.iva, 16);
      expect(desglose.etiqueta, 'IVA (16.00%)');
    });

    test('sin tasa general no hay IVA', () {
      final desglose = desglosarIva(lineas: [], tasaGeneral: 0, total: 100);
      expect(desglose.hayIva, isFalse);
    });
  });
}
