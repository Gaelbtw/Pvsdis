// Pruebas del constructor de CSV. Es una función pura, así que se prueba
// entera sin base de datos ni widgets -- justamente por eso el escapado vive
// separado del código que toca disco.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/utils/csv.dart';

void main() {
  group('escaparCampoCsv', () {
    test('deja el texto simple tal cual', () {
      expect(escaparCampoCsv('Refresco'), 'Refresco');
    });

    test('null se convierte en celda vacía, no en la palabra "null"', () {
      expect(escaparCampoCsv(null), '');
    });

    test('entrecomilla cuando hay coma', () {
      expect(escaparCampoCsv('Refresco, 600ml'), '"Refresco, 600ml"');
    });

    test('duplica las comillas internas', () {
      expect(escaparCampoCsv('Tornillo 1/2"'), '"Tornillo 1/2"""');
    });

    test('entrecomilla cuando hay salto de línea', () {
      expect(escaparCampoCsv('Linea 1\nLinea 2'), '"Linea 1\nLinea 2"');
    });

    test('no toca los acentos', () {
      expect(escaparCampoCsv('Camión piñata ñ'), 'Camión piñata ñ');
    });

    // CSV injection: si Excel ve una celda que empieza con =, +, - o @, la
    // ejecuta como fórmula. Un nombre de producto lo escribe una persona.
    group('inyección de fórmulas', () {
      test('neutraliza una celda que empieza con =', () {
        expect(escaparCampoCsv('=1+1'), "'=1+1");
      });

      test('neutraliza =HYPERLINK(...)', () {
        final r = escaparCampoCsv('=HYPERLINK("http://malo","clic")');

        // El contenido lleva comas y comillas, así que la celda entera va
        // entrecomillada: la comilla simple protectora queda DENTRO, no al
        // principio del texto. El orden es entrecomillar después de
        // neutralizar, no al revés.
        expect(r.startsWith('"\'='), isTrue, reason: 'debe quedar como "\'=...');

        // Y las comillas internas van duplicadas (RFC 4180).
        expect(r.contains('""'), isTrue);
      });

      test('neutraliza +, - y @', () {
        expect(escaparCampoCsv('+A1'), "'+A1");
        expect(escaparCampoCsv('-2+3'), "'-2+3");
        expect(escaparCampoCsv('@SUM(A1)'), "'@SUM(A1)");
      });

      test('un número negativo normal sigue siendo legible', () {
        // Se antepone la comilla (empieza con '-'), que es el precio a pagar
        // por no ejecutar fórmulas. Los importes se exportan con montoCsv,
        // que no produce negativos con este problema en la práctica.
        expect(escaparCampoCsv('-5'), "'-5");
      });
    });
  });

  group('construirCsv', () {
    test('escribe BOM, encabezados y filas con CRLF', () {
      final csv = construirCsv(
        encabezados: ['Producto', 'Cantidad'],
        filas: [
          ['Refresco', 2],
          ['Pan', 3],
        ],
      );

      expect(csv.startsWith('\uFEFF'), isTrue, reason: 'Excel necesita el BOM para leer UTF-8');
      expect(csv, contains('Producto,Cantidad\r\n'));
      expect(csv, contains('Refresco,2\r\n'));
      expect(csv, contains('Pan,3\r\n'));
    });

    test('se puede omitir el BOM', () {
      final csv = construirCsv(
        encabezados: ['A'],
        filas: const [],
        incluirBom: false,
      );

      expect(csv.startsWith('\uFEFF'), isFalse);
      expect(csv, 'A\r\n');
    });

    test('una tabla sin filas conserva el encabezado', () {
      final csv = construirCsv(encabezados: ['A', 'B'], filas: const []);
      expect(csv, '\uFEFFA,B\r\n');
    });

    test('escapa los valores de las filas, no solo los encabezados', () {
      final csv = construirCsv(
        encabezados: ['Producto'],
        filas: [
          ['Refresco, 600ml'],
        ],
      );

      expect(csv, contains('"Refresco, 600ml"'));
    });
  });

  group('montoCsv', () {
    test('siempre dos decimales y punto decimal', () {
      expect(montoCsv(1234.5), '1234.50');
      expect(montoCsv(0), '0.00');
      expect(montoCsv(10), '10.00');
    });

    test('null es 0.00 y no celda vacía', () {
      expect(montoCsv(null), '0.00');
    });

    test('sin símbolo de moneda ni separador de miles', () {
      // Con "$1,234.50" Excel recibiría texto y no se podría sumar.
      final r = montoCsv(1234.5);
      expect(r.contains(r'$'), isFalse);
      expect(r.contains(','), isFalse);
    });
  });
}
