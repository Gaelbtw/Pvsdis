// Pruebas de las piezas en que se partió la pantalla de Caja.
//
// `caja_view.dart` no se puede montar en una prueba: construye su propio
// `CajaController`, que abre la base. Pero las tres piezas que hacen el
// trabajo —contar el cajón, mostrar el efectivo, mostrar lo que no pasa por
// el cajón— son widgets independientes que reciben todo por parámetro. Eso
// es lo que se prueba aquí, y es donde vive el riesgo: la aritmética del
// conteo y la política de arqueo a ciegas.
//
// Lo que NO se prueba aquí y sigue dependiendo de revisión manual: el flujo
// completo de abrir turno, cerrar y volver a la pantalla de resultado.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/models/conteo_denominaciones.dart';
import 'package:pvapp/models/vista_corte.dart';
import 'package:pvapp/widgets/caja/contador_denominaciones.dart';
import 'package:pvapp/widgets/caja/ledger_efectivo.dart';
import 'package:pvapp/widgets/caja/panel_no_efectivo.dart';

Future<void> _montar(WidgetTester tester, Widget hijo, {double ancho = 520}) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: SizedBox(width: ancho, child: hijo)),
        ),
      ),
    ),
  );
}

/// Un turno con de todo: efectivo, plástico, anticipos y salidas.
///
/// Los números están elegidos para que el esperado NO sea redondo y para que
/// ningún sumando se repita: si dos coincidieran, una fuga podría pasar
/// inadvertida porque el monto filtrado se confundiría con otro permitido.
const _resumen = ResumenCaja(
  fondoInicial: 500,
  ventasEfectivo: 3355,
  ventasTarjeta: 5077.50,
  ventasTransferencia: 1240,
  cambioEntregado: 412,
  devoluciones: 130,
  anticiposEfectivo: 640,
  anticiposTarjeta: 310,
  anticiposTransferencia: 95,
  cambioAnticipos: 28,
  pagosProveedoresEfectivo: 700,
  entradasEfectivo: 200,
  salidasEfectivo: 150,
  ticketsCerrados: 47,
  efectivoEsperado: 3275,
);

/// Los campos del contador, en el orden en que los dibuja: los seis billetes
/// (de mayor a menor) y al final las monedas.
Finder get _campos => find.byType(TextField);

void main() {
  group('ContadorDenominaciones', () {
    testWidgets('suma lo tecleado y avisa con el conteo completo', (tester) async {
      ConteoDenominaciones? ultimo;
      await _montar(tester, ContadorDenominaciones(onCambio: (c) => ultimo = c));

      // 2 de $1000, 3 de $500, 1 de $100  ->  3,600 en billetes
      await tester.enterText(_campos.at(0), '2');
      await tester.enterText(_campos.at(1), '3');
      await tester.enterText(_campos.at(3), '1');
      await tester.enterText(_campos.at(6), '85.50'); // monedas
      await tester.pump();

      expect(ultimo, isNotNull);
      expect(ultimo!.totalBilletes, 3600);
      expect(ultimo!.monedas, 85.50);
      expect(ultimo!.total, 3685.50);
      expect(ultimo!.piezasBilletes, 6);
    });

    testWidgets('los renglones van del billete mayor al menor', (tester) async {
      await _montar(tester, ContadorDenominaciones(onCambio: (_) {}));

      // El orden importa: es el orden en que se apilan los billetes al
      // contar. Si alguien reordena la lista, el dedo y las manos dejan de
      // ir por el mismo camino.
      expect(ConteoDenominaciones.denominaciones, [1000, 500, 200, 100, 50, 20]);
      for (final d in ConteoDenominaciones.denominaciones) {
        expect(find.text('\$$d'), findsOneWidget);
      }
    });

    testWidgets('el subtotal del renglón se enciende al teclear', (tester) async {
      await _montar(tester, ContadorDenominaciones(onCambio: (_) {}));

      // Sin cantidad, el renglón muestra una raya, no un cero: un cero en
      // columna se lee como "ya lo conté y no había".
      expect(find.text('—'), findsNWidgets(6));

      await tester.enterText(_campos.at(2), '4'); // 4 x $200
      await tester.pump();

      expect(find.text('\$800.00'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(5));
    });

    testWidgets('en los billetes no entra nada que no sea un dígito', (tester) async {
      ConteoDenominaciones? ultimo;
      await _montar(tester, ContadorDenominaciones(onCambio: (c) => ultimo = c));

      // Teclado numérico y filtro de dígitos: un "3.5" de billetes de $1000
      // no significa nada, y un cajero con prisa lo teclea.
      await tester.enterText(_campos.at(0), '3.5');
      await tester.pump();

      expect(ultimo!.cantidadDe(1000), 35);
      expect(ultimo!.totalBilletes, 35000);
    });

    testWidgets('las monedas aceptan coma decimal', (tester) async {
      ConteoDenominaciones? ultimo;
      await _montar(tester, ContadorDenominaciones(onCambio: (c) => ultimo = c));

      // El teclado numérico de Windows en español produce coma. Sin esto,
      // "12,50" se leía como cero y el faltante aparecía de la nada.
      await tester.enterText(_campos.at(6), '12,50');
      await tester.pump();

      expect(ultimo!.monedas, 12.50);
    });

    testWidgets('borrar un renglón lo devuelve a cero', (tester) async {
      ConteoDenominaciones? ultimo;
      await _montar(tester, ContadorDenominaciones(onCambio: (c) => ultimo = c));

      await tester.enterText(_campos.at(1), '7');
      await tester.pump();
      expect(ultimo!.total, 3500);

      await tester.enterText(_campos.at(1), '');
      await tester.pump();
      expect(ultimo!.total, 0);
      expect(ultimo!.piezasBilletes, 0);
    });

    testWidgets('Enter en monedas cierra la caja', (tester) async {
      var enviado = 0;
      await _montar(
        tester,
        ContadorDenominaciones(onCambio: (_) {}, onEnviar: () => enviado++),
      );

      // Un cierre completo se hace con Tab y Enter, sin soltar el teclado.
      await tester.enterText(_campos.at(6), '40');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(enviado, 1);
    });
  });

  group('LedgerEfectivo', () {
    testWidgets('a ciegas no dibuja ningún renglón ni el esperado', (tester) async {
      await _montar(
        tester,
        const LedgerEfectivo(
          vista: VistaCorte(resumen: _resumen, aCiegas: true),
        ),
      );

      const vista = VistaCorte(resumen: _resumen, aCiegas: true);
      expect(vista.renglonesEfectivo, isEmpty);
      expect(vista.efectivoEsperado, isNull);

      // Ninguno de los sumandos aparece dibujado, ni el total.
      for (final monto in vista.sumandosDelEsperado) {
        expect(
          find.text('\$${monto.toStringAsFixed(2)}'),
          findsNothing,
          reason: 'Se filtró un sumando del efectivo esperado: $monto',
        );
      }
      expect(find.text('\$3275.00'), findsNothing);
    });

    testWidgets('con el ledger abierto, entradas y salidas van separadas', (tester) async {
      await _montar(
        tester,
        const LedgerEfectivo(
          vista: VistaCorte(resumen: _resumen, aCiegas: false),
        ),
      );

      const vista = VistaCorte(resumen: _resumen, aCiegas: false);
      final entradas = vista.renglonesEfectivo.where((r) => r.suma);
      final salidas = vista.renglonesEfectivo.where((r) => !r.suma);

      // El problema que resolvió este widget: "Cambio entregado $412" se
      // leía como si entrara al cajón. Ahora hay dos bloques.
      expect(entradas, isNotEmpty);
      expect(salidas, isNotEmpty);

      expect(find.text('\$3275.00'), findsOneWidget); // el esperado, visible
    });

    testWidgets('el esperado se puede reconstruir sumando lo que se ve', (tester) async {
      // La razón de ser del ledger: antes faltaban renglones (anticipos y
      // pagos a proveedores), así que quien revisaba sumaba lo de la
      // pantalla, no le daba, y concluía que el sistema se equivocaba.
      const vista = VistaCorte(resumen: _resumen, aCiegas: false);

      final suma = vista.renglonesEfectivo.fold<double>(
        0,
        (a, r) => a + (r.suma ? r.importe : -r.importe),
      );

      expect(suma, closeTo(_resumen.efectivoEsperado, 0.001));
    });
  });

  group('PanelNoEfectivo', () {
    testWidgets('se muestra igual a quien cuenta a ciegas', (tester) async {
      await _montar(
        tester,
        const PanelNoEfectivo(
          vista: VistaCorte(resumen: _resumen, aCiegas: true),
        ),
        ancho: 720,
      );

      // No entra en la fórmula del esperado, así que no filtra nada, y al
      // cajero le sirve para cuadrar sus vouchers durante el turno.
      expect(find.text('\$5077.50'), findsOneWidget); // tarjeta
      expect(find.text('\$1240.00'), findsOneWidget); // transferencia
      expect(find.text('\$405.00'), findsOneWidget); // anticipos 310 + 95
    });

    testWidgets('sin anticipos con plástico, esa columna no aparece', (tester) async {
      const sinAnticipos = ResumenCaja(
        fondoInicial: 500,
        ventasEfectivo: 1000,
        ventasTarjeta: 2000,
        ventasTransferencia: 300,
        cambioEntregado: 0,
        devoluciones: 0,
        efectivoEsperado: 1500,
      );

      await _montar(
        tester,
        const PanelNoEfectivo(
          vista: VistaCorte(resumen: sinAnticipos, aCiegas: false),
        ),
        ancho: 720,
      );

      expect(find.text('TARJETA'), findsOneWidget);
      expect(find.text('ANTICIPOS S/EFECTIVO'), findsNothing);
    });
  });
}
