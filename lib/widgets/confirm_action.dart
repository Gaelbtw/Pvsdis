import 'package:flutter/material.dart';

import '../core/utils/mensaje_error.dart';
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
        // Sin este try, cualquier fallo de [accion] subía sin manejar. El
        // caso normal no es un bug raro: es intentar borrar un registro que
        // otro usa. `Clientes`, `Producto`, `Proveedores` y `Usuarios` están
        // referenciados con `ON DELETE RESTRICT`, así que SQLite rechaza el
        // borrado y los controladores ya convierten ese rechazo en un mensaje
        // legible ("no se puede eliminar: tiene ventas asociadas"). Ese
        // mensaje nunca llegaba a la pantalla.
        //
        // Va aquí y no en cada vista a propósito: este helper lo usa TODO
        // botón de eliminar de la app, así que se arregla en un solo sitio en
        // vez de repetir el mismo try en una docena de archivos.
        try {
          await accion();
        } catch (e) {
          if (!context.mounted) return;
          Toast.error(context, mensajeDeError(e));
          return;
        }

        if (!context.mounted) return;
        Toast.exito(context, mensajeExito);
      },
    ),
  );
}
