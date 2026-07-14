import 'package:flutter/material.dart';
import '../controllers/producto_controller.dart';
import '../controllers/categoria_controller.dart';
import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../widgets/nav_bar.dart';
import '../core/session/session_manager.dart';
import '../widgets/custom_alert.dart';
import 'categoria_view.dart';

class ProductosView extends StatefulWidget {
  const ProductosView({super.key});

  @override
  State<ProductosView> createState() => _ProductosViewState();
}

class _ProductosViewState extends State<ProductosView> {
  final controller = ProductoService();
  final categoriaController = CategoriaController();

  final nombreCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final precioCtrl = TextEditingController();
  final precioCompraCtrl = TextEditingController();

  List<Producto> productos = [];
  List<Producto> filtrados = [];
  List<Categoria> categorias = [];

  int? categoriaSeleccionada;

  bool get esCajero => SessionManager.currentUserRole == "Cajero";

  @override
  void initState() {
    super.initState();
    cargar();
  }

  void cargar() async {
    final data = await controller.obtenerTodos();
    final cat = await categoriaController.obtenerTodos();

    setState(() {
      productos = data;
      filtrados = data;
      categorias = cat;
    });
  }

  void buscar(String query) {
    if (query.isEmpty) {
      setState(() => filtrados = productos);
      return;
    }

    final resultado = productos.where((p) {
      return p.nombre.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() => filtrados = resultado);
  }

  void mostrarFormulario({Producto? producto}) {
    final stockCtrl = TextEditingController();

    String estado = "Activo";

    if (producto != null) {
      nombreCtrl.text = producto.nombre;
      descCtrl.text = producto.descripcion;
      precioCtrl.text = producto.precio.toString();
      precioCompraCtrl.text = producto.precioCompra?.toString() ?? "";
      estado = producto.estado;
      categoriaSeleccionada = producto.categoriaId;
      stockCtrl.text = producto.stockMinimo.toString();
    } else {
      nombreCtrl.clear();
      descCtrl.clear();
      precioCtrl.clear();
      precioCompraCtrl.clear();
      stockCtrl.clear();
      categoriaSeleccionada = null;
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFFFAF8F4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto == null ? "Nuevo Producto" : "Editar Producto",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2D2B28),
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  "Complete la información del producto",
                  style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
                ),

                const SizedBox(height: 24),

                _input(nombreCtrl, "Nombre"),
                const SizedBox(height: 16),

                _input(descCtrl, "Descripción", maxLines: 3),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _input(
                        precioCtrl,
                        "Precio",
                        keyboard: TextInputType.number,
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: _input(
                        precioCompraCtrl,
                        "Precio compra",
                        keyboard: TextInputType.number,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButtonFormField<int>(
                    value: categoriaSeleccionada,
                    decoration: const InputDecoration(border: InputBorder.none),
                    hint: const Text("Seleccionar categoría"),
                    items: categorias.map((cat) {
                      return DropdownMenuItem(
                        value: cat.idCategoria,
                        child: Text(cat.nombre),
                      );
                    }).toList(),
                    onChanged: (v) {
                      categoriaSeleccionada = v;
                    },
                  ),
                ),

                const SizedBox(height: 16),

                _input(
                  stockCtrl,
                  "Stock mínimo",
                  keyboard: TextInputType.number,
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: estado,
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: ["Activo", "Inactivo"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      estado = v!;
                    },
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cancelar",
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),

                    const SizedBox(width: 12),

                    ElevatedButton(
                      onPressed: () async {
                      

                        double precio = double.tryParse(precioCtrl.text) ?? 0;

                        int stock = int.tryParse(stockCtrl.text) ?? 0;

                        final nuevo = Producto(
                          idProducto: producto?.idProducto,
                          nombre: nombreCtrl.text,
                          descripcion: descCtrl.text,
                          precio: precio,
                          precioCompra:
                              double.tryParse(precioCompraCtrl.text) ?? 0,
                          categoriaId: categoriaSeleccionada,
                          estado: estado,
                          stockMinimo: stock,
                        );

                        if (producto == null) {
                          await controller.insertar(nuevo, stock);
                        } else {
                          await controller.actualizar(nuevo);
                          // El stock actual se gestiona desde la vista de Inventario
                        }

                        Navigator.pop(context);
                        cargar();

                          showDialog (
                              context: context,
                              builder: (_) => CustomAlert(
                                titulo: producto == null ? "Producto agregado" : "Producto actualizado",
                                mensaje: producto == null
                                    ? "El producto ha sido agregado exitosamente."
                                    : "El producto ha sido actualizado exitosamente.",
                                icono: Icons.check_circle_outline,
                                textoConfirmar: "Aceptar",
                                onConfirm: () {
                                },
                              ),
                            );

                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2C500),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      
                      child: const Text(
                        "Guardar",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void eliminar(int id) async {
    await controller.eliminar(id);
    cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

      appBar: CustomHeader(titulo: "Productos", mostrarVolver: true),

      body: Padding(
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,

                children: [
                  SizedBox(
                    width: 320,

                    child: TextField(
                      onChanged: buscar,

                      decoration: InputDecoration(
                        hintText: "Buscar producto...",
                        prefixIcon: const Icon(Icons.search),

                        filled: true,
                        fillColor: const Color(0xFFF8F6F2),

                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  if (!esCajero)
                    ElevatedButton.icon(
                      onPressed: () => mostrarFormulario(),

                      icon: const Icon(Icons.add),

                      label: const Text("Nuevo producto"),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2C500),

                        foregroundColor: Colors.black87,

                        elevation: 0,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),

                  if (!esCajero)
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CategoriasView(),
                          ),
                        ).then((_) => cargar());
                      },

                      icon: const Icon(Icons.category_outlined),

                      label: const Text("Categorías"),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),

                        side: const BorderSide(color: Color(0xFFE5DED3)),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              const Text(
                "Administre los productos registrados dentro del sistema",
                style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: GridView.builder(
                  itemCount: filtrados.length,

                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: 1.7,
                  ),

                  itemBuilder: (_, i) {
                    final p = filtrados[i];

                    return Container(
                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: const Color(0xFFFCFBF9),

                        borderRadius: BorderRadius.circular(24),

                        border: Border.all(color: const Color(0xFFF0EBE5)),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.nombre,

                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                    color: Color(0xFF2D2B28),
                                  ),
                                ),
                              ),

                              if (!esCajero)
                                PopupMenuButton(
                                  color: Colors.white,

                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      onTap: () => mostrarFormulario(producto: p),
                                      child: const Text("Editar"),
                                    ),

                                    PopupMenuItem(
                                      onTap: () {
                                        Future.delayed(Duration.zero, () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => CustomAlert(
                                              titulo: "Eliminar producto",
                                              mensaje:
                                                  "¿Seguro que deseas eliminar este producto?",
                                              icono: Icons.warning_amber_rounded,
                                              textoConfirmar: "Eliminar",

                                              onConfirm: () async {
                                                eliminar(p.idProducto!);

                                                //Navigator.pop(context);

                                                showDialog(
                                                  context: context,
                                                  builder: (_) => CustomAlert(
                                                    titulo: "Producto eliminado",
                                                    mensaje:
                                                        "El producto ha sido eliminado exitosamente.",
                                                    icono: Icons.check_circle_outline,
                                                    textoConfirmar: "Aceptar",

                                                    onConfirm: () {
                                              
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                          );
                                        });
                                      },
                                      child: const Text("Eliminar"),
                                    ),
                                  ],
                                ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          Text(
                            p.descripcion,

                            maxLines: 2,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Color(0xFF6F6A63),
                              height: 1.5,
                            ),
                          ),

                          const Spacer(),

                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),

                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7D6),

                                  borderRadius: BorderRadius.circular(30),
                                ),

                                child: Text(
                                  p.categoriaNombre ?? "Sin categoría",

                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: Color(0xFFB27B00),
                                  ),
                                ),
                              ),

                              const Spacer(),

                              Text(
                                "\$${p.precio}",

                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2C2A27),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
