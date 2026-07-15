import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Estructura estándar de un diálogo de alta/edición: título, subtítulo,
/// lista de campos y botones Cancelar/Guardar. Antes cada vista
/// (clientes, productos, proveedores, usuarios, categorías) reconstruía
/// este mismo contenedor desde cero.
class FormDialog extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final List<Widget> campos;
  final VoidCallback onGuardar;
  final String textoGuardar;

  const FormDialog({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.campos,
    required this.onGuardar,
    this.textoGuardar = "Guardar",
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitulo,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              for (final campo in campos) ...[
                campo,
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancelar",
                      style: TextStyle(color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: onGuardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      textoGuardar,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
