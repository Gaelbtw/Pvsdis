import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Barra de escaneo: el punto donde vive el foco durante todo el turno.
///
/// Antes era un `TextField` más, dentro de la tarjeta del catálogo y con el
/// tamaño de cualquier otro campo. Eso describía mal cómo se usa el sistema:
/// con lector de códigos, **casi toda** la venta entra por aquí y el catálogo
/// es la excepción --el producto a granel, el que perdió la etiqueta--. Sacarla
/// a una barra propia que cruza la pantalla no es adorno: es que el elemento
/// más usado se vea como el más importante.
///
/// El filo del color de marca al tener el foco responde a una pregunta real que
/// el cajero se hace varias veces al día: "¿está escuchando al lector?". Un
/// lector escribe tan rápido que, si el foco se fue a otro lado, el código
/// termina en cualquier campo y no pasa nada visible.
class BarraEscaneo extends StatelessWidget {
  const BarraEscaneo({
    super.key,
    required this.controlador,
    required this.foco,
    required this.onBuscar,
    required this.onEscanear,
    this.habilitada = true,
  });

  final TextEditingController controlador;
  final FocusNode foco;

  /// Texto tecleado, para filtrar el catálogo (amortiguado en la vista).
  final ValueChanged<String> onBuscar;

  /// Enter del lector: llega el código completo de una sola vez.
  final ValueChanged<String> onEscanear;

  final bool habilitada;

  static const double alto = 76;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: foco,
      builder: (context, _) {
        final enfocada = foco.hasFocus && habilitada;

        return Container(
          height: alto,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: enfocada ? AppColors.primary : AppColors.border,
              width: enfocada ? 1.5 : 1,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              Icon(
                Icons.qr_code_scanner_rounded,
                size: 26,
                color: enfocada ? AppColors.primaryDark : AppColors.textSecondary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ESCANEA O ESCRIBE',
                      style: TextStyle(
                        fontSize: AppText.overline,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    // `isDense` + `contentPadding` en cero: sin eso el campo
                    // reserva el alto de un TextField de Material y la barra
                    // se desborda de sus 76 px.
                    TextField(
                      controller: controlador,
                      focusNode: foco,
                      autofocus: true,
                      enabled: habilitada,
                      onChanged: onBuscar,
                      onSubmitted: onEscanear,
                      style: const TextStyle(
                        fontSize: AppText.titleLg,
                        color: AppColors.textPrimary,
                      ),
                      cursorColor: AppColors.primary,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: 'Código de barras, clave o nombre',
                        hintStyle: TextStyle(
                          fontSize: AppText.titleLg,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _atajo(enfocada),
            ],
          ),
        );
      },
    );
  }

  /// Recordatorio de F2. Se apaga cuando la barra ya tiene el foco: ahí el
  /// atajo no sirve de nada y el chip solo sería ruido encendido todo el día.
  Widget _atajo(bool enfocada) {
    return AnimatedOpacity(
      opacity: enfocada ? 0.35 : 1,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primaryLighter,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          'F2',
          style: TextStyle(
            fontSize: AppText.caption,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}
