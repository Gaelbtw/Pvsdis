import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/promociones_engine.dart';

/// Resumen de qué promociones automáticas se aplicaron al carrito actual y
/// cuánto ahorraron en total. Puramente informativo: el motor
/// (`promociones_engine.dart`) ya decidió qué aplica y por cuánto, esta
/// sección solo lo muestra.
class PromocionesAplicadasSection extends StatelessWidget {
  final List<PromocionAplicada> aplicaciones;
  final double ahorroTotal;

  const PromocionesAplicadasSection({
    super.key,
    required this.aplicaciones,
    required this.ahorroTotal,
  });

  @override
  Widget build(BuildContext context) {
    if (aplicaciones.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_outlined, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                "Promociones aplicadas",
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...aplicaciones.map(
            (a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(a.nombre, style: const TextStyle(fontSize: AppText.small))),
                  Text(
                    "-${AppConfig.formatoMoneda(a.ahorroTotal)}",
                    style: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w600, color: AppColors.success),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Ahorro total", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                "-${AppConfig.formatoMoneda(ahorroTotal)}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
