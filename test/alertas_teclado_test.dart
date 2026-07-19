// Cubre el punto 5 (alertas y diálogos): Enter activa la acción principal,
// Escape siempre cancela/cierra (nunca confirma), no hay doble disparo por
// tecla repetida, y FormDialog responde a Ctrl+S/Escape. Todo esto vive en
// el componente compartido (CustomAlert/FormDialog), así que probarlo aquí
// cubre los ~40+ sitios que ya los usan sin tocar cada pantalla.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/widgets/confirm_action.dart';
import 'package:pvapp/widgets/custom_alert.dart';
import 'package:pvapp/widgets/form_dialog.dart';

void main() {
  Future<void> abrirDialogo(WidgetTester tester, Widget dialogo) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog(context: context, builder: (_) => dialogo),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  group('CustomAlert', () {
    testWidgets('Enter activa la acción principal', (tester) async {
      var confirmados = 0;

      await abrirDialogo(
        tester,
        CustomAlert(
          titulo: 'Título',
          mensaje: 'Mensaje',
          icono: Icons.info_outline,
          textoConfirmar: 'Aceptar',
          onConfirm: () => confirmados++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(confirmados, 1);
      expect(find.byType(CustomAlert), findsNothing); // se cerró
    });

    testWidgets('Escape cierra y cancela, nunca dispara onConfirm (ni en un diálogo destructivo)', (tester) async {
      var confirmados = 0;
      var cancelados = 0;

      await abrirDialogo(
        tester,
        CustomAlert(
          titulo: 'Eliminar producto',
          mensaje: '¿Seguro?',
          icono: Icons.delete_outline,
          textoConfirmar: 'Eliminar',
          textoCancelar: 'Cancelar',
          esDestructivo: true,
          onConfirm: () => confirmados++,
          onCancel: () => cancelados++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(confirmados, 0, reason: 'Escape jamás debe confirmar una acción destructiva');
      expect(cancelados, 1);
      expect(find.byType(CustomAlert), findsNothing);
    });

    testWidgets('una alerta de error no se puede "confirmar" con Escape', (tester) async {
      var confirmados = 0;

      await abrirDialogo(
        tester,
        CustomAlert(
          titulo: 'Error',
          mensaje: 'Algo salió mal',
          icono: Icons.error_outline,
          textoConfirmar: 'Aceptar',
          onConfirm: () => confirmados++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(confirmados, 0);
    });

    testWidgets('Enter mantenido / repetido no dispara onConfirm dos veces', (tester) async {
      var confirmados = 0;

      await abrirDialogo(
        tester,
        CustomAlert(
          titulo: 'Título',
          mensaje: 'Mensaje',
          icono: Icons.info_outline,
          textoConfirmar: 'Aceptar',
          onConfirm: () => confirmados++,
        ),
      );

      // Dos Enter consecutivos antes de que termine de asentarse el pop.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(confirmados, 1);
    });

    testWidgets('confirmarAccion ahora incluye botón Cancelar y es destructivo', (tester) async {
      var accionEjecutada = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => confirmarAccion(
                  context: context,
                  tituloConfirmar: 'Eliminar cliente',
                  mensajeConfirmar: '¿Seguro?',
                  iconoConfirmar: Icons.delete_outline,
                  textoConfirmar: 'Eliminar',
                  accion: () async => accionEjecutada = true,
                  tituloExito: 'Eliminado',
                  mensajeExito: 'Listo',
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(accionEjecutada, isFalse, reason: 'Escape cancela sin ejecutar la eliminación');
    });
  });

  group('FormDialog', () {
    testWidgets('Ctrl+S dispara onGuardar', (tester) async {
      var guardados = 0;

      await abrirDialogo(
        tester,
        FormDialog(
          titulo: 'Nuevo cliente',
          subtitulo: 'Datos del cliente',
          campos: const [SizedBox.shrink()],
          onGuardar: () => guardados++,
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(guardados, 1);
    });

    testWidgets('Escape cancela sin llamar onGuardar', (tester) async {
      var guardados = 0;

      await abrirDialogo(
        tester,
        FormDialog(
          titulo: 'Nuevo cliente',
          subtitulo: 'Datos del cliente',
          campos: const [SizedBox.shrink()],
          onGuardar: () => guardados++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(guardados, 0);
      expect(find.byType(FormDialog), findsNothing);
    });

    testWidgets('reintentar tras un guardado fallido (validación) sigue funcionando', (tester) async {
      var intentos = 0;

      await abrirDialogo(
        tester,
        FormDialog(
          titulo: 'Nuevo cliente',
          subtitulo: 'Datos del cliente',
          campos: const [SizedBox.shrink()],
          // Simula el patrón real: valida y, si falla, NO cierra el
          // diálogo (el usuario debe poder reintentar).
          onGuardar: () => intentos++,
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(intentos, 2, reason: 'el guardado debe poder reintentarse, no bloquearse para siempre');
    });
  });
}
