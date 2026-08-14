import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/producto_model.dart';

/// Mitad izquierda del punto de venta: buscador/escáner, filtro por categoría
/// y rejilla de productos.
///
/// Antes vivía dentro del `build` de `ventas_view.dart`, anidada una decena de
/// niveles. No tiene estado ni reglas: recibe la lista ya filtrada y avisa por
/// callbacks. Toda la decisión de qué se puede agregar sigue en la vista (ver
/// `validarCantidadEnCarrito`).
class CatalogoProductos extends StatelessWidget {
  final TextEditingController busquedaCtrl;
  final FocusNode busquedaFocus;

  /// Texto tecleado (con amortiguación en la vista).
  final ValueChanged<String> onBuscar;

  /// Enter del lector de códigos: llega el código completo de una vez.
  final ValueChanged<String> onEscanear;

  /// Categorías presentes en el catálogo, ya ordenadas.
  final List<({int id, String nombre})> categorias;
  final int? categoriaFiltro;
  final ValueChanged<int?> onFiltrarCategoria;

  /// Productos que hay que dibujar (ya filtrados por texto y categoría).
  final List<Producto> productos;

  /// Existencia disponible por producto, para pintar el estado de cada tarjeta.
  final Map<int, int> existencias;

  final ValueChanged<Producto> onAgregar;

  const CatalogoProductos({
    super.key,
    required this.busquedaCtrl,
    required this.busquedaFocus,
    required this.onBuscar,
    required this.onEscanear,
    required this.categorias,
    required this.categoriaFiltro,
    required this.onFiltrarCategoria,
    required this.productos,
    required this.existencias,
    required this.onAgregar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          _buscador(),
          _filtroCategorias(),
          const SizedBox(height: 20),
          Expanded(child: _rejilla()),
        ],
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: busquedaCtrl,
      focusNode: busquedaFocus,
      autofocus: true,
      onChanged: onBuscar,
      onSubmitted: onEscanear,
      decoration: InputDecoration(
        hintText: "Buscar por nombre, clave, categoría o código...",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Fila de categorías sobre la rejilla. No se dibuja si el catálogo no tiene
  /// categorías: una sola píldora de "Todos" no filtraría nada y solo robaría
  /// alto a la rejilla.
  Widget _filtroCategorias() {
    if (categorias.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: categorias.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final esTodos = i == 0;
            final categoria = esTodos ? null : categorias[i - 1];
            final seleccionada = categoriaFiltro == categoria?.id;

            return ChoiceChip(
              label: Text(esTodos ? "Todos" : categoria!.nombre),
              selected: seleccionada,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              side: BorderSide(color: seleccionada ? AppColors.primary : AppColors.border),
              labelStyle: TextStyle(
                fontSize: AppText.caption,
                fontWeight: FontWeight.w700,
                color: seleccionada ? AppColors.onPrimary : AppColors.textPrimary,
              ),
              onSelected: (_) => onFiltrarCategoria(categoria?.id),
            );
          },
        ),
      ),
    );
  }

  Widget _rejilla() {
    // Grilla adaptativa: la cantidad de columnas se ajusta al ancho de la
    // ventana (≈5 a 1280px, menos al achicar) y cada tarjeta tiene alto fijo,
    // así no se desborda en la ventana mínima.
    //
    // Nota: aquí se probó reducir la caché de scroll para que la grilla no
    // construya dos filas de más fuera de pantalla. Se quitó porque
    // `cacheExtent` quedó obsoleto en Flutter 3.41 y su reemplazo
    // (`scrollCacheExtent`) ya no acepta un número de píxeles sino un
    // `ScrollCacheExtent`. La ganancia era marginal frente al riesgo de usar mal
    // una API que no se pudo verificar; el cuello de botella real de esta
    // grilla era el filtro, que ya está resuelto.
    return GridView.builder(
      itemCount: productos.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 132,
      ),
      itemBuilder: (_, i) => _tarjeta(productos[i]),
    );
  }

  Widget _tarjeta(Producto p) {
    // Lo que no se puede vender se atenúa en vez de ocultarse: el cajero
    // necesita ver que el producto existe (para decirle al cliente que se
    // acabó) sin que la tarjeta invite a tocarla. Tocarla igual avisa por qué.
    final existencia = existencias[p.idProducto] ?? 0;
    final vendible = p.estado == 'Activo' && existencia > 0;

    return Opacity(
      opacity: vendible ? 1 : 0.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onAgregar(p),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFDFD),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              _estadoInventario(p, existencia),
              const Spacer(),
              // Precio + señal de agregar (toda la tarjeta agrega al tocar; el
              // chip solo lo señala).
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppConfig.formatoMoneda(p.precio),
                        style: const TextStyle(
                          fontSize: AppText.subtitle,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.add, size: 18, color: AppColors.onPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// La tarjeta tiene alto fijo (`mainAxisExtent`), así que este renglón se
  /// limita a una línea con puntos suspensivos: con un nombre de producto que
  /// ocupa dos líneas y una existencia de varios dígitos, el texto empujaba el
  /// contenido y la tarjeta se desbordaba.
  Widget _estadoInventario(Producto p, int existencia) {
    if (p.estado != 'Activo') {
      return const Text(
        "Inactivo",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppText.caption,
          color: AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Text(
      existencia == 0 ? "Agotado" : "Inventario: $existencia",
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AppText.caption,
        color: existencia == 0
            ? AppColors.error
            : existencia <= p.stockMinimo
                ? AppColors.warning
                : AppColors.success,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
