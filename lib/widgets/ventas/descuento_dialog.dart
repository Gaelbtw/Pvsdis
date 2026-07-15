import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/descuento_utils.dart';

/// Diálogo para aplicar (o quitar) un descuento porcentual o fijo sobre
/// [base] — se usa tanto para el descuento de un producto como para el
/// descuento global de la venta. Valida en vivo con
/// `calcularMontoDescuento` para mostrar el monto resultante o el error
/// apenas el usuario escribe, sin esperar a intentar guardar.
Future<void> mostrarDescuentoDialog(
  BuildContext context, {
  required String titulo,
  required double base,
  TipoDescuento? tipoActual,
  double valorActual = 0,
  required void Function(TipoDescuento tipo, double valor) onAplicar,
  VoidCallback? onQuitar,
}) {
  var tipo = tipoActual ?? TipoDescuento.porcentaje;
  final valorCtrl = TextEditingController(
    text: valorActual > 0 ? _formatearValor(valorActual) : '',
  );

  return showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialog) {
        final valor = double.tryParse(valorCtrl.text.replaceAll(',', '.')) ?? 0;

        String? error;
        double montoPreview = 0;
        if (valor > 0) {
          try {
            montoPreview = calcularMontoDescuento(tipo: tipo, valor: valor, base: base).monto;
          } catch (e) {
            error = e.toString().replaceFirst('Exception: ', '');
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Base: ${AppConfig.formatoMoneda(base)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _tipoChip(
                        label: 'Porcentaje',
                        activo: tipo == TipoDescuento.porcentaje,
                        onTap: () => setDialog(() => tipo = TipoDescuento.porcentaje),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _tipoChip(
                        label: 'Monto fijo',
                        activo: tipo == TipoDescuento.fijo,
                        onTap: () => setDialog(() => tipo = TipoDescuento.fijo),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valorCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tipo == TipoDescuento.porcentaje ? 'Porcentaje (%)' : 'Monto (\$)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (_) => setDialog(() {}),
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error, style: const TextStyle(color: Colors.red, fontSize: 13))
                else if (valor > 0)
                  Text(
                    'Descuento: -${AppConfig.formatoMoneda(montoPreview)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            if (onQuitar != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  onQuitar();
                },
                child: const Text('Quitar descuento', style: TextStyle(color: Colors.red)),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: (error == null && valor > 0)
                      ? () {
                          Navigator.pop(dialogContext);
                          onAplicar(tipo, valor);
                        }
                      : null,
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

String _formatearValor(double valor) {
  return valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toString();
}

Widget _tipoChip({
  required String label,
  required bool activo,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: activo ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: activo ? Colors.black : Colors.grey.shade600,
        ),
      ),
    ),
  );
}
