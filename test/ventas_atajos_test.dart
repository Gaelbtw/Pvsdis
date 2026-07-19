// Cubre los atajos de teclado de Ventas (punto 4), probando la lógica
// extraída a widgets/ventas/ventas_atajos.dart en vez de montar VentasView
// completo: esa vista dispara 3 cargas asíncronas reales contra la base en
// initState (productos, caja, promociones) que resultaron inestables bajo
// el backend sqflite ffi de test (ver historial de este archivo). Aquí se
// prueba la lógica de decisión (pura) y el widget de atajos (aislado, con
// callbacks falsos) sin ninguna base de datos de por medio.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/widgets/ventas/ventas_atajos.dart';

void main() {
  group('moverSeleccionCarrito (lógica pura de las flechas)', () {
    test('sin selección previa, flecha abajo selecciona la primera línea', () {
      expect(
        moverSeleccionCarrito(actual: null, delta: 1, totalLineas: 3),
        0,
      );
    });

    test('sin selección previa, flecha arriba selecciona la última línea', () {
      expect(
        moverSeleccionCarrito(actual: null, delta: -1, totalLineas: 3),
        2,
      );
    });

    test('avanza y retrocede desde una selección existente', () {
      expect(moverSeleccionCarrito(actual: 1, delta: 1, totalLineas: 5), 2);
      expect(moverSeleccionCarrito(actual: 1, delta: -1, totalLineas: 5), 0);
    });

    test('no se sale de los límites del carrito', () {
      expect(moverSeleccionCarrito(actual: 4, delta: 1, totalLineas: 5), 4);
      expect(moverSeleccionCarrito(actual: 0, delta: -1, totalLineas: 5), 0);
    });

    test('carrito vacío: no hay línea que seleccionar', () {
      expect(moverSeleccionCarrito(actual: null, delta: 1, totalLineas: 0), isNull);
    });
  });

  group('puedeConfirmarVenta (lógica pura de F4)', () {
    test('solo permite confirmar con carrito, pagos válidos y caja abierta', () {
      expect(
        puedeConfirmarVenta(carritoVacio: false, pagosValidos: true, cajaAbierta: true),
        isTrue,
      );
    });

    test('rechaza con carrito vacío', () {
      expect(
        puedeConfirmarVenta(carritoVacio: true, pagosValidos: true, cajaAbierta: true),
        isFalse,
      );
    });

    test('rechaza con pagos inválidos', () {
      expect(
        puedeConfirmarVenta(carritoVacio: false, pagosValidos: false, cajaAbierta: true),
        isFalse,
      );
    });

    test('rechaza sin caja abierta', () {
      expect(
        puedeConfirmarVenta(carritoVacio: false, pagosValidos: true, cajaAbierta: false),
        isFalse,
      );
    });
  });

  group('VentasAtajos (widget de atajos, aislado con callbacks falsos)', () {
    // Arma una pantalla mínima: un TextField (para poder enfocarlo y
    // simular "el usuario está escribiendo") y el widget de atajos
    // envolviendo un área vacía donde recae el foco por defecto.
    Widget arma({
      required VoidCallback onEnfocarBusqueda,
      required VoidCallback onConfirmarVenta,
      required VoidCallback onEscape,
      required void Function(int) onMoverSeleccion,
      required VoidCallback onEliminarSeleccionada,
      required FocusNode focoCampoDeTexto,
    }) {
      // El campo de texto está DENTRO de VentasAtajos, como en VentasView
      // real (el buscador vive en el mismo árbol que envuelve
      // CallbackShortcuts): así los eventos de teclado de un campo
      // enfocado sí burbujean hacia los bindings, igual que en la vista.
      return MaterialApp(
        home: Scaffold(
          body: VentasAtajos(
            onEnfocarBusqueda: onEnfocarBusqueda,
            onConfirmarVenta: onConfirmarVenta,
            onEscape: onEscape,
            onMoverSeleccion: onMoverSeleccion,
            onEliminarSeleccionada: onEliminarSeleccionada,
            child: Column(
              children: [
                TextField(focusNode: focoCampoDeTexto),
                const Expanded(
                  child: Focus(
                    autofocus: true,
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('F2 enfoca el buscador', (tester) async {
      var enfocado = 0;
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () => enfocado++,
        onConfirmarVenta: () {},
        onEscape: () {},
        onMoverSeleccion: (_) {},
        onEliminarSeleccionada: () {},
        focoCampoDeTexto: foco,
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();

      expect(enfocado, 1);
    });

    testWidgets('F4 intenta confirmar la venta', (tester) async {
      var confirmados = 0;
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () {},
        onConfirmarVenta: () => confirmados++,
        onEscape: () {},
        onMoverSeleccion: (_) {},
        onEliminarSeleccionada: () {},
        focoCampoDeTexto: foco,
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await tester.pump();

      expect(confirmados, 1);
    });

    testWidgets('las flechas cambian la línea seleccionada', (tester) async {
      final movimientos = <int>[];
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () {},
        onConfirmarVenta: () {},
        onEscape: () {},
        onMoverSeleccion: movimientos.add,
        onEliminarSeleccionada: () {},
        focoCampoDeTexto: foco,
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(movimientos, [1, -1]);
    });

    testWidgets('Delete solicita eliminar la línea seleccionada', (tester) async {
      var solicitudes = 0;
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () {},
        onConfirmarVenta: () {},
        onEscape: () {},
        onMoverSeleccion: (_) {},
        onEliminarSeleccionada: () => solicitudes++,
        focoCampoDeTexto: foco,
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      expect(solicitudes, 1);
    });

    testWidgets('Escape se dispara aunque no haya nada seleccionado', (tester) async {
      var escapes = 0;
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () {},
        onConfirmarVenta: () {},
        onEscape: () => escapes++,
        onMoverSeleccion: (_) {},
        onEliminarSeleccionada: () {},
        focoCampoDeTexto: foco,
      ));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(escapes, 1);
    });

    testWidgets(
      'F4, flechas y Delete no se disparan mientras se escribe en un campo de texto',
      (tester) async {
        var confirmados = 0;
        final movimientos = <int>[];
        var eliminaciones = 0;
        final foco = FocusNode();
        addTearDown(foco.dispose);

        await tester.pumpWidget(arma(
          onEnfocarBusqueda: () {},
          onConfirmarVenta: () => confirmados++,
          onEscape: () {},
          onMoverSeleccion: movimientos.add,
          onEliminarSeleccionada: () => eliminaciones++,
          focoCampoDeTexto: foco,
        ));

        // El usuario está escribiendo en el campo de texto.
        foco.requestFocus();
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.f4);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pump();

        expect(confirmados, 0, reason: 'F4 no debe confirmar mientras se escribe');
        expect(movimientos, isEmpty, reason: 'las flechas no deben mover la selección mientras se escribe');
        expect(eliminaciones, 0, reason: 'Delete no debe pedir eliminar mientras se escribe');
      },
    );

    testWidgets('F2 sí enfoca el buscador aunque se esté escribiendo en otro campo', (tester) async {
      var enfocado = 0;
      final foco = FocusNode();
      addTearDown(foco.dispose);

      await tester.pumpWidget(arma(
        onEnfocarBusqueda: () => enfocado++,
        onConfirmarVenta: () {},
        onEscape: () {},
        onMoverSeleccion: (_) {},
        onEliminarSeleccionada: () {},
        focoCampoDeTexto: foco,
      ));

      foco.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();

      expect(enfocado, 1, reason: 'F2 debe funcionar siempre, incluso escribiendo en otro campo');
    });
  });
}
