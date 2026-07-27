import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/app_colors.dart';

/// Barra superior mínima que reemplaza la barra de título nativa de Windows
/// (la que decía "Pv Control"). Se integra con el fondo de la app: a la
/// izquierda una zona para arrastrar/mover la ventana, y a la derecha los
/// botones de minimizar, maximizar/restaurar y cerrar.
///
/// Se coloca una sola vez, por encima de todas las pantallas, desde
/// `MaterialApp.builder`.
class BarraVentana extends StatelessWidget {
  const BarraVentana({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: AppColors.background,
      child: Row(
        children: [
          // Zona arrastrable para mover la ventana (ocupa el resto del ancho).
          Expanded(
            child: DragToMoveArea(
              child: const SizedBox.expand(),
            ),
          ),
          _BotonVentana(
            icono: Icons.remove_rounded,
            onTap: () => windowManager.minimize(),
          ),
          _BotonVentana(
            icono: Icons.crop_square_rounded,
            iconoSize: 14,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _BotonVentana(
            icono: Icons.close_rounded,
            onTap: () => windowManager.close(),
            colorHover: AppColors.error,
            colorIconoHover: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _BotonVentana extends StatefulWidget {
  final IconData icono;
  final VoidCallback onTap;
  final double iconoSize;
  final Color? colorHover;
  final Color? colorIconoHover;

  const _BotonVentana({
    required this.icono,
    required this.onTap,
    this.iconoSize = 16,
    this.colorHover,
    this.colorIconoHover,
  });

  @override
  State<_BotonVentana> createState() => _BotonVentanaState();
}

class _BotonVentanaState extends State<_BotonVentana> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 34,
          alignment: Alignment.center,
          color: _hover ? (widget.colorHover ?? AppColors.surfaceAlt) : Colors.transparent,
          child: Icon(
            widget.icono,
            size: widget.iconoSize,
            color: _hover ? (widget.colorIconoHover ?? AppColors.textPrimary) : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
