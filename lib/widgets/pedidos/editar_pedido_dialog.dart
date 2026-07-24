import 'package:flutter/material.dart';

import '../../controllers/pedidos_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/pedidos_model.dart';

/// Diálogo de edición de un pedido (estado, tipo de entrega, fecha,
/// dirección). Antes vivía completo dentro de `pedidos_view.dart` (~230
/// líneas entre el diálogo y su chip de tipo de entrega).
void mostrarEditarPedidoDialog(
  BuildContext context, {
  required Map<String, dynamic> pedidoMap,
  required PedidosController pedidosController,
  required VoidCallback onGuardado,
}) {
  String estado = pedidoMap['estado']?.toString() ?? 'Pendiente';
  String tipo = pedidoMap['tipo_entrega']?.toString() ?? 'Domicilio';
  String fechaEntregaStr = pedidoMap['fecha_entrega']?.toString() ?? '';
  String direccion = pedidoMap['direccion']?.toString() ?? '';

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Editar Pedido #${pedidoMap["id_pedido"]}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estado', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: estado,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: ['Pendiente', 'En Proceso', 'Entregado', 'Cancelado']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setDialog(() => estado = v!),
              ),
              const SizedBox(height: 16),
              const Text('Tipo de entrega', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _tipoChipDialog('Domicilio', tipo, (v) => setDialog(() => tipo = v)),
                  const SizedBox(width: 12),
                  _tipoChipDialog('Recoger', tipo, (v) => setDialog(() => tipo = v)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Fecha de entrega', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime(DateTime.now().year + 2),
                  );
                  if (picked != null) {
                    setDialog(() {
                      fechaEntregaStr = '${picked.day}/${picked.month}/${picked.year}';
                    });
                  }
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        fechaEntregaStr.isEmpty ? 'Seleccionar fecha' : fechaEntregaStr,
                        style: TextStyle(
                          color: fechaEntregaStr.isEmpty ? AppColors.textSecondary : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (tipo == 'Domicilio') ...[
                const SizedBox(height: 16),
                const Text('Dirección', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: direccion,
                  onChanged: (v) => direccion = v,
                  decoration: InputDecoration(
                    hintText: 'Calle, colonia, ciudad',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () async {
              final idPedido = pedidoMap['id_pedido'] as int;
              final estadoAnterior = pedidoMap['estado']?.toString() ?? 'Pendiente';

              final actualizado = Pedidos(
                idPedido: idPedido,
                idCliente: pedidoMap['id_cliente'] as int,
                fecha: pedidoMap['fecha']?.toString() ?? '',
                fechaEntrega: fechaEntregaStr,
                tipoEntrega: tipo,
                estado: estado,
                total: (pedidoMap['total'] as num?)?.toDouble() ?? 0,
                direccion: tipo == 'Domicilio' ? direccion : null,
              );

              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);

              // Actualiza el pedido y ajusta el inventario (si el cambio
              // de estado lo requiere) en una sola transacción atómica.
              await pedidosController.cambiarEstadoConAjusteInventario(
                actualizado,
                estadoAnterior,
              );

              if (!context.mounted) return;
              nav.pop();
              onGuardado();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    estado == 'Entregado' && estadoAnterior != 'Entregado'
                        ? 'Pedido entregado — inventario actualizado'
                        : estado == 'Cancelado' && estadoAnterior == 'Entregado'
                            ? 'Pedido cancelado — inventario restaurado'
                            : 'Pedido editado con éxito',
                  ),
                  backgroundColor: estado == 'Entregado'
                      ? AppColors.success
                      : estado == 'Cancelado'
                          ? AppColors.error
                          : Colors.blueGrey,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}

Widget _tipoChipDialog(String label, String selected, ValueChanged<String> onTap) {
  final activo = selected == label;
  return GestureDetector(
    onTap: () => onTap(label),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: activo ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: activo ? Colors.black : AppColors.textSecondary,
        ),
      ),
    ),
  );
}
