import 'package:flutter/material.dart';

import '../core/utils/mensaje_error.dart';
import '../widgets/estado_vista.dart';
import '../core/config/app_config.dart';
import '../core/licencia/guarda_licencia.dart';
import '../core/licencia/licencia_service.dart';
import '../core/theme/app_colors.dart';
import '../controllers/producto_controller.dart';
import '../controllers/categoria_controller.dart';
import '../models/producto_model.dart';
import '../models/categoria_model.dart';
import '../widgets/nav_bar.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/toast.dart';
import '../widgets/form_dialog.dart';
import '../widgets/inventario/captura_margen.dart';
import 'categoria_view.dart';
import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';

class ProductosView extends StatefulWidget {
  const ProductosView({super.key});

  @override
  State<ProductosView> createState() => _ProductosViewState();
}

class _ProductosViewState extends State<ProductosView> {
  /// Falso hasta que la primera carga termina. Sin esto la vista
  /// pintaba una lista vacía mientras consultaba, y en un equipo lento
  /// con catálogo grande eso se lee como "no hay nada" en vez de
  /// "todavía estoy cargando".
  bool _cargandoVista = true;

  /// Mensaje del último fallo al cargar, o `null`. Con esto la pantalla
  /// puede decir qué pasó y ofrecer reintentar, en vez de dejar la rueda
  /// girando para siempre.
  String? _errorCarga;

  final controller = ProductoController();
  final categoriaController = CategoriaController();

  final nombreCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final precioCtrl = TextEditingController();
  final precioCompraCtrl = TextEditingController();
  final codigoBarrasCtrl = TextEditingController();
  final skuCtrl = TextEditingController();
  final ivaCtrl = TextEditingController();

  List<Producto> productos = [];
  List<Producto> filtrados = [];
  List<Categoria> categorias = [];

  int? categoriaSeleccionada;

  /// Alta/edición/baja del catálogo. Antes era `rol == "Cajero"`, que
  /// ignoraba por completo la matriz de permisos y además le daba a un
  /// Supervisor los mismos accesos que a un Admin.
  bool get puedeGestionarProductos =>
      PermisosService.instancia.puedeActual(Permiso.gestionarProductos);

  @override
  void initState() {
    super.initState();
    cargar();
  }

  // `Future<void>` y no `void`: quien borra necesita esperar a que la
  // lista se refresque antes de anunciar el éxito.
  Future<void> cargar() async {
    if (mounted) setState(() => _errorCarga = null);
    try {
      final data = await controller.obtenerTodos();
      final cat = await categoriaController.obtenerTodos();

      if (!mounted) return;

      setState(() {
        productos = data;
        filtrados = data;
        categorias = cat;
        _cargandoVista = false;
      });
    } catch (e) {
      // Sin esto la bandera nunca se apagaba y la rueda giraba para
      // siempre: el error solo llegaba a la consola.
      if (!mounted) return;
      setState(() {
        _cargandoVista = false;
        _errorCarga = mensajeDeError(e);
      });
    }
  }

  void buscar(String query) {
    if (query.isEmpty) {
      setState(() => filtrados = productos);
      return;
    }

    final consulta = query.toLowerCase();
    final resultado = productos.where((p) {
      return p.nombre.toLowerCase().contains(consulta) ||
          (p.codigoBarras?.toLowerCase().contains(consulta) ?? false) ||
          (p.sku?.toLowerCase().contains(consulta) ?? false) ||
          (p.categoriaNombre?.toLowerCase().contains(consulta) ?? false);
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
      skuCtrl.text = producto.sku ?? "";
      ivaCtrl.text = producto.ivaTasa?.toString() ?? "";
    } else {
      nombreCtrl.clear();
      descCtrl.clear();
      precioCtrl.clear();
      precioCompraCtrl.clear();
      stockCtrl.clear();
      codigoBarrasCtrl.clear();
      skuCtrl.clear();
      ivaCtrl.clear();
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
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: DropdownButtonFormField<int>(
              initialValue: categoriaSeleccionada,
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
          CapturaMargen(
            precioCtrl: precioCtrl,
            precioCompraCtrl: precioCompraCtrl,
          ),
          AppTextField(
            controller: stockCtrl,
            hint: "Inventario mínimo",
            keyboardType: TextInputType.number,
          ),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: codigoBarrasCtrl,
                  hint: "Código de barras (opcional)",
                  icon: Icons.qr_code_scanner,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppTextField(
                  controller: skuCtrl,
                  hint: "Clave / SKU (opcional)",
                  icon: Icons.tag,
                ),
              ),
            ],
          ),
          AppTextField(
            controller: ivaCtrl,
            hint: "IVA % de este producto (vacío = tasa general)",
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            icon: Icons.percent,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: estado,
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
          final sku = Producto.normalizarSku(skuCtrl.text);

          if (codigoBarras != null) {
            final duplicado = await controller.existeCodigoBarras(
              codigoBarras,
              excluirId: producto?.idProducto,
            );

            if (duplicado) {
              if (!mounted) return;
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

          if (sku != null) {
            final duplicado = await controller.existeSku(
              sku,
              excluirId: producto?.idProducto,
            );

            if (duplicado) {
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (_) => const CustomAlert(
                  titulo: "Clave duplicada",
                  mensaje: "Ya existe otro producto con esa clave (SKU).",
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
            sku: sku,
            ivaTasa: Producto.normalizarIvaTasa(ivaCtrl.text),
          );

          try {
            if (producto == null) {
              await controller.insertar(nuevo, stock);
            } else {
              await controller.actualizar(nuevo);
              // El stock actual se gestiona desde la vista de Inventario
            }
          } catch (e) {
            if (!mounted) return;
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

          if (!mounted) return;
          Navigator.pop(context);
          cargar();

          Toast.exito(
            context,
            producto == null ? "Producto agregado" : "Producto actualizado",
          );
        },
      ),
    );
  }

  /// Devuelve un `Future` a propósito: `confirmarAccion` lo espera para saber
  /// si de verdad se borró. Cuando esto era `void ... async`, el `await` del
  /// helper regresaba de inmediato y el aviso de "eliminado exitosamente"
  /// salía ANTES de que la base respondiera -- incluso cuando la base
  /// rechazaba el borrado por tener registros asociados.
  Future<void> eliminar(int id) async {
    await controller.eliminar(id);
    await cargar();
  }

  @override
  void dispose() {
    nombreCtrl.dispose();
    descCtrl.dispose();
    precioCtrl.dispose();
    precioCompraCtrl.dispose();
    codigoBarrasCtrl.dispose();
    skuCtrl.dispose();
    ivaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Productos", mostrarVolver: true),

      body: (_cargandoVista || _errorCarga != null)
          ? EstadoVista(cargando: _cargandoVista, error: _errorCarga, onReintentar: cargar)
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
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  if (puedeGestionarProductos)
                    ElevatedButton.icon(
                      // Dar de alta productos se bloquea con la licencia
                      // vencida; editar y vender los que ya existen, no. El
                      // negocio sigue operando con su catálogo tal como está.
                      onPressed: () async {
                        if (!await GuardaLicencia.permite(
                          context,
                          FuncionLicenciada.altaProductos,
                        )) {
                          return;
                        }
                        if (!context.mounted) return;
                        mostrarFormulario();
                      },

                      icon: const Icon(Icons.add),

                      label: const Text("Nuevo producto"),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,

                        foregroundColor: AppColors.onPrimary,

                        elevation: 0,

                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),

                  if (puedeGestionarProductos)
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
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              const Text(
                "Administre los productos registrados dentro del sistema",
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: filtrados.isEmpty
                    ? PanelVacio(
                        icono: Icons.inventory_2_outlined,
                        // Sin catálogo o sin coincidencias son dos cosas
                        // distintas, y el mensaje tiene que decir cuál.
                        mensaje: productos.isEmpty
                            ? 'Todavía no hay productos'
                            : 'Ningún producto coincide',
                        detalle: productos.isEmpty
                            ? 'Da de alta el primero con el botón de arriba.'
                            : 'Revisa el nombre, el código de barras o el SKU.',
                      )
                    : GridView.builder(
                  itemCount: filtrados.length,

                  // Ancho máximo por tarjeta y ALTO FIJO, en vez de cuatro
                  // columnas con proporción fija. Con `crossAxisCount: 4` la
                  // celda se angostaba con la ventana y su alto bajaba con
                  // ella: a 940 px quedaban 197x116 para un contenido que
                  // necesita ~160 de alto, y la tarjeta salía rayada de
                  // amarillo y negro. El alto que hace falta no depende del
                  // ancho, así que se fija y las columnas se acomodan.
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    mainAxisExtent: 172,
                  ),

                  itemBuilder: (_, i) {
                    final p = filtrados[i];

                    return Container(
                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,

                        borderRadius: BorderRadius.circular(AppRadius.lg),

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

                                  // "Coca Cola 600ml Retornable Pack 12
                                  // piezas" se partía en tres renglones y
                                  // empujaba todo lo de abajo fuera de la
                                  // tarjeta.
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: AppText.bodyLg,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),

                              if (puedeGestionarProductos)
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
                                          if (!context.mounted) return;
                                          confirmarAccion(
                                            context: context,
                                            tituloConfirmar: "Eliminar producto",
                                            mensajeConfirmar:
                                                "¿Seguro que deseas eliminar este producto?",
                                            iconoConfirmar: Icons.warning_amber_rounded,
                                            textoConfirmar: "Eliminar",
                                            accion: () => eliminar(p.idProducto!),
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

                          if (p.sku != null)
                            Text(
                              "Clave: ${p.sku}",
                              style: const TextStyle(
                                fontSize: AppText.overline,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
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

                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),

                                child: Text(
                                  p.categoriaNombre ?? "Sin categoría",

                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: AppText.caption,
                                    color: AppColors.primaryDarker,
                                  ),
                                ),
                              ),

                              const Spacer(),

                              Text(
                                AppConfig.formatoMoneda(p.precio),

                                style: const TextStyle(
                                  fontSize: AppText.titleLg,
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
