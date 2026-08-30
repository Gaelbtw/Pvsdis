import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/descuento_utils.dart';

/// Una línea del carrito: nombre, precio unitario (con su descuento si lo
/// tiene), cantidad e importe.
///
/// El campo de cantidad NO se reescribe en cada build —eso movía el cursor
/// mientras el cajero tecleaba—: el [cantidadCtrl] lo actualiza la vista solo
/// cuando el cambio viene de fuera del campo (botones +/- o un recorte por
/// existencia).
class LineaCarrito extends StatelessWidget {
  final Map<String, dynamic> item;

  /// La línea ya calculada (con promociones, descuento de línea y la parte
  /// proporcional del global), para no recalcular nada aquí.
  final LineaVentaCalculada calculada;

  final TextEditingController cantidadCtrl;
  final bool seleccionada;

  /// Es la línea que acaba de entrar al ticket.
  ///
  /// Distinta de [seleccionada], que marca dónde está el cursor de las flechas.
  /// Esta responde a otra pregunta, y es la que el cajero se hace cien veces al
  /// día sin despegar la vista del mostrador: *¿sí entró, y entró lo que era?*
  /// Con lector, uno pasa el producto y mira al cliente, no a la pantalla.
  final bool recienAgregada;
  final bool puedeAplicarDescuentos;

  final VoidCallback onSeleccionar;
  final VoidCallback onEditarDescuento;

  /// +1 / -1 desde los botones.
  final ValueChanged<int> onCambiarCantidad;

  /// Cantidad tecleada directamente en el campo. La vista decide si cabe.
  final ValueChanged<int> onCantidadTecleada;

  /// Quitar la línea completa del carrito.
  final VoidCallback onQuitar;

  const LineaCarrito({
    super.key,
    required this.item,
    required this.calculada,
    required this.cantidadCtrl,
    required this.seleccionada,
    this.recienAgregada = false,
    required this.puedeAplicarDescuentos,
    required this.onSeleccionar,
    required this.onEditarDescuento,
    required this.onCambiarCantidad,
    required this.onCantidadTecleada,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSeleccionar,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Recién agregada tiñe el fondo; seleccionada dibuja el borde. Son
          // dos señales distintas y pueden coincidir en la misma línea, así
          // que no pueden competir por el mismo recurso visual.
          color: recienAgregada ? AppColors.primaryLighter : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: seleccionada
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _nombreYDescuento(),
            const SizedBox(height: 6),
            _precioUnitario(),
            const SizedBox(height: 10),
            _cantidadEImporte(),
          ],
        ),
      ),
    );
  }

  Widget _nombreYDescuento() {
    return Row(
      children: [
        Expanded(
          child: Text(
            item['nombre'],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        if (puedeAplicarDescuentos)
          InkWell(
            onTap: onEditarDescuento,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.sell_outlined,
                size: 18,
                color: item['descuento_tipo'] != null
                    ? AppColors.primaryDark
                    : AppColors.disabled,
              ),
            ),
          ),
        // Quitar la línea de un toque. Antes solo se podía bajando la cantidad
        // hasta cero o seleccionando la línea y usando Supr: dos caminos que
        // hay que conocer, ninguno visible.
        InkWell(
          onTap: onQuitar,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close, size: 18, color: AppColors.error),
          ),
        ),
      ],
    );
  }

  Widget _precioUnitario() {
    final precio = (item['precio'] as num).toDouble();
    final tieneDescuento = item['descuento_tipo'] != null;
    final unitario = tieneDescuento && calculada.cantidad > 0
        ? (calculada.subtotalLinea - calculada.descuentoMonto) / calculada.cantidad
        : precio;

    return Text(
      tieneDescuento
          ? "${AppConfig.formatoMoneda(unitario)} c/u  ·  lista ${AppConfig.formatoMoneda(precio)}"
          : "${AppConfig.formatoMoneda(precio)} c/u",
      style: TextStyle(
        fontSize: AppText.caption,
        fontWeight: tieneDescuento ? FontWeight.w600 : FontWeight.w400,
        color: tieneDescuento ? AppColors.primaryDark : AppColors.textSecondary,
      ),
    );
  }

  Widget _cantidadEImporte() {
    // Importe de la línea con su propio descuento, sin el global (ese se
    // muestra una sola vez en la zona de cobro).
    final importe = calculada.subtotalLinea - calculada.descuentoMonto;

    return Row(
      children: [
        IconButton(
          onPressed: () => onCambiarCantidad(-1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 60,
          child: TextField(
            controller: cantidadCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (valor) {
              final cantidad = int.tryParse(valor);
              if (cantidad == null || cantidad <= 0) return;
              onCantidadTecleada(cantidad);
            },
          ),
        ),
        IconButton(
          onPressed: () => onCambiarCantidad(1),
          icon: const Icon(Icons.add_circle_outline),
        ),
        const Spacer(),
        Text(
          AppConfig.formatoMoneda(importe),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
