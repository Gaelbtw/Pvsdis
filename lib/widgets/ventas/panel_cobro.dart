import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/descuento_utils.dart';
import '../../core/utils/pagos_mixtos.dart';
import 'pagos_mixtos_section.dart';

/// Zona de cobro: subtotal/descuento discretos, el TOTAL como el elemento
/// dominante de la pantalla (lo leen cajero y cliente), los pagos y el botón de
/// confirmar, todo dentro de un panel para que el ojo aterrice aquí de
/// inmediato.
class PanelCobro extends StatelessWidget {
  /// Desglose ya calculado de la venta en curso.
  final VentaCalculada venta;

  /// `true` cuando se puede cobrar (hay carrito, los pagos cuadran y la caja
  /// está abierta).
  final bool habilitado;

  /// Cambia con cada venta terminada; se usa como `key` de la sección de pagos
  /// para que se reinicie limpia en la siguiente.
  final int ventaCounter;

  final void Function(List<Map<String, dynamic>> pagos, ResultadoValidacionPagos resultado) onCambioPagos;
  final VoidCallback onConfirmar;

  const PanelCobro({
    super.key,
    required this.venta,
    required this.habilitado,
    required this.ventaCounter,
    required this.onCambioPagos,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (venta.descuentoTotal > 0) ...[
            _lineaResumen("Subtotal", AppConfig.formatoMoneda(venta.subtotal)),
            const SizedBox(height: 6),
            _lineaResumen(
              "Descuento",
              "-${AppConfig.formatoMoneda(venta.descuentoTotal)}",
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  "TOTAL",
                  style: TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    AppConfig.formatoMoneda(venta.total),
                    style: const TextStyle(
                      fontSize: AppText.hero,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          PagosMixtosSection(
            key: ValueKey(ventaCounter),
            total: venta.total,
            onCambio: onCambioPagos,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: habilitado ? onConfirmar : null,
              icon: const Icon(Icons.check_circle),
              label: const Text(
                "Confirmar venta  ·  F4",
                style: TextStyle(fontSize: AppText.bodyLg, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaResumen(String etiqueta, String valor, {Color? color}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            valor,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
