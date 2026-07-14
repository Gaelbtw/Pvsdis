import 'package:flutter/material.dart';

class CustomAlert extends StatelessWidget {
  final String titulo;
  final String mensaje;
  final IconData icono;

  final String textoConfirmar;
  final String? textoCancelar;

  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  /// Color de acento: afecta ícono, fondo del avatar y botón confirmar.
  /// Por defecto usa amarillo/amber (comportamiento original).
  final Color? color;

  const CustomAlert({
    super.key,
    required this.titulo,
    required this.mensaje,
    required this.icono,
    this.textoConfirmar = "Confirmar",
    this.textoCancelar,
    this.onConfirm,
    this.onCancel,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = color ?? Colors.amber;
    final isLight = accentColor.computeLuminance() > 0.4;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Franja superior de color
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                      width: 3,
                    ),
                  ),
                  child: Icon(icono, color: accentColor, size: 40),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              children: [
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  mensaje,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (textoCancelar != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (onCancel != null) {
                          Navigator.pop(context);
                          onCancel!();
                        } else {
                          Navigator.pop(context, false);
                        }
                      },
                      child: Text(textoCancelar!),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor:
                          isLight ? Colors.black87 : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      if (onConfirm != null) {
                        Navigator.pop(context);
                        onConfirm!();
                      } else {
                        Navigator.pop(context, true);
                      }
                    },
                    child: Text(
                      textoConfirmar,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
