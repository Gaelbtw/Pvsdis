import 'package:flutter/material.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/descuento_utils.dart';
import '../core/utils/escaneo_utils.dart';
import '../controllers/ventas_controller.dart';
import '../controllers/producto_controller.dart';
import '../models/carrito_venta.dart';
import '../models/producto_model.dart';
import '../widgets/custom_alert.dart';
import '../widgets/ventas/autorizacion_descuento_dialog.dart';
import '../widgets/ventas/descuento_dialog.dart';
import '../models/cliente_model.dart';
import '../widgets/nav_bar.dart';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../services/ticket_service.dart';

class VentasView extends StatefulWidget {
  final Cliente? cliente;

  const VentasView({
    super.key,
    this.cliente,
  });

  @override
  State<VentasView> createState() => _VentasViewState();
}

class _VentasViewState extends State<VentasView> {
  final ventasController = VentasController();
  final productoController = ProductoController();

  Cliente? clienteSeleccionado;

  List<Producto> productos = [];
  Map<int, int> stockProductos = {};
  final _carrito = CarritoVenta();
  List<Map<String, dynamic>> get carrito => _carrito.items;

  final Map<int, TextEditingController> controllers = {};

  final pagoCtrl = TextEditingController();
  final busquedaCtrl = TextEditingController();
  final busquedaFocus = FocusNode();

  String metodoPago = "efectivo";
  String busqueda = "";

  double cambio = 0;
  bool cargando = true;

  bool get esCajero => SessionManager.currentUserRole == "Cajero";

  bool get puedeAplicarDescuentos =>
      !esCajero || AppConfig.actual.descuentoCajeroPuedeAplicar;

  /// Única fuente de verdad del desglose financiero de la venta en curso
  /// (subtotal, descuentos, total). Se recalcula en cada build a partir del
  /// carrito y del descuento global — nunca se guarda un total aparte que
  /// se pueda desincronizar.
  VentaCalculada get calculo => calcularVenta(
        carrito: carrito,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        descuentoMaximoPorcentaje: AppConfig.actual.descuentoMaximoPorcentaje,
      );

  @override
  void initState() {
    super.initState();

    clienteSeleccionado = widget.cliente;

    cargarProductos();
  }

  // 🔥 CARGAR PRODUCTOS
  Future<void> cargarProductos() async {
    final data = await productoController.obtenerConStock();

    if (!mounted) return;

    final Map<int, int> stock = {};
    final List<Producto> lista = [];

    for (final row in data) {
      final p = Producto.fromMap(row);
      lista.add(p);
      if (p.idProducto != null) {
        stock[p.idProducto!] = (row['cantidad'] as int?) ?? 0;
      }
    }

    setState(() {
      productos = lista;
      stockProductos = stock;
      cargando = false;
    });
  }

  // 🔍 FILTRO
  List<Producto> get productosFiltrados {
    final consulta = busqueda.toLowerCase();
    return productos.where((p) {
      return p.nombre.toLowerCase().contains(consulta) ||
          (p.codigoBarras?.toLowerCase().contains(consulta) ?? false);
    }).toList();
  }

  // 🛒 AGREGAR PRODUCTO
  void agregarProducto(Producto p) {
    final yaExistia = _carrito.contieneProducto(p.idProducto);

    setState(() {
      _carrito.agregar(p);

      if (!yaExistia) {
        controllers[p.idProducto!] = TextEditingController(text: "1");
      }
    });
  }

  // 🔫 ESCANEO DE CÓDIGO DE BARRAS
  // Los lectores USB emulan un teclado: "escriben" el código y envían
  // Enter, por lo que basta con onSubmitted de un TextField normal (sin
  // listeners de teclado en bruto) para capturar el evento.
  void procesarEscaneo(String codigo) {
    if (codigo.trim().isEmpty) return;

    final resultado = resolverEscaneo(
      codigo: codigo,
      productos: productos,
      stockDisponible: stockProductos,
      cantidadEnCarrito: _carrito.cantidadEnCarrito,
    );

    switch (resultado.tipo) {
      case TipoResultadoEscaneo.agregado:
        agregarProducto(resultado.producto!);
        break;
      case TipoResultadoEscaneo.noEncontrado:
      case TipoResultadoEscaneo.inactivo:
      case TipoResultadoEscaneo.stockInsuficiente:
        showDialog(
          context: context,
          builder: (_) => CustomAlert(
            titulo: 'Escaneo',
            mensaje: resultado.mensaje,
            icono: Icons.error_outline,
          ),
        );
        break;
    }

    busquedaCtrl.clear();
    setState(() => busqueda = "");
    busquedaFocus.requestFocus();
  }

  // ➕➖ CAMBIAR CANTIDAD
  void cambiarCantidad(int index, int delta) {
    final id = carrito[index]['id_producto'];

    setState(() {
      final eliminado = _carrito.cambiarCantidad(index, delta);

      if (eliminado) {
        controllers[id]?.dispose();
        controllers.remove(id);
      } else if (controllers.containsKey(id)) {
        controllers[id]!.text = carrito[index]['cantidad'].toString();
      }
    });
  }

  // 💰 TOTAL (ya con descuentos aplicados)
  double get total => calculo.total;

  // 💵 CAMBIO
  void calcularCambio() {
    final recibido = double.tryParse(pagoCtrl.text) ?? 0;

    setState(() {
      cambio = recibido - total;
    });
  }

  // 🏷 DESCUENTO POR PRODUCTO
  void editarDescuentoLinea(int index) {
    final item = carrito[index];
    final base = (item['precio'] as num) * (item['cantidad'] as int);
    final tipoActual = item['descuento_tipo'] as TipoDescuento?;
    final valorActual = (item['descuento_valor'] as num?)?.toDouble() ?? 0;

    mostrarDescuentoDialog(
      context,
      titulo: 'Descuento a "${item['nombre']}"',
      base: base.toDouble(),
      tipoActual: tipoActual,
      valorActual: valorActual,
      onAplicar: (tipo, valor) {
        setState(() => _carrito.aplicarDescuentoLinea(index, tipo, valor));
      },
      onQuitar: tipoActual != null
          ? () => setState(() => _carrito.quitarDescuentoLinea(index))
          : null,
    );
  }

  // 🏷 DESCUENTO GLOBAL
  void editarDescuentoGlobal() {
    if (carrito.isEmpty) return;

    // Base real del descuento global: el subtotal ya después de los
    // descuentos de línea (sin el propio descuento global todavía).
    final baseGlobal = calcularVenta(
      carrito: carrito,
      descuentoMaximoPorcentaje: AppConfig.actual.descuentoMaximoPorcentaje,
    ).total;

    mostrarDescuentoDialog(
      context,
      titulo: 'Descuento global de la venta',
      base: baseGlobal,
      tipoActual: _carrito.descuentoGlobalTipo,
      valorActual: _carrito.descuentoGlobalValor,
      onAplicar: (tipo, valor) {
        setState(() => _carrito.aplicarDescuentoGlobal(tipo, valor));
      },
      onQuitar: _carrito.descuentoGlobalTipo != null
          ? () => setState(() => _carrito.quitarDescuentoGlobal())
          : null,
    );
  }

  // 🧾 INICIAR CONFIRMACIÓN (pide motivo/autorización si el descuento lo amerita)
  void iniciarConfirmacionVenta() {
    if (carrito.isEmpty) return;

    if (calculo.descuentoTotal > 0 && !puedeAplicarDescuentos) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Descuento no permitido',
          mensaje: 'No tienes permiso para aplicar descuentos. Contacta a un administrador.',
          icono: Icons.block,
        ),
      );
      return;
    }

    if (calculo.requiereAutorizacion) {
      mostrarAutorizacionDescuentoDialog(
        context,
        requiereCredencialesAdmin: esCajero && AppConfig.actual.descuentoCajeroRequiereAutorizacion,
        onConfirmar: (motivo, autorizadoPor) {
          confirmarVenta(descuentoMotivo: motivo, descuentoAutorizadoPor: autorizadoPor);
        },
      );
      return;
    }

    confirmarVenta();
  }

  void confirmarVenta({String? descuentoMotivo, int? descuentoAutorizadoPor}) {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "VENTA",
        mensaje: "¿Deseas confirmar la venta?",
        icono: Icons.point_of_sale,
        textoCancelar: "Cancelar",
        textoConfirmar: "Confirmar",
        onConfirm: () {
          vender(descuentoMotivo: descuentoMotivo, descuentoAutorizadoPor: descuentoAutorizadoPor);
        },
      ),
    );
  }

  // 🧾 VENDER
  Future<void> vender({String? descuentoMotivo, int? descuentoAutorizadoPor}) async {
    if (carrito.isEmpty) return;

    if (metodoPago == "efectivo") {
      final recibido = double.tryParse(
            pagoCtrl.text,
          ) ??
          0;

      if (recibido < total) {
        showDialog(
          context: context,
          builder: (_) => const CustomAlert(
            titulo: 'VENTA',
            mensaje: 'Dinero insuficiente',
            icono: Icons.error,
          ),
        );

        return;
      }
    }

    try {
      final ventaCalculada = calculo;

      await ventasController.insertarVentaCompleta(
        carrito: carrito,
        metodoPago: metodoPago,
        idCliente: clienteSeleccionado?.idCliente,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        descuentoMotivo: descuentoMotivo,
        descuentoAutorizadoPor: descuentoAutorizadoPor,
      );

      await imprimirTicket(ventaCalculada);

      setState(() {
        _carrito.limpiar();

        pagoCtrl.clear();

        cambio = 0;

        for (var c in controllers.values) {
          c.dispose();
        }

        controllers.clear();
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'VENTA',
          mensaje: 'Venta realizada con éxito',
          icono: Icons.check_circle,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'No se pudo completar la venta',
          mensaje: mensaje,
          icono: Icons.inventory_2_outlined,
        ),
      );
      await cargarProductos();
    }
  }

  // 🖨 IMPRIMIR
  Future<void> imprimirTicket(VentaCalculada ventaCalculada) async {
    final carritoParaTicket = ventaCalculada.lineas
        .map((l) => {
              'nombre': l.nombre,
              'precio': l.precioOriginal,
              'cantidad': l.cantidad,
              'descuento_monto': l.descuentoMonto,
            })
        .toList();

    final pdf = await TicketService.generarTicket(
      carrito: carritoParaTicket,
      total: ventaCalculada.total,
      subtotal: ventaCalculada.subtotal,
      descuento: ventaCalculada.descuentoTotal,
      metodoPago: metodoPago,
      recibido: double.tryParse(
            pagoCtrl.text,
          ) ??
          0,
      cambio: cambio,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),

      appBar: CustomHeader(
        titulo: clienteSeleccionado != null
            ? "Venta - ${clienteSeleccionado!.nombre}"
            : "Punto de Venta",
        mostrarVolver: true,
      ),

      body: cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                24,
                20,
                24,
                24,
              ),
              child: Row(
                children: [

                  // 🔥 PRODUCTOS
                  Expanded(
                    flex: 7,
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
                        children: [

                          // 🔍 BUSCADOR / ESCÁNER
                          TextField(
                            controller: busquedaCtrl,
                            focusNode: busquedaFocus,
                            autofocus: true,
                            onChanged: (v) {
                              setState(() {
                                busqueda = v;
                              });
                            },
                            onSubmitted: procesarEscaneo,
                            decoration: InputDecoration(
                              hintText: "Buscar o escanear código...",
                              prefixIcon: const Icon(
                                Icons.search,
                              ),
                              filled: true,
                              fillColor:
                                  AppColors.surface,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 📦 GRID
                          Expanded(
                            child: GridView.builder(
                              itemCount:
                                  productosFiltrados.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 1.15,
                              ),
                              itemBuilder: (_, i) {
                                final p =
                                    productosFiltrados[i];

                                return InkWell(
                                  borderRadius:
                                      BorderRadius.circular(
                                    18,
                                  ),
                                  onTap: () =>
                                      agregarProducto(p),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.all(
                                      16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFFDFDFD,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(
                                        18,
                                      ),
                                      border: Border.all(
                                        color: Colors.grey
                                            .shade200,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment
                                              .start,
                                      children: [

                                        // 🏷 NOMBRE
                                        Text(
                                          p.nombre,
                                          maxLines: 2,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                          style:
                                              const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        // 📦 STOCK
                                        Builder(builder: (_) {
                                          final s = stockProductos[p.idProducto] ?? 0;
                                          return Text(
                                            "Stock: $s",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: s == 0
                                                  ? Colors.red
                                                  : s <= p.stockMinimo
                                                      ? Colors.orange
                                                      : Colors.green.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          );
                                        }),

                                        const Spacer(),

                                        // 💰 PRECIO
                                        Text(
                                          "\$${p.precio.toStringAsFixed(2)}",
                                          style:
                                              const TextStyle(
                                            fontSize: 18,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                          ),
                                        ),

                                        const SizedBox(
                                            height: 12),

                                        // ➕ BOTÓN
                                        SizedBox(
                                          width:
                                              double.infinity,
                                          height: 42,
                                          child:
                                              ElevatedButton
                                                  .icon(
                                            onPressed: () =>
                                                agregarProducto(
                                              p,
                                            ),
                                            icon: const Icon(
                                              Icons.add,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              "Agregar",
                                            ),
                                            style:
                                                ElevatedButton
                                                    .styleFrom(
                                              backgroundColor:
                                                  const Color(
                                                0xFFF2C500,
                                              ),
                                              foregroundColor:
                                                  Colors
                                                      .black,
                                              elevation: 0,
                                              shape:
                                                  RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  // 🛒 CARRITO
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [

                          // 🧾 HEADER
                          Row(
                            children: [
                              const Icon(
                                Icons.shopping_cart,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "Detalle de Venta",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          if (clienteSeleccionado !=
                              null) ...[
                            const SizedBox(height: 10),

                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF8F6F2,
                                ),
                                borderRadius:
                                    BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      clienteSeleccionado!
                                          .nombre,
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // 🛒 ITEMS
                          Expanded(
                            child: carrito.isEmpty
                                ? const Center(
                                    child: Text(
                                      "No hay productos",
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount:
                                        carrito.length,
                                    separatorBuilder:
                                        (_, __) =>
                                            const SizedBox(
                                      height: 10,
                                    ),
                                    itemBuilder: (_, i) {
                                      final item =
                                          carrito[i];

                                      final id = item[
                                          'id_producto'];

                                      controllers[id]!
                                              .text =
                                          item['cantidad']
                                              .toString();

                                      return Container(
                                        padding:
                                            const EdgeInsets
                                                .all(12),
                                        decoration:
                                            BoxDecoration(
                                          color:
                                              const Color(
                                            0xFFF8F6F2,
                                          ),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(
                                            16,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [

                                            // 🏷 NOMBRE + DESCUENTO
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item['nombre'],
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (puedeAplicarDescuentos)
                                                  InkWell(
                                                    onTap: () => editarDescuentoLinea(i),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(4),
                                                      child: Icon(
                                                        Icons.sell_outlined,
                                                        size: 18,
                                                        color: item['descuento_tipo'] != null
                                                            ? AppColors.primaryDark
                                                            : Colors.grey.shade400,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),

                                            const SizedBox(
                                                height: 6),

                                            Text(
                                              item['descuento_tipo'] != null
                                                  ? "\$${item['precio']}  ·  descuento aplicado"
                                                  : "\$${item['precio']}",
                                              style: TextStyle(
                                                color: item['descuento_tipo'] != null
                                                    ? AppColors.primaryDark
                                                    : null,
                                              ),
                                            ),

                                            const SizedBox(
                                                height: 10),

                                            Row(
                                              children: [

                                                // ➖
                                                IconButton(
                                                  onPressed:
                                                      () =>
                                                          cambiarCantidad(
                                                    i,
                                                    -1,
                                                  ),
                                                  icon:
                                                      const Icon(
                                                    Icons
                                                        .remove_circle_outline,
                                                  ),
                                                ),

                                                // 🔢 INPUT
                                                SizedBox(
                                                  width: 60,
                                                  child:
                                                      TextField(
                                                    controller:
                                                        controllers[
                                                            id],
                                                    keyboardType:
                                                        TextInputType.number,
                                                    textAlign:
                                                        TextAlign.center,
                                                    decoration:
                                                        InputDecoration(
                                                      isDense:
                                                          true,
                                                      filled:
                                                          true,
                                                      fillColor:
                                                          Colors.white,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                        vertical:
                                                            10,
                                                      ),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                          10,
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged:
                                                        (
                                                      value,
                                                    ) {
                                                      final nuevaCantidad =
                                                          int.tryParse(
                                                        value,
                                                      );

                                                      if (nuevaCantidad !=
                                                              null &&
                                                          nuevaCantidad >
                                                              0) {
                                                        setState(
                                                          () {
                                                            item['cantidad'] =
                                                                nuevaCantidad;
                                                          },
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),

                                                // ➕
                                                IconButton(
                                                  onPressed:
                                                      () =>
                                                          cambiarCantidad(
                                                    i,
                                                    1,
                                                  ),
                                                  icon:
                                                      const Icon(
                                                    Icons
                                                        .add_circle_outline,
                                                  ),
                                                ),

                                                const Spacer(),

                                                // 💰 SUBTOTAL (con su descuento de línea, sin el global)
                                                Builder(builder: (_) {
                                                  final lineaCalculada = calculo.lineas[i];
                                                  final montoLinea = lineaCalculada.subtotalLinea -
                                                      lineaCalculada.descuentoMonto;
                                                  return Text(
                                                    "\$${montoLinea.toStringAsFixed(2)}",
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          const Divider(height: 30),

                          // 🏷 DESCUENTO GLOBAL
                          if (puedeAplicarDescuentos)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: carrito.isEmpty ? null : editarDescuentoGlobal,
                                  icon: const Icon(Icons.sell_outlined, size: 18),
                                  label: Text(
                                    _carrito.descuentoGlobalTipo != null
                                        ? "Editar descuento global"
                                        : "Aplicar descuento global",
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryDark,
                                    side: BorderSide(color: AppColors.primaryDark),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 💰 SUBTOTAL / DESCUENTO / TOTAL
                          Builder(builder: (_) {
                            final c = calculo;
                            return Column(
                              children: [
                                if (c.descuentoTotal > 0) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Subtotal", style: TextStyle(color: Colors.grey.shade700)),
                                      Text("\$${c.subtotal.toStringAsFixed(2)}"),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("Descuento", style: TextStyle(color: Colors.grey.shade700)),
                                      Text(
                                        "-\$${c.descuentoTotal.toStringAsFixed(2)}",
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "TOTAL",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      "\$${c.total.toStringAsFixed(2)}",
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),

                          const SizedBox(height: 20),

                          // 💳 MÉTODO
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      metodoPago =
                                          "efectivo";
                                    });
                                  },
                                  style:
                                      ElevatedButton
                                          .styleFrom(
                                    backgroundColor:
                                        metodoPago ==
                                                "efectivo"
                                            ? Colors.green
                                            : Colors.grey
                                                .shade200,
                                    foregroundColor:
                                        metodoPago ==
                                                "efectivo"
                                            ? Colors.white
                                            : Colors.black,
                                    elevation: 0,
                                    shape:
                                        RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        14,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    "Efectivo",
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      metodoPago =
                                          "tarjeta";
                                    });
                                  },
                                  style:
                                      ElevatedButton
                                          .styleFrom(
                                    backgroundColor:
                                        metodoPago ==
                                                "tarjeta"
                                            ? Colors.blue
                                            : Colors.grey
                                                .shade200,
                                    foregroundColor:
                                        metodoPago ==
                                                "tarjeta"
                                            ? Colors.white
                                            : Colors.black,
                                    elevation: 0,
                                    shape:
                                        RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius
                                              .circular(
                                        14,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    "Tarjeta",
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // 💵 EFECTIVO
                          if (metodoPago ==
                              "efectivo") ...[
                            const SizedBox(height: 16),

                            TextField(
                              controller: pagoCtrl,
                              keyboardType:
                                  TextInputType.number,
                              onChanged: (_) =>
                                  calcularCambio(),
                              decoration: InputDecoration(
                                labelText:
                                    "Monto recibido",
                                prefixIcon: const Icon(
                                  Icons.payments,
                                ),
                                filled: true,
                                fillColor:
                                    const Color(
                                  0xFFF8F6F2,
                                ),
                                border:
                                    OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(14),
                                  borderSide:
                                      BorderSide.none,
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cambio < 0
                                    ? Colors.red
                                        .withOpacity(0.1)
                                    : Colors.green
                                        .withOpacity(0.1),
                                borderRadius:
                                    BorderRadius
                                        .circular(14),
                              ),
                              child: Text(
                                "Cambio: \$${cambio.toStringAsFixed(2)}",
                                textAlign:
                                    TextAlign.center,
                                style: TextStyle(
                                  fontWeight:
                                      FontWeight.bold,
                                  color: cambio < 0
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),

                          //  BOTÓN
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: iniciarConfirmacionVenta,
                              icon: const Icon(
                                Icons.check_circle,
                              ),
                              label: const Text(
                                "Confirmar Venta",
                              ),
                              style:
                                  ElevatedButton
                                      .styleFrom(
                                backgroundColor:
                                    const Color(
                                  0xFFF2C500,
                                ),
                                foregroundColor:
                                    Colors.black,
                                elevation: 0,
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius
                                          .circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    pagoCtrl.dispose();
    busquedaCtrl.dispose();
    busquedaFocus.dispose();

    for (var c in controllers.values) {
      c.dispose();
    }

    super.dispose();
  }
}