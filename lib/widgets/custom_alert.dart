import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

class CustomAlert extends StatefulWidget {
  final String titulo;
  final String mensaje;
  final IconData icono;

  final String textoConfirmar;
  final String? textoCancelar;

  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  /// Color de acento: afecta ícono, fondo del avatar y botón confirmar. Por
  /// defecto usa el color de marca configurado en Configuración
  /// ([AppColors.primary]), para que los avisos genéricos sean visualmente
  /// consistentes con el resto de la app. Los diálogos que sí necesitan un
  /// color semántico fijo (éxito en verde, peligro en rojo) lo siguen
  /// pasando explícitamente y no se ven afectados.
  final Color? color;

  /// Marca este diálogo como una confirmación destructiva (ej. eliminar).
  /// Cambia el foco inicial al botón de cancelar en vez del de confirmar,
  /// para que presionar Enter por costumbre no dispare la acción.
  final bool esDestructivo;

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
    this.esDestructivo = false,
  });

  @override
  State<CustomAlert> createState() => _CustomAlertState();
}

class _CustomAlertState extends State<CustomAlert> {
  // Evita que una tecla repetida (Enter mantenido) o un doble click alcancen
  // a invocar onConfirm/onCancel dos veces: el diálogo se cierra en el
  // primer disparo y cualquier evento posterior se ignora.
  bool _resuelto = false;

  void _confirmar() {
    if (_resuelto) return;
    _resuelto = true;
    Navigator.pop(context);
    if (widget.onConfirm != null) {
      widget.onConfirm!();
    }
  }

  void _cancelar() {
    if (_resuelto) return;
    _resuelto = true;
    if (widget.onCancel != null) {
      Navigator.pop(context);
      widget.onCancel!();
    } else {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.color ?? AppColors.primary;
    final isLight = accentColor.computeLuminance() > 0.4;
    // Si es destructivo pero no hay botón de cancelar que reciba el foco,
    // igual hay que enfocar algo (si no, ningún widget del diálogo tiene
    // foco y Enter/Escape no llegarían a los bindings de arriba).
    final cancelarTieneFoco = widget.esDestructivo && widget.textoCancelar != null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _confirmar,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirmar,
        // Escape SIEMPRE cancela/cierra, nunca confirma: así un mensaje de
        // error o una confirmación destructiva no se puede "aceptar" sin
        // querer con la tecla que el usuario espera que solo cierre.
        const SingleActivator(LogicalKeyboardKey.escape): _cancelar,
      },
      child: Dialog(
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
                    child: Icon(widget.icono, color: accentColor, size: 40),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                children: [
                  Text(
                    widget.titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.mensaje,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
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
                  if (widget.textoCancelar != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        autofocus: cancelarTieneFoco,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _cancelar,
                        child: Text(widget.textoCancelar!),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      autofocus: !cancelarTieneFoco,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor:
                            isLight ? Colors.black87 : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _confirmar,
                      child: Text(
                        widget.textoConfirmar,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
