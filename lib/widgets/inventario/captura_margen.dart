import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/producto_model.dart';

/// Margen del producto dentro del formulario de alta/edición.
///
/// Hace dos cosas que antes había que calcular a mano en una calculadora:
/// muestra en vivo el margen que dejan el precio de compra y el de venta ya
/// capturados, y permite el camino inverso —"quiero ganar 35%"— fijando el
/// precio de venta a partir del costo. Es margen sobre el PRECIO (lo que se
/// usa en los reportes de utilidad), no sobre el costo: si se calcularan de
/// formas distintas, el formulario y el reporte darían números diferentes
/// para el mismo producto.
///
/// No guarda nada: el margen no es una columna, es una relación entre dos
/// precios que sí se guardan. Escribir aquí solo modifica el campo de precio.
class CapturaMargen extends StatefulWidget {
  final TextEditingController precioCtrl;
  final TextEditingController precioCompraCtrl;

  const CapturaMargen({
    super.key,
    required this.precioCtrl,
    required this.precioCompraCtrl,
  });

  @override
  State<CapturaMargen> createState() => _CapturaMargenState();
}

class _CapturaMargenState extends State<CapturaMargen> {
  final _margenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.precioCtrl.addListener(_alCambiarPrecios);
    widget.precioCompraCtrl.addListener(_alCambiarPrecios);
  }

  @override
  void dispose() {
    widget.precioCtrl.removeListener(_alCambiarPrecios);
    widget.precioCompraCtrl.removeListener(_alCambiarPrecios);
    _margenCtrl.dispose();
    super.dispose();
  }

  void _alCambiarPrecios() {
    if (mounted) setState(() {});
  }

  double? get _precio => double.tryParse(widget.precioCtrl.text.trim());
  double? get _costo => double.tryParse(widget.precioCompraCtrl.text.trim());

  /// Aplica el margen deseado: calcula el precio de venta desde el costo y lo
  /// escribe en el campo de precio.
  void _aplicarMargen() {
    final costo = _costo;
    final margen = double.tryParse(_margenCtrl.text.trim().replaceAll('%', ''));

    if (costo == null || costo <= 0 || margen == null) return;

    final precio = Producto.precioParaMargen(costo: costo, margen: margen);
    if (precio == null) return;

    widget.precioCtrl.text = (precio * 100).round() / 100 == precio
        ? precio.toString()
        : precio.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final precio = _precio;
    final costo = _costo;

    final producto = (precio == null || costo == null)
        ? null
        : Producto(nombre: '', descripcion: '', precio: precio, precioCompra: costo);
    final margen = producto?.margenPorcentaje;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              margen == null
                  ? "Captura precio de compra y de venta para ver el margen"
                  : "Margen ${margen.toStringAsFixed(1)}% · Ganas "
                      "${AppConfig.formatoMoneda(precio! - costo!)} por pieza",
              style: TextStyle(
                fontSize: AppText.caption,
                fontWeight: margen == null ? FontWeight.w500 : FontWeight.w700,
                color: margen == null
                    ? AppColors.textSecondary
                    : (margen < 0 ? AppColors.error : AppColors.textStrong),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _margenCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _aplicarMargen(),
              decoration: InputDecoration(
                hintText: "Margen %",
                hintStyle: const TextStyle(fontSize: AppText.caption),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _aplicarMargen,
            child: const Text("Calcular precio"),
          ),
        ],
      ),
    );
  }
}
