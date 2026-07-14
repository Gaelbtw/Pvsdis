import 'package:flutter/material.dart';
import '../controllers/ventas_controller.dart';
import '../controllers/producto_controller.dart';
import '../models/producto_model.dart';
import '../widgets/custom_alert.dart';
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
  final productoController = ProductoService();

  Cliente? clienteSeleccionado;

  List<Producto> productos = [];
  Map<int, int> stockProductos = {};
  List<Map<String, dynamic>> carrito = [];

  final Map<int, TextEditingController> controllers = {};

  final pagoCtrl = TextEditingController();

  String metodoPago = "efectivo";
  String busqueda = "";

  double cambio = 0;
  bool cargando = true;

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
    return productos.where((p) {
      return p.nombre.toLowerCase().contains(
            busqueda.toLowerCase(),
          );
    }).toList();
  }

  // 🛒 AGREGAR PRODUCTO
  void agregarProducto(Producto p) {
    final index = carrito.indexWhere(
      (i) => i['id_producto'] == p.idProducto,
    );

    setState(() {
      if (index >= 0) {
        carrito[index]['cantidad']++;
      } else {
        carrito.add({
          "id_producto": p.idProducto,
          "nombre": p.nombre,
          "precio": p.precio,
          "cantidad": 1,
        });

        controllers[p.idProducto!] = TextEditingController(
          text: "1",
        );
      }
    });
  }

  // ➕➖ CAMBIAR CANTIDAD
  void cambiarCantidad(int index, int delta) {
    setState(() {
      carrito[index]['cantidad'] += delta;

      final id = carrito[index]['id_producto'];

      if (controllers.containsKey(id)) {
        controllers[id]!.text =
            carrito[index]['cantidad'].toString();
      }

      if (carrito[index]['cantidad'] <= 0) {
        controllers[id]?.dispose();
        controllers.remove(id);

        carrito.removeAt(index);
      }
    });
  }

  // 💰 TOTAL
  double get total {
    return carrito.fold(
      0,
      (sum, item) =>
          sum + (item['precio'] * item['cantidad']),
    );
  }

  // 💵 CAMBIO
  void calcularCambio() {
    final recibido = double.tryParse(pagoCtrl.text) ?? 0;

    setState(() {
      cambio = recibido - total;
    });
  }

  // 🧾 VENDER
  Future<void> vender() async {
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
      await ventasController.insertarVentaCompleta(
        carrito,
        total,
        metodoPago,
        idCliente: clienteSeleccionado?.idCliente,
      );

      await imprimirTicket();

      setState(() {
        carrito.clear();

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
          titulo: 'Stock Insuficiente',
          mensaje: mensaje,
          icono: Icons.inventory_2_outlined,
        ),
      );
      await cargarProductos();
    }
  }

  // 🖨 IMPRIMIR
  Future<void> imprimirTicket() async {
    final pdf = await TicketService.generarTicket(
      carrito: carrito,
      total: total,
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

                          // 🔍 BUSCADOR
                          TextField(
                            onChanged: (v) {
                              setState(() {
                                busqueda = v;
                              });
                            },
                            decoration: InputDecoration(
                              hintText: "Buscar producto...",
                              prefixIcon: const Icon(
                                Icons.search,
                              ),
                              filled: true,
                              fillColor:
                                  const Color(0xFFF8F6F2),
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

                                            // 🏷 NOMBRE
                                            Text(
                                              item['nombre'],
                                              style:
                                                  const TextStyle(
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                              ),
                                            ),

                                            const SizedBox(
                                                height: 6),

                                            Text(
                                              "\$${item['precio']}",
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

                                                // 💰 SUBTOTAL
                                                Text(
                                                  "\$${(item['precio'] * item['cantidad']).toStringAsFixed(2)}",
                                                  style:
                                                      const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
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

                          const Divider(height: 30),

                          // 💰 TOTAL
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment
                                    .spaceBetween,
                            children: [
                              const Text(
                                "TOTAL",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              Text(
                                "\$${total.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

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
                              onPressed: () {
                                if (carrito.isEmpty) {
                                  return;
                                }

                                showDialog(
                                  context: context,
                                  builder: (_) =>
                                      CustomAlert(
                                    titulo: "VENTA",
                                    mensaje:
                                        "¿Deseas confirmar la venta?",
                                    icono: Icons
                                        .point_of_sale,
                                    textoCancelar:
                                        "Cancelar",
                                    textoConfirmar:
                                        "Confirmar",
                                    onConfirm: () {
                                      vender();
                                    },
                                  ),
                                );
                              },
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

    for (var c in controllers.values) {
      c.dispose();
    }

    super.dispose();
  }
}