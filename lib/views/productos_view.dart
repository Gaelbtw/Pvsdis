import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../controllers/producto_controller.dart';
import '../controllers/categoria_controller.dart';
import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../widgets/nav_bar.dart';
import '../core/session/session_manager.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import 'categoria_view.dart';

class ProductosView extends StatefulWidget {
  const ProductosView({super.key});

  @override
  State<ProductosView> createState() => _ProductosViewState();
}

class _ProductosViewState extends State<ProductosView> {
  final controller = ProductoController();
  final categoriaController = CategoriaController();

  final nombreCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final precioCtrl = TextEditingController();
  final precioCompraCtrl = TextEditingController();
  final codigoBarrasCtrl = TextEditingController();

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

    final consulta = query.toLowerCase();
    final resultado = productos.where((p) {
      return p.nombre.toLowerCase().contains(consulta) ||
          (p.codigoBarras?.toLowerCase().contains(consulta) ?? false);
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
      codigoBarrasCtrl.text = producto.codigoBarras ?? "";
    } else {
      nombreCtrl.clear();
      descCtrl.clear();
      precioCtrl.clear();
      precioCompraCtrl.clear();
      stockCtrl.clear();
      codigoBarrasCtrl.clear();
      categoriaSeleccionada = null;
    }

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: producto == null ? "Nuevo Producto" : "Editar Producto",
        subtitulo: "Complete la información del producto",
        campos: [
          AppTextField(controller: nombreCtrl, hint: "Nombre"),
          AppTextField(controller: descCtrl, hint: "Descripción", maxLines: 3),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: precioCtrl,
                  hint: "Precio",
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppTextField(
                  controller: precioCompraCtrl,
                  hint: "Precio compra",
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
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
          AppTextField(
            controller: stockCtrl,
            hint: "Stock mínimo",
            keyboardType: TextInputType.number,
          ),
          AppTextField(
            controller: codigoBarrasCtrl,
            hint: "Código de barras (opcional)",
            icon: Icons.qr_code_scanner,
          ),
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
        ],
        onGuardar: () async {
          double precio = double.tryParse(precioCtrl.text) ?? 0;
          int stock = int.tryParse(stockCtrl.text) ?? 0;
          final codigoBarras = Producto.normalizarCodigoBarras(codigoBarrasCtrl.text);

          if (codigoBarras != null) {
            final duplicado = await controller.existeCodigoBarras(
              codigoBarras,
              excluirId: producto?.idProducto,
            );

            if (duplicado) {
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => const CustomAlert(
                  titulo: "Código duplicado",
                  mensaje: "Ya existe otro producto con ese código de barras.",
                  icono: Icons.error_outline,
                  textoConfirmar: "Aceptar",
                ),
              );
              return;
            }
          }

          final nuevo = Producto(
            idProducto: producto?.idProducto,
            nombre: nombreCtrl.text,
            descripcion: descCtrl.text,
            precio: precio,
            precioCompra: double.tryParse(precioCompraCtrl.text) ?? 0,
            categoriaId: categoriaSeleccionada,
            estado: estado,
            stockMinimo: stock,
            codigoBarras: codigoBarras,
          );

          try {
            if (producto == null) {
              await controller.insertar(nuevo, stock);
            } else {
              await controller.actualizar(nuevo);
              // El stock actual se gestiona desde la vista de Inventario
            }
          } catch (e) {
            if (!context.mounted) return;
            showDialog(
              context: context,
              builder: (_) => CustomAlert(
                titulo: "No se pudo guardar",
                mensaje: e.toString().replaceFirst("Exception: ", ""),
                icono: Icons.error_outline,
                textoConfirmar: "Aceptar",
              ),
            );
            return;
          }

          if (!context.mounted) return;
          Navigator.pop(context);
          cargar();

          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: producto == null ? "Producto agregado" : "Producto actualizado",
              mensaje: producto == null
                  ? "El producto ha sido agregado exitosamente."
                  : "El producto ha sido actualizado exitosamente.",
              icono: Icons.check_circle_outline,
              textoConfirmar: "Aceptar",
              onConfirm: () {},
            ),
          );
        },
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
      backgroundColor: AppColors.background,

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
                        fillColor: AppColors.surface,

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
                        backgroundColor: AppColors.primary,

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

                        side: const BorderSide(color: AppColors.border),

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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                        color: AppColors.surfaceAlt,

                        borderRadius: BorderRadius.circular(24),

                        border: Border.all(color: AppColors.border),
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
                                    color: AppColors.textPrimary,
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
                                          confirmarAccion(
                                            context: context,
                                            tituloConfirmar: "Eliminar producto",
                                            mensajeConfirmar:
                                                "¿Seguro que deseas eliminar este producto?",
                                            iconoConfirmar: Icons.warning_amber_rounded,
                                            textoConfirmar: "Eliminar",
                                            accion: () async {
                                              eliminar(p.idProducto!);
                                            },
                                            tituloExito: "Producto eliminado",
                                            mensajeExito:
                                                "El producto ha sido eliminado exitosamente.",
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
                              color: AppColors.textSecondary,
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
                                  color: AppColors.primaryLighter,

                                  borderRadius: BorderRadius.circular(30),
                                ),

                                child: Text(
                                  p.categoriaNombre ?? "Sin categoría",

                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: AppColors.primaryDarker,
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
