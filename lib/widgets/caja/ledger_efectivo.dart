import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/vista_corte.dart';

/// El efectivo del turno como una cuenta que se puede seguir con el dedo.
///
/// Antes esto eran nueve tarjetas del mismo tamano, sin signo y en cualquier
/// orden. Dos problemas de fondo:
///
/// 1. **No decian su signo.** "Cambio entregado $412" junto a "Ventas en
///    efectivo $3,355" se lee como si ambos entraran al cajon.
/// 2. **No estaban todas.** Los anticipos de apartados y los pagos a
///    proveedores en efectivo SI entran en `efectivoEsperado`, pero no tenian
///    tarjeta. En un negocio con apartados, el esperado que mostraba la
///    pantalla no se podia reconstruir sumando lo que se veia, y quien
///    revisaba concluia que el sistema se habia equivocado.
///
/// Los renglones salen de `ResumenCaja.renglonesEfectivo`, la misma lista que
/// imprime el ticket, para que papel y pantalla no puedan discrepar.
class LedgerEfectivo extends StatelessWidget {
  const LedgerEfectivo({
    super.key,
    required this.vista,
    this.titulo = 'Efectivo — esto sí está en el cajón',
    this.notaTotal = 'Solo lo ve quien audita, no quien cuenta',
  });

  final VistaCorte vista;
  final String titulo;
  final String notaTotal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: vista.aCiegas ? _bloqueado() : _abierto(),
    );
  }

  // ---------------------------------------------------------------- abierto

  Widget _abierto() {
    final renglones = vista.renglonesEfectivo;
    final entradas = renglones.where((r) => r.suma).toList();
    final salidas = renglones.where((r) => !r.suma).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezado(Icons.point_of_sale_outlined, titulo),
        const SizedBox(height: 12),
        for (final r in entradas) _renglon(r.etiqueta, r.importe, suma: true),
        if (salidas.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 6),
          for (final r in salidas) _renglon(r.etiqueta, r.importe, suma: false),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Debería haber en el cajón',
                      style: TextStyle(
                        fontSize: AppText.body,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (notaTotal.isNotEmpty)
                      Text(
                        notaTotal,
                        style: const TextStyle(
                          fontSize: AppText.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                AppConfig.formatoMoneda(vista.efectivoEsperado ?? 0),
                style: const TextStyle(
                  fontSize: AppText.display,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _renglon(String etiqueta, double importe, {required bool suma}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              suma ? '+' : '−',
              style: TextStyle(
                fontSize: AppText.body,
                fontWeight: FontWeight.w700,
                color: suma ? AppColors.success : AppColors.error,
              ),
            ),
          ),
          Expanded(
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: AppText.body, color: AppColors.textSecondary),
            ),
          ),
          Text(
            AppConfig.formatoMoneda(importe),
            style: const TextStyle(
              fontSize: AppText.body,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- bloqueado

  /// Lo que ve quien cuenta a ciegas: la forma de la cuenta, sin sus numeros.
  ///
  /// Se muestran las etiquetas y no una pantalla en blanco a proposito: el
  /// cajero debe saber QUE se le va a comparar, aunque todavia no cuanto.
  Widget _bloqueado() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _encabezado(Icons.lock_outline_rounded, 'Efectivo del turno',
            sufijo: '— se revela al cerrar'),
        const SizedBox(height: 12),
        for (final etiqueta in const [
          'Fondo inicial',
          'Ventas en efectivo',
          'Entradas y salidas',
        ])
          _renglonOculto(etiqueta),
        _renglonOculto('Debería haber en el cajón', fuerte: true),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 19, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: AppText.small,
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                    children: [
                      TextSpan(text: 'Cuentas primero, ves los números después. Esto '),
                      TextSpan(
                        text: 'te protege a ti',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                      TextSpan(
                        text: ': nadie puede decir luego que ajustaste el conteo para '
                            'que cuadrara. Al cerrar se te muestra todo, y también '
                            'sale impreso en tu corte.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _renglonOculto(String etiqueta, {bool fuerte = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: AppText.body,
                fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400,
                color: fuerte ? AppColors.textStrong : AppColors.textSecondary,
              ),
            ),
          ),
          const Text(
            '•••••',
            style: TextStyle(
              fontSize: AppText.body,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- comun

  Widget _encabezado(IconData icono, String texto, {String? sufijo}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icono, size: 18, color: AppColors.textStrong),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: AppText.bodyLg,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (sufijo != null) ...[
          const SizedBox(width: 7),
          Text(
            sufijo,
            style: const TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
