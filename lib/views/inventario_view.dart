import 'package:flutter/material.dart';

import '../widgets/toast.dart';

import '../core/utils/mensaje_error.dart';
import '../widgets/estado_vista.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../controllers/auditoria_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/categoria_controller.dart';
import '../core/utils/stock_status.dart';
import '../models/auditoria_model.dart';
import '../models/categoria_model.dart';
import '../widgets/confirm_action.dart';
import '../widgets/nav_bar.dart';
import '../widgets/historial_cambios_dialog.dart';
import '../widgets/inventario/editar_producto_dialog.dart';
import '../widgets/inventario/inventario_tabla.dart';
import '../services/configuracion_service.dart';
import '../models/configuracion_model.dart';
import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';

class InventarioView extends StatefulWidget {
  const InventarioView({super.key});

  @override
  State<InventarioView> createState() => _InventarioViewState();
}

class _InventarioViewState extends State<InventarioView> {
  final productoController = ProductoController();
  final categoriaController = CategoriaController();
  final auditoriaController = AuditoriaController();

  // Inicializado con valores por defecto para evitar LateInitializationError
  // si algún build ocurre antes de que `inicializar()` cargue la config real.
  Configuracion config = Configuracion.porDefecto();

  bool cargando = true;

  /// Mensaje del último fallo al cargar, o `null`. Con esto la pantalla
  /// puede decir qué pasó y ofrecer reintentar, en vez de dejar la rueda
  /// girando para siempre.
  String? _errorCarga;

  List<Map<String, dynamic>> productos = [];
  List<Categoria> categorias = [];
  List<Auditoria> cambios = [];

  int? categoriaSeleccionada;
  String busqueda = "";

  /// Filtro por nivel de existencia: `null` es "todos".
  ///
  /// Antes esto no existia y arriba habia cuatro recuadros que solo decian
  /// numeros. Ver "Inventario bajo: 7" no sirve de nada si para saber CUALES
  /// hay que recorrer la tabla a ojo. Los mismos numeros, ahora, filtran.
  EstadoStock? estadoSeleccionado;

  /// Editar el producto en sí (nombre, precio) y ver su historial de
  /// cambios. Antes ambas cosas y el ajuste de stock colgaban de un único
  /// `rol == "Cajero"`, ignorando la matriz de permisos.
  bool get puedeGestionarProductos =>
      PermisosService.instancia.puedeActual(Permiso.gestionarProductos);

  /// Modificar existencias. Es un permiso distinto a propósito: hay negocios
  /// donde el cajero cuenta inventario pero no toca precios.
  bool get puedeAjustarInventario =>
      PermisosService.instancia.puedeActual(Permiso.ajustarInventario);

  @override
  void initState() {
    super.initState();
    inicializar();
  }

  Future<void> inicializar() async {
    if (mounted) setState(() => _errorCarga = null);
    try {
      config = await ConfiguracionService().obtener();

      await cargarTodo();

      if (!mounted) return;

      setState(() {
        cargando = false;
      });
    } catch (e) {
      // Sin esto la bandera nunca se apagaba y la rueda giraba para
      // siempre: el error solo llegaba a la consola.
      if (!mounted) return;
      setState(() {
        cargando = false;
        _errorCarga = mensajeDeError(e);
      });
    }
  }

  Future<void> cargarTodo() async {
    try {
      final prod = await productoController.obtenerConStock();
      final cat = await categoriaController.obtenerTodos();
      final audit =
          await auditoriaController.obtenerPorTablas(['Productos', 'Inventario']);

      productos = prod;
      categorias = cat;
      cambios = audit;
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo cargar el inventario. ${mensajeDeError(e)}');
    }
  }

  List<Map<String, dynamic>> get filtrados {
    return productos.where((p) {
      final consulta = busqueda.toLowerCase();
      // Se busca también por clave y código de barras: en un conteo físico se
      // tiene la etiqueta del producto en la mano, no su nombre exacto.
      final matchBusqueda = p['nombre'].toLowerCase().contains(consulta) ||
          (p['sku']?.toString().toLowerCase().contains(consulta) ?? false) ||
          (p['codigo_barras']?.toString().toLowerCase().contains(consulta) ?? false);

      final matchCategoria = categoriaSeleccionada == null ||
          p['id_categoria'] == categoriaSeleccionada;

      final matchEstado = estadoSeleccionado == null ||
          clasificarStock(p['cantidad'] as int, config.stockMinimo) ==
              estadoSeleccionado;

      return matchBusqueda && matchCategoria && matchEstado;
    }).toList();
  }

  void confirmarEliminar(Map<String, dynamic> p) {
    confirmarAccion(
      context: context,
      tituloConfirmar: "Eliminar producto",
      mensajeConfirmar: "¿Deseas eliminar ${p['nombre']}?",
      iconoConfirmar: Icons.warning_amber_rounded,
      textoConfirmar: "Eliminar",
      accion: () async {
        // Un producto con ventas no se puede borrar (FK RESTRICT); el
        // controlador ya devuelve el motivo en texto claro.
        await productoController.eliminar(p['id_producto']);
        await inicializar();
      },
      tituloExito: "Producto eliminado",
      mensajeExito: "El producto ha sido eliminado exitosamente.",
    );
  }

  Future<void> mostrarCambiosInventario() async {
    try {
      await cargarTodo();
      if (!mounted) return;
      setState(() {});

      if (!mounted) return;
      await mostrarHistorialCambios(
        context,
        titulo: "Cambios de inventario",
        subtitulo: "Consulta quién creó, modificó o eliminó productos e inventario.",
        cambios: cambios,
      );
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo abrir el historial de cambios. ${mensajeDeError(e)}');
    }
  }

  void mostrarEditarProducto(Map<String, dynamic> p) {
    mostrarEditarProductoDialog(
      context,
      producto: p,
      puedeEditarProducto: puedeGestionarProductos,
      puedeAjustarInventario: puedeAjustarInventario,
      productoController: productoController,
      onGuardado: inicializar,
    );
  }

  Future<void> _agregarStockRapido(Map<String, dynamic> p, int cantidad) async {
    try {
      await productoController.agregarStock(p['id_producto'], cantidad);
      await inicializar();
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo agregar la existencia. ${mensajeDeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ResumenStock.desde(productos, config.stockMinimo);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(
        titulo: "Inventario",
        mostrarVolver: true,
        extraActions: [
          if (puedeGestionarProductos)
            IconButton(
              tooltip: "Cambios de inventario",
              icon: const Icon(Icons.history, color: Colors.black87),
              onPressed: mostrarCambiosInventario,
            ),
        ],
      ),
      body: (cargando || _errorCarga != null)
          ? EstadoVista(cargando: cargando, error: _errorCarga, onReintentar: inicializar)
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _filtros(resumen),
                    const SizedBox(height: 20),
                    Expanded(
                      child: InventarioTabla(
                        productos: filtrados,
                        stockMinimo: config.stockMinimo,
                        puedeAjustarInventario: puedeAjustarInventario,
                        puedeEliminar: puedeGestionarProductos,
                        onAgregarStock: _agregarStockRapido,
                        onEditar: mostrarEditarProducto,
                        onEliminar: confirmarEliminar,
                      ),
                    ),
                    _pieTabla(),
                  ],
                ),
              ),
            ),
    );
  }

  /// Pastillas de estado: informan y filtran a la vez.
  ///
  /// Reemplazan a cuatro tarjetas que solo informaban. "Inventario bajo: 7"
  /// obliga a recorrer la tabla a ojo para saber cuales son los siete; la
  /// pastilla los deja en pantalla de un clic. Y el numero sigue ahi.
  Widget _pastillasEstado(ResumenStock resumen) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _pastilla(
          etiqueta: 'Todos',
          cuenta: productos.length,
          color: AppColors.textPrimary,
          activa: estadoSeleccionado == null,
          onTap: () => setState(() => estadoSeleccionado = null),
        ),
        _pastilla(
          etiqueta: 'Bajos',
          cuenta: resumen.bajos,
          color: AppColors.warning,
          activa: estadoSeleccionado == EstadoStock.bajo,
          onTap: () => setState(() => estadoSeleccionado =
              estadoSeleccionado == EstadoStock.bajo ? null : EstadoStock.bajo),
        ),
        _pastilla(
          etiqueta: 'Agotados',
          cuenta: resumen.agotados,
          color: AppColors.error,
          activa: estadoSeleccionado == EstadoStock.agotado,
          onTap: () => setState(() => estadoSeleccionado =
              estadoSeleccionado == EstadoStock.agotado
                  ? null
                  : EstadoStock.agotado),
        ),
      ],
    );
  }

  Widget _pastilla({
    required String etiqueta,
    required int cuenta,
    required Color color,
    required bool activa,
    required VoidCallback onTap,
  }) {
    // Activa: relleno solido con la tinta que le toque encima. Inactiva: el
    // color al 10%, que deja leer la cuenta sin gritar.
    final tinta = activa ? AppColors.tintaSobre(color) : color;
    return Material(
      color: activa ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(etiqueta,
                style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: tinta)),
            const SizedBox(width: 6),
            Text('$cuenta',
                style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: tinta.withValues(alpha: 0.62))),
          ]),
        ),
      ),
    );
  }

  /// Cuantos se ven de cuantos hay, y cuanto dinero esta parado en la bodega.
  ///
  /// El valor del inventario se calcula a COSTO, no a precio de venta: es el
  /// dinero que el negocio ya desembolso y todavia no recupera. A precio de
  /// venta saldria un numero mas grande y mas bonito que no corresponde a
  /// nada que exista.
  Widget _pieTabla() {
    final valor = productos.fold<double>(0, (a, p) {
      final costo = (p['precio_compra'] as num?)?.toDouble() ?? 0;
      final cantidad = (p['cantidad'] as num?)?.toDouble() ?? 0;
      return a + costo * cantidad;
    });

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        Text(
          filtrados.length == productos.length
              ? 'Mostrando ${productos.length}'
              : 'Mostrando ${filtrados.length} de ${productos.length}',
          style: const TextStyle(
              fontSize: AppText.caption, color: AppColors.textSecondary),
        ),
        const Spacer(),
        const Text('Valor del inventario, a costo  ',
            style: TextStyle(
                fontSize: AppText.caption,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong)),
        Text(AppConfig.formatoMoneda(valor),
            style: const TextStyle(
                fontSize: AppText.body,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ]),
    );
  }

  /// Una sola fila: buscar, filtrar por existencia, filtrar por categoria.
  ///
  /// Antes el buscador y las categorias se repartian el ancho a la mitad
  /// (flex 4 / flex 5) y las categorias vivian en un ListView horizontal que
  /// se desplazaba a ciegas: con ocho categorias, la novena no existia para
  /// quien no supiera que ahi se podia arrastrar.
  Widget _filtros(ResumenStock resumen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => busqueda = v),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, clave o código…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _pastillasEstado(resumen),
        ]),
        if (categorias.isNotEmpty) ...[
          const SizedBox(height: 12),
          // Wrap y no un carrusel horizontal: las categorias caben, y las que
          // no caben bajan de renglon en vez de esconderse.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipCategoria('Todas', null),
              for (final c in categorias) _chipCategoria(c.nombre, c.idCategoria),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chipCategoria(String etiqueta, int? id) {
    final activa = categoriaSeleccionada == id;
    return ChoiceChip(
      label: Text(etiqueta),
      selected: activa,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: BorderSide(
        color: activa && AppColors.primaryNecesitaBorde
            ? AppColors.bordePrimario
            : AppColors.border,
      ),
      labelStyle: TextStyle(
        fontSize: AppText.small,
        fontWeight: FontWeight.w700,
        // La tinta se calcula del color de marca, no se escribe a mano: con
        // una marca oscura, el negro fijo de antes quedaba ilegible.
        color: activa ? AppColors.onPrimary : AppColors.textPrimary,
      ),
      onSelected: (_) => setState(() => categoriaSeleccionada = id),
    );
  }
}

class ResumenStock {
  final int agotados;
  final int bajos;
  final int ok;

  const ResumenStock({required this.agotados, required this.bajos, required this.ok});

  factory ResumenStock.desde(List<Map<String, dynamic>> productos, int stockMinimo) {
    int agotados = 0, bajos = 0, ok = 0;

    for (final p in productos) {
      switch (clasificarStock(p['cantidad'] as int, stockMinimo)) {
        case EstadoStock.agotado:
          agotados++;
        case EstadoStock.bajo:
          bajos++;
        case EstadoStock.disponible:
          ok++;
      }
    }

    return ResumenStock(agotados: agotados, bajos: bajos, ok: ok);
  }
}
