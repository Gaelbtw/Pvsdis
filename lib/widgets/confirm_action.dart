import 'package:flutter/material.dart';

import 'custom_alert.dart';
import 'toast.dart';

/// Flujo estándar "confirmar -> ejecutar -> avisar éxito", usado en cada
/// botón de eliminar de la app. La confirmación (que sí exige una decisión)
/// se muestra como diálogo; el aviso de éxito ya NO abre un segundo diálogo
/// con "Aceptar" (interrumpía por gusto), ahora es una notificación breve
/// que se va sola ([Toast]).
///
/// [tituloExito] se conserva por compatibilidad con las llamadas existentes,
/// pero el toast solo muestra [mensajeExito].
Future<void> confirmarAccion({
  required BuildContext context,
  required String tituloConfirmar,
  required String mensajeConfirmar,
  required IconData iconoConfirmar,
  required String textoConfirmar,
  required Future<void> Function() accion,
  String? tituloExito,
  required String mensajeExito,
}) {
  return showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: tituloConfirmar,
      mensaje: mensajeConfirmar,
      icono: iconoConfirmar,
      textoConfirmar: textoConfirmar,
      textoCancelar: 'Cancelar',
      esDestructivo: true,
      onConfirm: () async {
        await accion();
        if (!context.mounted) return;
        Toast.exito(context, mensajeExito);
      },
    ),
  );
}
