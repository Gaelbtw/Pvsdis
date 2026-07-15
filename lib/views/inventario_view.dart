import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../controllers/auditoria_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/categoria_controller.dart';
import '../core/session/session_manager.dart';
import '../core/utils/stock_status.dart';
import '../models/auditoria_model.dart';
import '../models/categoria_model.dart';
import '../widgets/confirm_action.dart';
import '../widgets/nav_bar.dart';
import '../widgets/stat_card.dart';
import '../widgets/historial_cambios_dialog.dart';
import '../widgets/inventario/editar_producto_dialog.dart';
import '../widgets/inventario/inventario_tabla.dart';
import '../services/configuracion_service.dart';
import '../models/configuracion_model.dart';

class InventarioView extends StatefulWidget {
  const InventarioView({super.key});

  @override
  State<InventarioView> createState() => _InventarioViewState();
}

class _InventarioViewState extends State<InventarioView> {
  final productoController = ProductoController();
  final categoriaController = CategoriaController();
  final auditoriaController = AuditoriaController();

  late Configuracion config;

  bool cargando = true;

  List<Map<String, dynamic>> productos = [];
  List<Categoria> categorias = [];
  List<Auditoria> cambios = [];

  int? categoriaSeleccionada;
  String busqueda = "";

  bool get esCajero => SessionManager.currentUserRole == "Cajero";

  @override
  void initState() {
    super.initState();
    inicializar();
  }

  Future<void> inicializar() async {
    config = await ConfiguracionService().obtener();

    await cargarTodo();

    if (!mounted) return;

    setState(() {
      cargando = false;
    });
  }

  Future<void> cargarTodo() async {
    final prod = await productoController.obtenerConStock();
    final cat = await categoriaController.obtenerTodos();
    final audit =
        await auditoriaController.obtenerPorTablas(['Productos', 'Inventario']);

    productos = prod;
    categorias = cat;
    cambios = audit;
  }

  List<Map<String, dynamic>> get filtrados {
    return productos.where((p) {
      final matchBusqueda =
          p['nombre'].toLowerCase().contains(busqueda.toLowerCase());

      final matchCategoria = categoriaSeleccionada == null ||
          p['id_categoria'] == categoriaSeleccionada;

      return matchBusqueda && matchCategoria;
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
        await productoController.eliminar(p['id_producto']);
        await inicializar();
      },
      tituloExito: "Producto eliminado",
      mensajeExito: "El producto ha sido eliminado exitosamente.",
    );
  }

  Future<void> mostrarCambiosInventario() async {
    await cargarTodo();
    if (!mounted) return;
    setState(() {});

    if (!mounted) return;
    await mostrarHistorialCambios(
      context,
      titulo: "Cambios de inventario",
      subtitulo: "Consulta quien creo, modifico o elimino productos y stock.",
      cambios: cambios,
    );
  }

  void mostrarEditarProducto(Map<String, dynamic> p) {
    mostrarEditarProductoDialog(
      context,
      producto: p,
      esCajero: esCajero,
      config: config,
      productoController: productoController,
      onGuardado: inicializar,
    );
  }

  Future<void> _agregarStockRapido(Map<String, dynamic> p, int cantidad) async {
    await productoController.agregarStock(p['id_producto'], cantidad);
    await inicializar();
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
          if (!esCajero)
            IconButton(
              tooltip: "Cambios de inventario",
              icon: const Icon(Icons.history, color: Colors.black87),
              onPressed: mostrarCambiosInventario,
            ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Administra productos, existencias y niveles de stock.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    _metricas(resumen),
                    const SizedBox(height: 24),
                    _filtros(),
                    const SizedBox(height: 24),
                    Expanded(
                      child: InventarioTabla(
                        productos: filtrados,
                        stockMinimo: config.stockMinimo,
                        esCajero: esCajero,
                        onAgregarStock: _agregarStockRapido,
                        onEditar: mostrarEditarProducto,
                        onEliminar: confirmarEliminar,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _metricas(ResumenStock resumen) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            title: "Productos",
            value: productos.length.toString(),
            icon: Icons.inventory_2,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            title: "Agotados",
            value: resumen.agotados.toString(),
            icon: Icons.error_outline,
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            title: "Stock Bajo",
            value: resumen.bajos.toString(),
            icon: Icons.warning_amber,
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            title: "Stock OK",
            value: resumen.ok.toString(),
            icon: Icons.check_circle,
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _filtros() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            onChanged: (v) => setState(() => busqueda = v),
            decoration: InputDecoration(
              hintText: "Buscar producto...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF8F6F2),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: const Text("Todos"),
                  selected: categoriaSeleccionada == null,
                  selectedColor: const Color(0xFFF2C500),
                  labelStyle: TextStyle(
                    color: categoriaSeleccionada == null ? Colors.black : Colors.black87,
                  ),
                  onSelected: (_) {
                    setState(() => categoriaSeleccionada = null);
                  },
                ),
                ...categorias.map((cat) {
                  final selected = categoriaSeleccionada == cat.idCategoria;

                  return Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: ChoiceChip(
                      label: Text(cat.nombre),
                      selected: selected,
                      selectedColor: const Color(0xFFF2C500),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.black87,
                      ),
                      onSelected: (_) {
                        setState(() => categoriaSeleccionada = cat.idCategoria);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        if (!esCajero)
          ElevatedButton.icon(
            onPressed: mostrarCambiosInventario,
            icon: const Icon(Icons.history, size: 18),
            label: const Text("Cambios"),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
      ],
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
