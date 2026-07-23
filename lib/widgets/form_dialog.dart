import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// Estructura estándar de un diálogo de alta/edición: título, subtítulo,
/// lista de campos y botones Cancelar/Guardar. Antes cada vista
/// (clientes, productos, proveedores, usuarios, categorías) reconstruía
/// este mismo contenedor desde cero.
class FormDialog extends StatefulWidget {
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
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  // Evita disparar onGuardar dos veces por Enter mantenido, Ctrl+S repetido
  // o doble click mientras la llamada anterior sigue en curso. A diferencia
  // de CustomAlert, este diálogo NO se cierra solo: `onGuardar` valida y,
  // si el formulario es inválido, muestra un error y deja el diálogo
  // abierto para que el usuario corrija y reintente — por eso el bloqueo se
  // libera al terminar la llamada en vez de quedar fijo para siempre.
  bool _enviando = false;
  bool _cancelado = false;

  Future<void> _guardar() async {
    if (_enviando) return;
    _enviando = true;
    try {
      await Future.sync(widget.onGuardar);
    } finally {
      _enviando = false;
    }
  }

  void _cancelar() {
    if (_cancelado) return;
    _cancelado = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _guardar,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _guardar,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _guardar,
        const SingleActivator(LogicalKeyboardKey.escape): _cancelar,
      },
      child: Dialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    fontSize: AppText.heading,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitulo,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
                ),
                const SizedBox(height: 24),
                for (final campo in widget.campos) ...[
                  campo,
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _cancelar,
                      child: const Text(
                        "Cancelar",
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      autofocus: true,
                      onPressed: _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: Text(
                        widget.textoGuardar,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
