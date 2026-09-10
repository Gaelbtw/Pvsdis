import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auditoria_helpers.dart';
import '../../core/utils/stock_status.dart';

/// Tabla de productos de Inventario (encabezado + filas). Antes vivía
/// completa dentro de `inventario_view.dart` (~275 líneas).
class InventarioTabla extends StatelessWidget {
  final List<Map<String, dynamic>> productos;
  final int stockMinimo;
  /// Habilita el campo de entrada rápida de stock.
  final bool puedeAjustarInventario;

  /// Habilita el botón de eliminar producto.
  final bool puedeEliminar;
  final void Function(Map<String, dynamic> producto, int cantidad) onAgregarStock;
  final void Function(Map<String, dynamic> producto) onEditar;
  final void Function(Map<String, dynamic> producto) onEliminar;

  const InventarioTabla({
    super.key,
    required this.productos,
    required this.stockMinimo,
    required this.puedeAjustarInventario,
    required this.puedeEliminar,
    required this.onAgregarStock,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
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
          topLeft: Radius.circular(AppRadius.lg),
          topRight: Radius.circular(AppRadius.lg),
        ),
      ),
      child: const Row(
        children: [
          Expanded(flex: 24, child: Text("PRODUCTO", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("CATEGORÍA", style: auditoriaHeaderStyle)),
          Expanded(flex: 11, child: Text("COSTO", style: auditoriaHeaderStyle)),
          Expanded(flex: 11, child: Text("PRECIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("MARGEN", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("EXIST.", style: auditoriaHeaderStyle)),
          Expanded(flex: 15, child: Text("ESTADO", style: auditoriaHeaderStyle)),
          Expanded(flex: 19, child: Text("ACCIONES", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaProducto(Map<String, dynamic> p) {
    final stock = p['cantidad'] as int;
    final estado = clasificarStock(stock, stockMinimo);

    final precio = (p['precio'] as num?)?.toDouble() ?? 0;
    final costoCrudo = (p['precio_compra'] as num?)?.toDouble();

    // Sin costo capturado NO se inventa un margen. Tomar el costo como cero
    // daria 100% en cada producto sin dato: un margen falso y ademas
    // halagador, que es la peor combinacion posible en la pantalla donde se
    // deciden los precios.
    final costo = (costoCrudo == null || costoCrudo <= 0) ? null : costoCrudo;
    final margen =
        (costo == null || precio <= 0) ? null : (precio - costo) / precio * 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(
            flex: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p['nombre'],
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
                ),
                if (p['sku'] != null)
                  Text(
                    p['sku'].toString(),
                    style: const TextStyle(
                      fontSize: AppText.overline,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 14,
            child: Text(p['categoria_nombre'] ?? 'Sin categoría',
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 11,
            child: Text(
              costo == null ? '—' : AppConfig.formatoMoneda(costo),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 11,
            child: Text(
              AppConfig.formatoMoneda(precio),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              margen == null ? '—' : '${margen.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: AppText.small,
                // Rojo si se vende por debajo del costo. Ese caso existe y no
                // se nota: alguien sube el costo al capturar la compra y
                // nadie vuelve a mirar el precio de venta.
                color: margen == null
                    ? AppColors.textSecondary
                    : margen < 0
                        ? AppColors.error
                        : margen < 20
                            ? AppColors.warning
                            : AppColors.success,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text("$stock",
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            flex: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: estado.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.pill),
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
                        fontSize: AppText.caption,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 19,
            child: Row(
              children: [
                if (puedeAjustarInventario)
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
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
                if (puedeEliminar)
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
