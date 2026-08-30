import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Columna derecha de la pantalla de venta: cobro y catálogo, en pestañas.
///
/// El cobro es la pestaña de arranque y la que importa. El catálogo pasó aquí
/// desde la mitad izquierda de la pantalla porque, con lector de códigos, casi
/// no se usa: tenerlo ocupando el 62% del ancho todo el día era darle el mejor
/// lugar de la pantalla a la excepción.
///
/// Se dibujan las DOS pestañas siempre (con [IndexedStack], no reconstruyendo)
/// para no perder el estado de la otra al cambiar: el filtro de categoría, la
/// posición del scroll de la rejilla y los importes tecleados en los pagos
/// mixtos sobreviven a ir y volver.
class PanelLateralVenta extends StatefulWidget {
  const PanelLateralVenta({
    super.key,
    required this.cobro,
    required this.catalogo,
  });

  final Widget cobro;
  final Widget catalogo;

  @override
  State<PanelLateralVenta> createState() => _PanelLateralVentaState();
}

class _PanelLateralVentaState extends State<PanelLateralVenta> {
  int _pestana = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _selector(),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: IndexedStack(
                index: _pestana,
                sizing: StackFit.expand,
                children: [
                  // El cobro no llena el alto por sí solo: se ancla abajo para
                  // que el botón de cobrar quede siempre en el mismo lugar,
                  // lleve el ticket dos líneas o quince.
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [widget.cobro],
                  ),
                  widget.catalogo,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _boton('Cobro', 0),
          const SizedBox(width: 4),
          _boton('Catálogo', 1),
        ],
      ),
    );
  }

  Widget _boton(String texto, int indice) {
    final activa = _pestana == indice;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _pestana = indice),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activa ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: activa
                ? const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: AppText.small,
              fontWeight: activa ? FontWeight.w800 : FontWeight.w500,
              color: activa ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
