import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme/app_colors.dart';

/// Diálogo que pide motivo obligatorio (y, si corresponde, credenciales de
/// un administrador) antes de aplicar un descuento que superó el umbral
/// configurado. Reutiliza `Authcontroller.login` para validar al admin sin
/// duplicar la lógica de verificación de contraseña.
Future<void> mostrarAutorizacionDescuentoDialog(
  BuildContext context, {
  required bool requiereCredencialesAdmin,
  required void Function(String motivo, int? autorizadoPor) onConfirmar,
}) {
  final motivoCtrl = TextEditingController();
  final usuarioCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  return showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialog) {
        String? error;
        var verificando = false;

        Future<void> confirmar() async {
          final motivo = motivoCtrl.text.trim();
          if (motivo.isEmpty) {
            setDialog(() => error = 'El motivo es obligatorio.');
            return;
          }

          if (!requiereCredencialesAdmin) {
            Navigator.pop(dialogContext);
            onConfirmar(motivo, null);
            return;
          }

          setDialog(() {
            verificando = true;
            error = null;
          });

          final resultado = await Authcontroller().login(
            usuarioCtrl.text.trim(),
            passwordCtrl.text,
          );

          final rol = resultado.usuario?['rol']?.toString();
          if (resultado.status != LoginStatus.success || rol != 'Admin') {
            setDialog(() {
              verificando = false;
              error = 'Credenciales de administrador inválidas.';
            });
            return;
          }

          if (!dialogContext.mounted) return;
          Navigator.pop(dialogContext);
          onConfirmar(motivo, resultado.usuario!['id_usuario'] as int);
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Text('Descuento requiere autorización'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Este descuento supera el máximo habitual. Indica el motivo para continuar.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Motivo',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                ),
                if (requiereCredencialesAdmin) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Se requiere autorización de un administrador:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usuarioCtrl,
                    decoration: InputDecoration(
                      labelText: 'Usuario admin',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.error, fontSize: AppText.small)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: verificando ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
              ),
              onPressed: verificando ? null : confirmar,
              child: Text(verificando ? 'Verificando…' : 'Confirmar'),
            ),
          ],
        );
      },
    ),
  );
}
