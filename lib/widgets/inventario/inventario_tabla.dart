import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/auditoria_helpers.dart';
import '../../core/utils/stock_status.dart';

/// Tabla de productos de Inventario (encabezado + filas). Antes vivía
/// completa dentro de `inventario_view.dart` (~275 líneas).
class InventarioTabla extends StatelessWidget {
  final List<Map<String, dynamic>> productos;
  final int stockMinimo;
  final bool esCajero;
  final void Function(Map<String, dynamic> producto, int cantidad) onAgregarStock;
  final void Function(Map<String, dynamic> producto) onEditar;
  final void Function(Map<String, dynamic> producto) onEliminar;

  const InventarioTabla({
    super.key,
    required this.productos,
    required this.stockMinimo,
    required this.esCajero,
    required this.onAgregarStock,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E2D9)),
      ),
      child: Column(
        children: [
          _headerTabla(),
          Expanded(
            child: productos.isEmpty
                ? const Center(child: Text("No hay productos"))
                : ListView.separated(
                    itemCount: productos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _filaProducto(productos[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _headerTabla() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
        ),
      ),
      child: const Row(
        children: [
          Expanded(flex: 22, child: Text("PRODUCTO", style: auditoriaHeaderStyle)),
          Expanded(flex: 18, child: Text("CATEGORÍA", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("PRECIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("STOCK", style: auditoriaHeaderStyle)),
          Expanded(flex: 16, child: Text("ESTADO", style: auditoriaHeaderStyle)),
          Expanded(flex: 20, child: Text("ACCIONES", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaProducto(Map<String, dynamic> p) {
    final stock = p['cantidad'] as int;
    final estado = clasificarStock(stock, stockMinimo);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(
            flex: 22,
            child: Text(
              p['nombre'],
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textMuted),
            ),
          ),
          Expanded(flex: 18, child: Text(p['categoria_nombre'] ?? 'Sin categoría')),
          Expanded(
            flex: 12,
            child: Text(
              "\$${p['precio']}",
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(flex: 12, child: Text("$stock")),
          Expanded(
            flex: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: estado.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(estado.icono, size: 16, color: estado.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      estado.etiqueta,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: estado.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: Row(
              children: [
                SizedBox(
                  width: 75,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "Cant",
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (value) {
                      final cantidad = int.tryParse(value) ?? 0;
                      if (cantidad <= 0) return;
                      onAgregarStock(p, cantidad);
                    },
                  ),
                ),
                IconButton(
                  tooltip: "Editar",
                  icon: Icon(Icons.edit_outlined, color: AppColors.primaryDark),
                  onPressed: () => onEditar(p),
                ),
                if (!esCajero)
                  IconButton(
                    tooltip: "Eliminar",
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () => onEliminar(p),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
