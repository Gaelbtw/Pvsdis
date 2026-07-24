import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Notificación breve y NO invasiva: aparece flotando abajo y se va sola.
/// Reemplaza los diálogos modales de "éxito/aviso" que solo decían "listo,
/// Aceptar" e interrumpían el flujo. Los diálogos modales quedan reservados
/// para confirmaciones reales (borrar, cerrar caja, etc.).
class Toast {
  Toast._();

  static void exito(BuildContext context, String mensaje) =>
      _mostrar(context, mensaje, AppColors.success, Icons.check_circle_outline);

  static void info(BuildContext context, String mensaje) =>
      _mostrar(context, mensaje, AppColors.primaryDark, Icons.info_outline);

  static void error(BuildContext context, String mensaje) =>
      _mostrar(context, mensaje, AppColors.error, Icons.error_outline);

  static void _mostrar(BuildContext context, String mensaje, Color color, IconData icono) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        elevation: 8,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        content: Row(
          children: [
            Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            Icon(icono, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(mensaje,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: AppText.body)),
            ),
          ],
        ),
      ),
    );
  }
}
