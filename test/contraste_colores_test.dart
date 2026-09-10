// Contraste del color de marca.
//
// El color primario lo elige cada negocio, así que ninguna pantalla puede
// suponer de qué color va su texto. Aquí se verifica que la tinta calculada
// sea legible sobre CUALQUIER color de la paleta, y que nadie vuelva a
// escribir el color del texto a mano encima del fondo de marca.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/theme/app_colors.dart';

/// Mínimo de WCAG AA para texto normal. Los botones de esta app llevan texto
/// de 15-16px en negritas, que técnicamente calificaría como "texto grande"
/// con 3:1, pero se exige el 4.5 completo: el cajero lee el botón de cobrar de
/// reojo, a un metro, con la tienda llena.
const double _minimoLegible = 4.5;

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

void main() {
  tearDown(() => AppColors.actualizar(AppColors.paletaMarca.first));

  group('LA TINTA SE LEE SOBRE CUALQUIER COLOR DE MARCA', () {
    test('cada color de la paleta llega a 4.5:1 con su tinta', () {
      for (final color in AppColors.paletaMarca) {
        AppColors.actualizar(color);
        final razon = AppColors.contraste(AppColors.onPrimary, color);

        expect(
          razon,
          greaterThanOrEqualTo(_minimoLegible),
          reason: 'El color ${_hex(color)} solo alcanza '
              '${razon.toStringAsFixed(2)}:1 con la tinta '
              '${_hex(AppColors.onPrimary)}. Un botón así no se lee.',
        );
      }
    });

    test('elige tinta oscura sobre los colores claros', () {
      for (final claro in const [Color(0xFFF2C500), Color(0xFFFFFFFF)]) {
        AppColors.actualizar(claro);
        expect(AppColors.onPrimary, AppColors.textPrimary,
            reason: '${_hex(claro)} es claro: la tinta debe ser la oscura.');
      }
    });

    test('elige tinta blanca sobre los colores oscuros', () {
      for (final oscuro in const [
        Color(0xFF2563EB),
        Color(0xFF334155),
        Color(0xFF1F1D1A),
      ]) {
        AppColors.actualizar(oscuro);
        expect(AppColors.onPrimary, Colors.white,
            reason: '${_hex(oscuro)} es oscuro: la tinta debe ser blanca.');
      }
    });

    test('el umbral viejo de luminancia se equivocaba y este no', () {
      // Lo que importa no es dónde cae el umbral, sino que la decisión se
      // tome midiendo y no adivinando. Medir además reveló que el verde, el
      // naranja y el verde azulado que traía la paleta no llegaban a 4.5:1
      // con NINGUNA de las dos tintas: hubo que oscurecerlos (ver
      // AppColors.paletaMarca).
      for (final color in AppColors.paletaMarca) {
        AppColors.actualizar(color);
        final conLaOtra = AppColors.onPrimary == Colors.white
            ? AppColors.textPrimary
            : Colors.white;

        expect(
          AppColors.contraste(AppColors.onPrimary, color),
          greaterThanOrEqualTo(AppColors.contraste(conLaOtra, color)),
          reason: 'Para ${_hex(color)} se eligió la tinta con menos contraste.',
        );
      }
    });
  });

  group('un color de marca casi blanco necesita borde', () {
    test('el blanco lo pide', () {
      AppColors.actualizar(const Color(0xFFFFFFFF));
      expect(AppColors.primaryNecesitaBorde, isTrue);

      // Y el borde tiene que verse: un aro del mismo blanco no sirve de nada.
      expect(
        AppColors.contraste(AppColors.bordePrimario, AppColors.background),
        greaterThan(1.3),
      );
    });

    test('los demás no', () {
      for (final color in AppColors.paletaMarca) {
        if (color.toARGB32() == const Color(0xFFFFFFFF).toARGB32()) continue;
        AppColors.actualizar(color);
        expect(AppColors.primaryNecesitaBorde, isFalse,
            reason: '${_hex(color)} se distingue del fondo por sí solo.');
      }
    });
  });

  group('NADIE ESCRIBE EL COLOR DEL TEXTO SOBRE EL FONDO DE MARCA', () {
    test('ninguna vista fija Colors.black o Colors.white sobre AppColors.primary',
        () {
      // Esto empezó como 18 botones con `foregroundColor: Colors.black87`
      // sobre `backgroundColor: AppColors.primary`. Con el dorado por omisión
      // se veía bien, así que nadie lo notó; con el azul o el gris oscuro de
      // la misma paleta el texto desaparecía.
      //
      // La prueba lee el código fuente porque el error no es de ejecución: es
      // de escritura, y solo se ve en la máquina del cliente que eligió otro
      // color.
      final infractores = <String>[];

      for (final archivo in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lineas = archivo.readAsLinesSync();

        for (var i = 0; i < lineas.length; i++) {
          if (!RegExp(r'backgroundColor:\s*AppColors\.primary\b')
              .hasMatch(lineas[i])) {
            continue;
          }

          final desde = i - 3 < 0 ? 0 : i - 3;
          final hasta = i + 6 > lineas.length ? lineas.length : i + 6;
          final bloque = lineas.sublist(desde, hasta).join('\n');

          final fijo =
              RegExp(r'foregroundColor:\s*(Colors\.[A-Za-z0-9]+)').firstMatch(bloque);
          if (fijo != null) {
            infractores.add('${archivo.path}:${i + 1} -> ${fijo.group(1)}');
          }
        }
      }

      expect(
        infractores,
        isEmpty,
        reason: 'Estos botones fijan el color del texto sobre el color de marca.\n'
            'Usa AppColors.onPrimary, que lo calcula por contraste:\n'
            '  ${infractores.join('\n  ')}',
      );
    });
  });
}
