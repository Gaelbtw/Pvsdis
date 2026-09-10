import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/vista_corte.dart';

/// Tarjeta, transferencia y anticipos cobrados con plastico: dinero real del
/// turno que **nunca estuvo en el cajon**.
///
/// Vive en su propia tarjeta, con su propio encabezado y separado del bloque
/// de efectivo, porque confundir ambos es el error mas comun de quien aprende
/// a hacer un corte — y hasta ahora la pantalla lo invitaba, mostrando
/// "Tarjeta $5,077.50" en una tarjeta identica a la de "Efectivo $3,355.00",
/// una junto a la otra y sin ninguna senal de que solo una de las dos se
/// cuenta con las manos.
///
/// Se muestra igual a quien cuenta a ciegas: ninguno de estos montos aparece
/// en la formula del efectivo esperado, asi que no filtra nada, y al cajero le
/// sirve para cuadrar sus vouchers.
class PanelNoEfectivo extends StatelessWidget {
  const PanelNoEfectivo({super.key, required this.vista, this.nota});

  final VistaCorte vista;

  /// Aclaracion junto al titulo. Cambia segun quien mira: al que audita se le
  /// dice que no lo cuente, al cajero para que le sirve.
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final columnas = <({String titulo, double monto})>[
      (titulo: 'TARJETA', monto: vista.ventasTarjeta),
      (titulo: 'TRANSFERENCIA', monto: vista.ventasTransferencia),
      if (vista.anticiposTarjeta + vista.anticiposTransferencia > 0)
        (
          titulo: 'ANTICIPOS S/EFECTIVO',
          monto: vista.anticiposTarjeta + vista.anticiposTransferencia,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'No pasa por el cajón',
                style: TextStyle(
                  fontSize: AppText.bodyLg,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (nota != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    nota!,
                    style: const TextStyle(
                      fontSize: AppText.small,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (var i = 0; i < columnas.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _celda(columnas[i].titulo, columnas[i].monto)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _celda(String titulo, double monto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: AppText.overline,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            AppConfig.formatoMoneda(monto),
            style: const TextStyle(
              fontSize: AppText.subtitle,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
