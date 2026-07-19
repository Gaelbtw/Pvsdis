import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/pagos_mixtos.dart';
import '../controllers/producto_controller.dart';
import '../controllers/proveedor_controller.dart';
import '../controllers/compras_controller.dart';
import '../models/carrito_compra.dart';
import '../models/producto_model.dart';
import '../models/proveedores_model.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../services/ticket_compras_service.dart';

class ComprasView extends StatefulWidget {
  const ComprasView({super.key});

  @override
  State<ComprasView> createState() => _ComprasViewState();
}

class _ComprasViewState extends State<ComprasView> {
  final productoController = ProductoController();
  final proveedorController = ProveedorController();
  final comprasController = ComprasController();

  List<Producto> productos = [];
  List<Proveedores> proveedores = [];

  final _carrito = CarritoCompra();
  List<Map<String, dynamic>> get carrito => _carrito.items;
  Map<int, TextEditingController> controllers = {};

  Proveedores? proveedorSeleccionado;

  String busqueda = "";
  bool cargando = true;

  // 💳 Forma de pago de la compra (de contado no es un caso especial: es
  // simplemente un pago inicial igual al total; a crédito puede llevar un
  // pago inicial parcial, o ninguno).
  String formaPago = 'Contado';
  String metodoPagoInicial = metodosPagoDisponibles.first;
  DateTime? fechaVencimiento;
  final folioFacturaCtrl = TextEditingController();
  final montoInicialCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    productos = await productoController.obtenerProductosConPrecioCompra();
    proveedores = await proveedorController.obtenerTodos();

    if (!mounted) return;

    setState(() {
      cargando = false;
    });
  }

  // 🟢 AGREGAR PRODUCTO
  void agregarProducto(Producto p) {
    setState(() => _carrito.agregar(p));
  }

  // 🟢 TOTAL
  double get total => _carrito.total;

  // 🔍 FILTRAR
  List<Producto> get productosFiltrados {
    return productos.where((p) {
      return p.nombre.toLowerCase().contains(busqueda.toLowerCase());
    }).toList();
  }

  // ➕➖ CAMBIAR CANTIDAD
  void cambiarCantidad(int index, int delta) {
    setState(() => _carrito.cambiarCantidad(index, delta));
  }

  // 🧾 GUARDAR COMPRA
  void guardarCompra() async {
    if (carrito.isEmpty || proveedorSeleccionado == null) {
  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: "Datos incompletos",

      mensaje:
          "Debes seleccionar un proveedor y agregar productos a la compra.",

      icono: Icons.warning_amber_rounded,

      textoConfirmar: "Aceptar",

      onConfirm: () {
        Navigator.pop(context);
      },
    ),
  );

  return;
}

    final esContado = formaPago == 'Contado';
    final montoInicial = esContado ? total : (double.tryParse(montoInicialCtrl.text) ?? 0);
    final pagosIniciales = montoInicial > 0
        ? [
            {'metodo_pago': metodoPagoInicial, 'monto': montoInicial}
          ]
        : null;

    try {
      await comprasController.insertarCompraCompleta(
        carrito,
        total,
        proveedorSeleccionado!.idProveedor!,
        formaPago: formaPago,
        fechaVencimiento: esContado ? null : fechaVencimiento,
        folioFactura: folioFacturaCtrl.text,
        montoInicialPagado: montoInicial,
        pagosIniciales: pagosIniciales,
      );

      await imprimirTicket();

      setState(() {
        carrito.clear();
        formaPago = 'Contado';
        fechaVencimiento = null;
        folioFacturaCtrl.clear();
        montoInicialCtrl.text = '0';
      });

      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'COMPRA',
          mensaje: 'Compra realizada con éxito',
          icono: Icons.check_circle_outline,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // 🖨 IMPRIMIR
  Future<void> imprimirTicket() async {
    final pdf = await TicketComprasService.generarTicket(
      carrito: carrito,
      total: total,
      proveedor: proveedorSeleccionado!.nombre,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: const CustomHeader(titulo: "Compras", mostrarVolver: true),

      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),

              child: Row(
                children: [
                  // 🔥 PANEL PRODUCTOS
                  Expanded(
                    flex: 7,
                    child: Container(
                      padding: const EdgeInsets.all(24),

                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: AppColors.cardShadow,
                      ),

                      child: Column(
                        children: [
                          // 🔍 BUSCADOR
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: TextField(
                              onChanged: (v) {
                                setState(() {
                                  busqueda = v;
                                });
                              },
                              decoration: const InputDecoration(
                                hintText: "Buscar producto...",
                                prefixIcon: Icon(Icons.search),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // 📦 GRID
                          Expanded(
                            child: GridView.builder(
                              itemCount: productosFiltrados.length,

                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 18,
                                    childAspectRatio: 1.1,
                                  ),

                              itemBuilder: (_, i) {
                                final p = productosFiltrados[i];

                                return InkWell(
                                  borderRadius: BorderRadius.circular(22),

                                  onTap: () => agregarProducto(p),

                                  child: Container(
                                    padding: const EdgeInsets.all(18),

                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceSubtle,
                                      borderRadius: BorderRadius.circular(22),

                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),

                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,

                                      children: [
                                        // ICONO
                                        Container(
                                          padding: const EdgeInsets.all(12),

                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),

                                          child: const Icon(
                                            Icons.inventory_2_outlined,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        const Spacer(),

                                        // NOMBRE
                                        Text(
                                          p.nombre,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,

                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),

                                        const SizedBox(height: 8),

                                        // PRECIO
                                        Text(
                                          "\$${(p.precioCompra ?? 0).toStringAsFixed(2)}",

                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),

                                        const SizedBox(height: 14),

                                        // BOTÓN
                                        SizedBox(
                                          width: double.infinity,

                                          child: ElevatedButton.icon(
                                            onPressed: () => agregarProducto(p),

                                            icon: const Icon(Icons.add),

                                            label: const Text("Agregar"),

                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              backgroundColor: AppColors.primary,

                                              foregroundColor: AppColors.onPrimary,

                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),

                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
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

                  const SizedBox(width: 24),

                  // 🧾 PANEL CARRITO
                  Expanded(
                    flex: 3,

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
                          // HEADER
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),

                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(14),
                                ),

                                child: const Icon(Icons.shopping_cart),
                              ),

                              const SizedBox(width: 14),

                              const Text(
                                "Orden de Compra",

                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // 🏢 PROVEEDOR
                          DropdownButtonFormField<Proveedores>(
                            value: proveedorSeleccionado,

                            decoration: InputDecoration(
                              labelText: "Proveedor",

                              filled: true,
                              fillColor: AppColors.surface,

                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),

                            items: proveedores.map((p) {
                              return DropdownMenuItem(
                                value: p,
                                child: Text(p.nombre),
                              );
                            }).toList(),

                            onChanged: (value) {
                              setState(() {
                                proveedorSeleccionado = value;
                              });
                            },
                          ),

                          const SizedBox(height: 16),

                          _formaPagoSection(),

                          const SizedBox(height: 24),

                          // 🛒 ITEMS
                          Expanded(
                            child: carrito.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,

                                      children: [
                                        Icon(
                                          Icons.shopping_cart_outlined,
                                          size: 70,
                                          color: Colors.grey.shade400,
                                        ),

                                        const SizedBox(height: 14),

                                        Text(
                                          "No hay productos",

                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: carrito.length,

                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),

                                    itemBuilder: (_, i) {
                                      final item = carrito[i];

                                      final id = item['id_producto'];

                                      if (!controllers.containsKey(id)) {
                                        controllers[id] = TextEditingController(
                                          text: item['cantidad'].toString(),
                                        );
                                      } else {
                                        controllers[id]!.text = item['cantidad']
                                            .toString();
                                      }

                                      return Container(
                                        padding: const EdgeInsets.all(14),

                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceSubtle,

                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),

                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,

                                          children: [
                                            Text(
                                              item['nombre'],

                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),

                                            const SizedBox(height: 6),

                                            Text(
                                              "\$${item['precio_compra']}",
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                              ),
                                            ),

                                            const SizedBox(height: 14),

                                            Row(
                                              children: [
                                                // ➖
                                                _cantidadBtn(
                                                  icon: Icons.remove,
                                                  onTap: () =>
                                                      cambiarCantidad(i, -1),
                                                ),

                                                const SizedBox(width: 10),

                                                SizedBox(
                                                  width: 60,

                                                  child: TextField(
                                                    controller: controllers[id],

                                                    textAlign: TextAlign.center,

                                                    keyboardType:
                                                        TextInputType.number,

                                                    decoration: InputDecoration(
                                                      filled: true,
                                                      fillColor: Colors.white,

                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                            vertical: 10,
                                                          ),

                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                    ),

                                                    onChanged: (value) {
                                                      final cantidad =
                                                          int.tryParse(value) ??
                                                          1;

                                                      setState(() {
                                                        item['cantidad'] =
                                                            cantidad;
                                                      });
                                                    },
                                                  ),
                                                ),

                                                const SizedBox(width: 10),

                                                // ➕
                                                _cantidadBtn(
                                                  icon: Icons.add,
                                                  onTap: () =>
                                                      cambiarCantidad(i, 1),
                                                ),

                                                const Spacer(),

                                                Text(
                                                  "\$${((item['precio_compra'] ?? 0) * item['cantidad']).toStringAsFixed(2)}",

                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
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

                          const SizedBox(height: 20),

                          // 💰 TOTAL
                          Container(
                            padding: const EdgeInsets.all(18),

                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(18),
                            ),

                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,

                              children: [
                                const Text(
                                  "TOTAL",

                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                Text(
                                  "\$${total.toStringAsFixed(2)}",

                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // ✅ BOTÓN
                          SizedBox(
                            width: double.infinity,
                            height: 54,

                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (carrito.isEmpty) return;

                                showDialog(
                                  context: context,

                                  builder: (_) => CustomAlert(
                                    titulo: "Compra",
                                    mensaje: "¿Deseas confirmar la compra?",

                                    icono: Icons.shopping_bag_outlined,

                                    textoCancelar: "Cancelar",
                                    textoConfirmar: "Confirmar",

                                    onConfirm: () {
                                      guardarCompra();
                                    },
                                  ),
                                );
                              },

                              icon: const Icon(Icons.check_circle),

                              label: const Text(
                                "Confirmar Compra",

                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              style: ElevatedButton.styleFrom(
                                elevation: 0,

                                backgroundColor: AppColors.primary,

                                foregroundColor: Colors.black,

                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
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

  // 💳 FORMA DE PAGO: de contado (se paga el total ahora) o a crédito
  // (fecha límite opcional + pago inicial opcional). El folio de factura
  // aplica a cualquiera de las dos.
  Widget _formaPagoSection() {
    final esContado = formaPago == 'Contado';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _formaPagoBtn('Contado')),
            const SizedBox(width: 10),
            Expanded(child: _formaPagoBtn('Credito', label: 'Crédito')),
          ],
        ),
        const SizedBox(height: 12),
        if (esContado)
          DropdownButtonFormField<String>(
            initialValue: metodoPagoInicial,
            decoration: InputDecoration(
              labelText: 'Método de pago',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            items: metodosPagoDisponibles
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setState(() => metodoPagoInicial = v!),
          )
        else ...[
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final fecha = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (fecha != null) setState(() => fechaVencimiento = fecha);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    fechaVencimiento == null
                        ? 'Fecha límite de pago (opcional)'
                        : '${fechaVencimiento!.day}/${fechaVencimiento!.month}/${fechaVencimiento!.year}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: montoInicialCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Pago inicial (opcional)',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: metodoPagoInicial,
            decoration: InputDecoration(
              labelText: 'Método del pago inicial',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            items: metodosPagoDisponibles
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setState(() => metodoPagoInicial = v!),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: folioFacturaCtrl,
          decoration: InputDecoration(
            labelText: 'Folio de factura (opcional)',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _formaPagoBtn(String valor, {String? label}) {
    final seleccionado = formaPago == valor;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => formaPago = valor),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label ?? valor,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: seleccionado ? AppColors.onPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _cantidadBtn({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(10),

      child: Container(
        padding: const EdgeInsets.all(8),

        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),

          border: Border.all(color: Colors.grey.shade300),
        ),

        child: Icon(icon, size: 18),
      ),
    );
  }

  @override
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    folioFacturaCtrl.dispose();
    montoInicialCtrl.dispose();

    super.dispose();
  }
}
