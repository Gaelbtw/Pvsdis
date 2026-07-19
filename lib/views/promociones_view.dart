import 'package:flutter/material.dart';

import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/descuento_utils.dart';
import '../controllers/categoria_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/promociones_controller.dart';
import '../models/categoria_model.dart';
import '../models/producto_model.dart';
import '../models/promocion_model.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';

String _etiquetaTipo(TipoPromocion tipo) {
  switch (tipo) {
    case TipoPromocion.porcentajeProducto:
      return 'Descuento % por producto';
    case TipoPromocion.montoFijoProducto:
      return 'Descuento fijo por producto';
    case TipoPromocion.nxy:
      return 'Compra X y paga Y';
    case TipoPromocion.descuentoCantidad:
      return 'Descuento por cantidad';
    case TipoPromocion.combo:
      return 'Combo con precio especial';
  }
}

String _formatoFecha(DateTime? fecha) {
  if (fecha == null) return 'Sin límite';
  return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

class PromocionesView extends StatefulWidget {
  const PromocionesView({super.key});

  @override
  State<PromocionesView> createState() => _PromocionesViewState();
}

class _PromocionesViewState extends State<PromocionesView> {
  final controller = PromocionesController();
  final productoController = ProductoController();
  final categoriaController = CategoriaController();

  final nombreCtrl = TextEditingController();
  final prioridadCtrl = TextEditingController();
  final valorCtrl = TextEditingController();
  final cantidadMinimaCtrl = TextEditingController();
  final nxLlevaCtrl = TextEditingController();
  final nxPagaCtrl = TextEditingController();
  final precioComboCtrl = TextEditingController();
  final comboCantidadCtrl = TextEditingController();

  List<Promocion> promociones = [];
  List<Promocion> filtradas = [];
  List<Producto> productos = [];
  List<Categoria> categorias = [];

  bool get esCajero => SessionManager.currentUserRole == "Cajero";

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    final p = await controller.obtenerTodas();
    final prod = await productoController.obtenerTodos();
    final cat = await categoriaController.obtenerTodos();

    if (!mounted) return;
    setState(() {
      promociones = p;
      filtradas = p;
      productos = prod;
      categorias = cat;
    });
  }

  void buscar(String query) {
    if (query.isEmpty) {
      setState(() => filtradas = promociones);
      return;
    }
    final consulta = query.toLowerCase();
    setState(() {
      filtradas = promociones.where((p) => p.nombre.toLowerCase().contains(consulta)).toList();
    });
  }

  String _nombreProducto(int id) =>
      productos.firstWhere((p) => p.idProducto == id, orElse: () => Producto(nombre: '#$id', descripcion: '', precio: 0)).nombre;

  void mostrarFormulario({Promocion? promocion}) {
    var tipo = promocion?.tipo ?? TipoPromocion.porcentajeProducto;
    var activo = promocion?.activo ?? true;
    var combinable = promocion?.combinable ?? false;
    var fechaInicio = promocion?.fechaInicio;
    var fechaFin = promocion?.fechaFin;
    var tipoValorCantidad = promocion?.tipoValor ?? TipoDescuento.porcentaje;
    final productosSel = <int>{...promocion?.productosIds ?? const []};
    final categoriasSel = <int>{...promocion?.categoriasIds ?? const []};
    final comboItems = <ComboItem>[...promocion?.comboItems ?? const []];
    int? comboProductoSeleccionado;

    nombreCtrl.text = promocion?.nombre ?? '';
    prioridadCtrl.text = (promocion?.prioridad ?? 0).toString();
    valorCtrl.text = promocion?.valor?.toString() ?? '';
    cantidadMinimaCtrl.text = promocion?.cantidadMinima?.toString() ?? '';
    nxLlevaCtrl.text = promocion?.nxLleva?.toString() ?? '';
    nxPagaCtrl.text = promocion?.nxPaga?.toString() ?? '';
    precioComboCtrl.text = promocion?.precioCombo?.toString() ?? '';
    comboCantidadCtrl.text = '1';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> elegirFecha({required bool esInicio}) async {
            final elegida = await showDatePicker(
              context: context,
              initialDate: (esInicio ? fechaInicio : fechaFin) ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (elegida == null) return;
            setStateDialog(() {
              if (esInicio) {
                fechaInicio = elegida;
              } else {
                fechaFin = elegida;
              }
            });
          }

          Widget campoFecha(String etiqueta, DateTime? fecha, bool esInicio) {
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => elegirFecha(esInicio: esInicio),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text('$etiqueta: ${_formatoFecha(fecha)}'),
                    if (fecha != null) ...[
                      const Spacer(),
                      InkWell(
                        onTap: () => setStateDialog(() {
                          if (esInicio) {
                            fechaInicio = null;
                          } else {
                            fechaFin = null;
                          }
                        }),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          Widget dropdownContainer(Widget child) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: child,
              );

          Widget selectorParticipantes() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Productos participantes', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: productos.map((p) {
                    final seleccionado = productosSel.contains(p.idProducto);
                    return FilterChip(
                      label: Text(p.nombre),
                      selected: seleccionado,
                      onSelected: (v) => setStateDialog(() {
                        if (v) {
                          productosSel.add(p.idProducto!);
                        } else {
                          productosSel.remove(p.idProducto);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Categorías participantes', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categorias.map((c) {
                    final seleccionado = categoriasSel.contains(c.idCategoria);
                    return FilterChip(
                      label: Text(c.nombre),
                      selected: seleccionado,
                      onSelected: (v) => setStateDialog(() {
                        if (v) {
                          categoriasSel.add(c.idCategoria!);
                        } else {
                          categoriasSel.remove(c.idCategoria);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ],
            );
          }

          Widget seccionCombo() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: precioComboCtrl,
                  hint: "Precio especial del combo",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                const Text('Productos del combo', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: dropdownContainer(
                        DropdownButtonFormField<int>(
                          value: comboProductoSeleccionado,
                          decoration: const InputDecoration(border: InputBorder.none),
                          hint: const Text("Producto"),
                          items: productos
                              .map((p) => DropdownMenuItem(value: p.idProducto, child: Text(p.nombre)))
                              .toList(),
                          onChanged: (v) => setStateDialog(() => comboProductoSeleccionado = v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: AppTextField(
                        controller: comboCantidadCtrl,
                        hint: "Cant.",
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_circle, color: AppColors.primaryDark),
                      onPressed: () {
                        final idProducto = comboProductoSeleccionado;
                        final cantidad = int.tryParse(comboCantidadCtrl.text) ?? 0;
                        if (idProducto == null || cantidad <= 0) return;
                        setStateDialog(() {
                          comboItems.removeWhere((i) => i.idProducto == idProducto);
                          comboItems.add(ComboItem(idProducto: idProducto, cantidad: cantidad));
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...comboItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('${item.cantidad} x ${_nombreProducto(item.idProducto)}')),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: () => setStateDialog(() => comboItems.remove(item)),
                          ),
                        ],
                      ),
                    )),
              ],
            );
          }

          return FormDialog(
            titulo: promocion == null ? "Nueva Promoción" : "Editar Promoción",
            subtitulo: "Configure el tipo, vigencia y participantes de la promoción",
            campos: [
              AppTextField(controller: nombreCtrl, hint: "Nombre"),
              dropdownContainer(
                DropdownButtonFormField<TipoPromocion>(
                  value: tipo,
                  decoration: const InputDecoration(border: InputBorder.none),
                  items: TipoPromocion.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(_etiquetaTipo(t))))
                      .toList(),
                  onChanged: (v) => setStateDialog(() => tipo = v!),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: prioridadCtrl,
                      hint: "Prioridad (mayor = primero)",
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: campoFecha('Inicio', fechaInicio, true)),
                  const SizedBox(width: 12),
                  Expanded(child: campoFecha('Fin', fechaFin, false)),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Combinable con otras promociones'),
                value: combinable,
                onChanged: (v) => setStateDialog(() => combinable = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: activo,
                onChanged: (v) => setStateDialog(() => activo = v),
              ),
              if (tipo == TipoPromocion.porcentajeProducto) ...[
                AppTextField(
                  controller: valorCtrl,
                  hint: "Porcentaje de descuento (0-100)",
                  keyboardType: TextInputType.number,
                ),
                selectorParticipantes(),
              ],
              if (tipo == TipoPromocion.montoFijoProducto) ...[
                AppTextField(
                  controller: valorCtrl,
                  hint: "Monto fijo de descuento",
                  keyboardType: TextInputType.number,
                ),
                selectorParticipantes(),
              ],
              if (tipo == TipoPromocion.nxy) ...[
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: nxLlevaCtrl,
                        hint: "Lleva (X)",
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(
                        controller: nxPagaCtrl,
                        hint: "Paga (Y)",
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                selectorParticipantes(),
              ],
              if (tipo == TipoPromocion.descuentoCantidad) ...[
                AppTextField(
                  controller: cantidadMinimaCtrl,
                  hint: "Cantidad mínima (el excedente recibe el descuento)",
                  keyboardType: TextInputType.number,
                ),
                dropdownContainer(
                  DropdownButtonFormField<TipoDescuento>(
                    value: tipoValorCantidad,
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: const [
                      DropdownMenuItem(value: TipoDescuento.porcentaje, child: Text("Porcentaje")),
                      DropdownMenuItem(value: TipoDescuento.fijo, child: Text("Monto fijo")),
                    ],
                    onChanged: (v) => setStateDialog(() => tipoValorCantidad = v!),
                  ),
                ),
                AppTextField(
                  controller: valorCtrl,
                  hint: "Valor del descuento",
                  keyboardType: TextInputType.number,
                ),
                selectorParticipantes(),
              ],
              if (tipo == TipoPromocion.combo) seccionCombo(),
            ],
            onGuardar: () async {
              final nueva = Promocion(
                idPromocion: promocion?.idPromocion,
                nombre: nombreCtrl.text.trim(),
                tipo: tipo,
                activo: activo,
                fechaInicio: fechaInicio,
                fechaFin: fechaFin,
                prioridad: int.tryParse(prioridadCtrl.text) ?? 0,
                combinable: combinable,
                valor: double.tryParse(valorCtrl.text),
                tipoValor: tipo == TipoPromocion.descuentoCantidad ? tipoValorCantidad : null,
                cantidadMinima: int.tryParse(cantidadMinimaCtrl.text),
                nxLleva: int.tryParse(nxLlevaCtrl.text),
                nxPaga: int.tryParse(nxPagaCtrl.text),
                precioCombo: double.tryParse(precioComboCtrl.text),
                productosIds: productosSel.toList(),
                categoriasIds: categoriasSel.toList(),
                comboItems: comboItems,
              );

              try {
                if (promocion == null) {
                  await controller.crear(nueva);
                } else {
                  await controller.actualizar(nueva);
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
                  titulo: promocion == null ? "Promoción creada" : "Promoción actualizada",
                  mensaje: promocion == null
                      ? "La promoción ha sido creada exitosamente."
                      : "La promoción ha sido actualizada exitosamente.",
                  icono: Icons.check_circle_outline,
                  textoConfirmar: "Aceptar",
                  onConfirm: () {},
                ),
              );
            },
          );
        },
      ),
    );
  }

  void eliminar(int id) async {
    await controller.eliminar(id);
    cargar();
  }

  void cambiarActivo(Promocion promocion) async {
    if (promocion.activo) {
      await controller.desactivar(promocion.idPromocion!);
    } else {
      await controller.activar(promocion.idPromocion!);
    }
    cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: "Promociones", mostrarVolver: true),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
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
                        hintText: "Buscar promoción...",
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                      label: const Text("Nueva promoción"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "Administre las promociones automáticas del punto de venta",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: filtradas.isEmpty
                    ? const Center(child: Text("No hay promociones registradas"))
                    : ListView.separated(
                        itemCount: filtradas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final p = filtradas[i];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.nombre,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: p.activo
                                                  ? Colors.green.withOpacity(0.12)
                                                  : Colors.grey.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(30),
                                            ),
                                            child: Text(
                                              p.activo ? "Activa" : "Inactiva",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: p.activo ? Colors.green.shade800 : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "${_etiquetaTipo(p.tipo)} · Prioridad ${p.prioridad}"
                                        "${p.combinable ? ' · Combinable' : ''}",
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Vigencia: ${_formatoFecha(p.fechaInicio)} — ${_formatoFecha(p.fechaFin)}",
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!esCajero)
                                  PopupMenuButton(
                                    color: Colors.white,
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        onTap: () => mostrarFormulario(promocion: p),
                                        child: const Text("Editar"),
                                      ),
                                      PopupMenuItem(
                                        onTap: () => cambiarActivo(p),
                                        child: Text(p.activo ? "Desactivar" : "Activar"),
                                      ),
                                      PopupMenuItem(
                                        onTap: () {
                                          Future.delayed(Duration.zero, () {
                                            confirmarAccion(
                                              context: context,
                                              tituloConfirmar: "Eliminar promoción",
                                              mensajeConfirmar:
                                                  "¿Seguro que deseas eliminar esta promoción? Las ventas ya registradas no se verán afectadas.",
                                              iconoConfirmar: Icons.warning_amber_rounded,
                                              textoConfirmar: "Eliminar",
                                              accion: () async => eliminar(p.idPromocion!),
                                              tituloExito: "Promoción eliminada",
                                              mensajeExito: "La promoción ha sido eliminada exitosamente.",
                                            );
                                          });
                                        },
                                        child: const Text("Eliminar"),
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

  @override
  void dispose() {
    nombreCtrl.dispose();
    prioridadCtrl.dispose();
    valorCtrl.dispose();
    cantidadMinimaCtrl.dispose();
    nxLlevaCtrl.dispose();
    nxPagaCtrl.dispose();
    precioComboCtrl.dispose();
    comboCantidadCtrl.dispose();
    super.dispose();
  }
}
