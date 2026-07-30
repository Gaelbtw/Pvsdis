import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvapp/widgets/toast.dart';

/// Cubre la integración del toast de escritorio con el Overlay: que se monte,
/// muestre el mensaje, y se limpie solo (auto-cierre + disposición del timer y
/// el AnimationController, sin excepciones al final del test).
void main() {
  Widget appConBoton(void Function(BuildContext) alPresionar) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => alPresionar(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('muestra el mensaje y se cierra solo tras la duración', (tester) async {
    await tester.pumpWidget(appConBoton((c) => Toast.exito(c, 'Venta registrada')));

    await tester.tap(find.text('go'));
    await tester.pump(); // inserta la OverlayEntry
    await tester.pump(const Duration(milliseconds: 250)); // animación de entrada
    expect(find.text('Venta registrada'), findsOneWidget);

    // Auto-cierre (3 s) + animación de salida.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Venta registrada'), findsNothing);
  });

  testWidgets('se apilan varios y el botón de cerrar descarta el aviso', (tester) async {
    await tester.pumpWidget(appConBoton((c) {
      Toast.exito(c, 'Primero');
      Toast.error(c, 'Segundo');
    }));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Primero'), findsOneWidget);
    expect(find.text('Segundo'), findsOneWidget);

    // Cerrar manualmente con la «×» (hay uno por tarjeta): descarta una.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Una se fue; deja de haber dos mensajes a la vez.
    final quedan = [
      find.text('Primero').evaluate().length,
      find.text('Segundo').evaluate().length,
    ].fold<int>(0, (a, b) => a + b);
    expect(quedan, 1);

    // Deja que el resto se auto-cierre para no dejar timers vivos.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
