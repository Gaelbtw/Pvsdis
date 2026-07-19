import 'package:flutter/material.dart';

import 'custom_alert.dart';

/// Flujo estándar "confirmar -> ejecutar -> avisar éxito", usado en cada
/// botón de eliminar de la app. Antes cada vista repetía este mismo
/// bloque (diálogo de confirmación -> acción -> diálogo de éxito) a mano.
Future<void> confirmarAccion({
  required BuildContext context,
  required String tituloConfirmar,
  required String mensajeConfirmar,
  required IconData iconoConfirmar,
  required String textoConfirmar,
  required Future<void> Function() accion,
  required String tituloExito,
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
        showDialog(
          context: context,
          builder: (_) => CustomAlert(
            titulo: tituloExito,
            mensaje: mensajeExito,
            icono: Icons.check_circle_outline,
            textoConfirmar: "Aceptar",
            onConfirm: () {},
          ),
        );
      },
    ),
  );
}
