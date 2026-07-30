import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';

/// Pantalla que aparece justo después de cobrar una venta. Reemplaza al
/// antiguo diálogo genérico de "¿confirmar venta?": la venta ya se cobró, así
/// que aquí solo confirmamos el resultado (Total y Cambio) y dejamos que el
/// cajero decida si imprime el ticket o pasa a la siguiente venta.
///
/// La impresión NO es automática: solo ocurre si el usuario presiona
/// "Imprimir ticket" (se puede imprimir varias veces desde aquí, y el ticket
/// también queda disponible para reimprimir con F9 desde la vista de ventas).
class VentaExitosaDialog extends StatefulWidget {
  final int idVenta;
  final double total;
  final double cambio;

  /// Imprime el ticket de esta venta. Puede llamarse varias veces.
  final Future<void> Function() onImprimir;

  const VentaExitosaDialog({
    super.key,
    required this.idVenta,
    required this.total,
    required this.cambio,
    required this.onImprimir,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required int idVenta,
    required double total,
    required double cambio,
    required Future<void> Function() onImprimir,
  }) {
    return showDialog(
      context: context,
      builder: (_) => VentaExitosaDialog(
        idVenta: idVenta,
        total: total,
        cambio: cambio,
        onImprimir: onImprimir,
      ),
    );
  }

  @override
  State<VentaExitosaDialog> createState() => _VentaExitosaDialogState();
}

class _VentaExitosaDialogState extends State<VentaExitosaDialog> {
  bool _imprimiendo = false;

  void _nuevaVenta() {
    if (_imprimiendo) return;
    Navigator.pop(context);
  }

  Future<void> _imprimir() async {
    if (_imprimiendo) return;
    setState(() => _imprimiendo = true);
    try {
      await widget.onImprimir();
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.success;

    return CallbackShortcuts(
      bindings: {
        // Enter cierra y arranca una nueva venta: es la acción más frecuente
        // en un flujo de caja rápido.
        const SingleActivator(LogicalKeyboardKey.enter): _nuevaVenta,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _nuevaVenta,
        const SingleActivator(LogicalKeyboardKey.escape): _nuevaVenta,
      },
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Encabezado con ícono de éxito.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: 0.5),
                          width: 3,
                        ),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: accent, size: 40),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Venta realizada',
                      style: TextStyle(
                        fontSize: AppText.title,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Venta #${widget.idVenta}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppText.small,
                      ),
                    ),
                  ],
                ),
              ),

              // Resumen: Total y Cambio.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  children: [
                    _fila('Total', widget.total),
                    if (widget.cambio > 0) ...[
                      const SizedBox(height: 8),
                      _fila('Cambio', widget.cambio,
                          color: accent, destacado: true),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 4),
              const Divider(height: 1),

              // Acciones: imprimir ticket / nueva venta.
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: _imprimiendo ? null : _imprimir,
                        icon: _imprimiendo
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 20),
                        label: const Text('Imprimir ticket'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        autofocus: true,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: _imprimiendo ? null : _nuevaVenta,
                        child: const Text(
                          'Nueva venta',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, double valor,
      {Color? color, bool destacado = false}) {
    final estilo = TextStyle(
      color: color ?? AppColors.textStrong,
      fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
      fontSize: destacado ? AppText.titleLg : AppText.bodyLg,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(etiqueta, style: estilo),
        Text(AppConfig.formatoMoneda(valor), style: estilo),
      ],
    );
  }
}
