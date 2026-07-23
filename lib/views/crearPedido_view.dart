import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../controllers/pedidos_controller.dart';
import '../models/carrito_pedido.dart';
import '../models/pedidos_model.dart';
import '../models/producto_model.dart';
import '../widgets/nav_bar.dart';
import '../widgets/custom_alert.dart';
import '../controllers/producto_controller.dart';

class CrearPedidoView extends StatefulWidget {
  final int? idCliente;
  final String? nombreCliente;

  const CrearPedidoView({
    super.key,
    this.idCliente,
    this.nombreCliente,
  });

  @override
  State<CrearPedidoView> createState() => _CrearPedidoViewState();
}

class _CrearPedidoViewState extends State<CrearPedidoView> {
  final controller = PedidosController();
  final productoService = ProductoController();

  final direccionCtrl = TextEditingController();

  List<Producto> productos = [];
  Map<int, int> _stock = {};
  final _carrito = CarritoPedido();
  List<Map<String, dynamic>> get carrito => _carrito.items;

  String tipoEntrega = "Domicilio";
  DateTime? _fechaEntrega;
  double total = 0;

  @override
  void initState() {
    super.initState();
    cargarProductos();
  }

  Future<void> cargarProductos() async {
    final prods = await productoService.obtenerTodos();
    final stock = await productoService.obtenerStockMap();
    setState(() {
      productos = prods;
      _stock = stock;
    });
  }

  void agregarProducto(Producto producto) {
    final stockDisponible = _stock[producto.idProducto] ?? 0;
    final cantidadEnCarrito = _carrito.cantidadEnCarrito(producto.idProducto);

    if (stockDisponible == 0) {
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'Sin stock disponible',
          mensaje:
              '${producto.nombre} no tiene unidades en inventario.\nContacta a tu proveedor.',
          icono: Icons.inventory_2_outlined,
          textoConfirmar: 'Entendido',
          color: AppColors.error,
        ),
      );
      return;
    }

    if (cantidadEnCarrito >= stockDisponible) {
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'Stock insuficiente',
          mensaje:
              'Solo hay $stockDisponible unidad(es) de ${producto.nombre} en inventario y ya las tienes en el pedido.',
          icono: Icons.warning_rounded,
          textoConfirmar: 'Entendido',
          color: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _carrito.agregar(producto));

    calcularTotal();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${producto.nombre} agregado al pedido'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void calcularTotal() {
    setState(() => total = _carrito.total);
  }

  void aumentar(int index) {
    final producto = carrito[index]['producto'] as Producto;
    final cantidadActual = carrito[index]['cantidad'] as int;
    final stockDisponible = _stock[producto.idProducto] ?? 0;

    if (cantidadActual >= stockDisponible) {
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'Stock insuficiente',
          mensaje:
              'Ya tienes todas las unidades disponibles de ${producto.nombre} ($stockDisponible) en el pedido.',
          icono: Icons.warning_rounded,
          textoConfirmar: 'Entendido',
          color: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _carrito.aumentar(index));
    calcularTotal();
  }

  void disminuir(int index) {
    setState(() => _carrito.disminuir(index));
    calcularTotal();
  }

  Future<void> guardarPedido() async {
    if (widget.idCliente == null) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Cliente requerido',
          mensaje: 'Selecciona un cliente.',
          icono: Icons.person_outline,
          textoConfirmar: 'Aceptar',
        ),
      );
      return;
    }

    if (carrito.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Pedido vacío',
          mensaje: 'Agrega productos al pedido.',
          icono: Icons.shopping_cart_outlined,
          textoConfirmar: 'Aceptar',
        ),
      );
      return;
    }

    if (_fechaEntrega == null) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Fecha requerida',
          mensaje: 'Selecciona una fecha de entrega.',
          icono: Icons.calendar_month_outlined,
          textoConfirmar: 'Aceptar',
        ),
      );
      return;
    }

    if (tipoEntrega == 'Domicilio' && direccionCtrl.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Dirección requerida',
          mensaje: 'Ingresa la dirección de entrega.',
          icono: Icons.location_on_outlined,
          textoConfirmar: 'Aceptar',
        ),
      );
      return;
    }

    final fechaStr =
        '${_fechaEntrega!.day}/${_fechaEntrega!.month}/${_fechaEntrega!.year}';

    final pedido = Pedidos(
      idCliente: widget.idCliente!,
      fecha: DateTime.now().toIso8601String(),
      fechaEntrega: fechaStr,
      tipoEntrega: tipoEntrega,
      estado: 'Pendiente',
      total: total,
      direccion:
          tipoEntrega == 'Domicilio' ? direccionCtrl.text.trim() : null,
    );

    await controller.crearPedidoCompleto(pedido, _carrito.paraGuardar());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'Transacción exitosa',
        mensaje: 'El pedido se guardó correctamente.',
        icono: Icons.check_circle_outline,
        textoConfirmar: 'Aceptar',
        onConfirm: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const CustomHeader(
        titulo: 'Crear Pedido',
        mostrarVolver: true,
      ),
      body: SafeArea(
        child: Row(
          children: [
            /// FORMULARIO
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEA),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Nuevo Pedido',
                                  style: TextStyle(
                                    fontSize: AppText.display,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.nombreCliente ?? '',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: AppText.bodyLg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Tipo de entrega
                    const Text(
                      'Tipo de entrega',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.subtitle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        tipoCard('Domicilio'),
                        const SizedBox(width: 16),
                        tipoCard('Recoger'),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Fecha de entrega (siempre visible)
                    _buildFechaPicker(),

                    // Dirección (solo domicilio)
                    if (tipoEntrega == 'Domicilio') ...[
                      const SizedBox(height: 20),
                      campo(
                        controller: direccionCtrl,
                        titulo: 'Dirección',
                        icon: Icons.location_on_outlined,
                        hint: 'Calle, colonia, ciudad',
                      ),
                    ],

                    const SizedBox(height: 35),

                    const Text(
                      'Productos',
                      style: TextStyle(
                        fontSize: AppText.title,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: productos.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        childAspectRatio: 0.95,
                      ),
                      itemBuilder: (context, index) {
                        final producto = productos[index];
                        final stockActual =
                            _stock[producto.idProducto] ?? 0;
                        final sinStock = stockActual == 0;

                        return Opacity(
                          opacity: sinStock ? 0.55 : 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.pill),
                                      ),
                                      child: Text(
                                        AppConfig.formatoMoneda(producto.precio),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: AppText.small,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sinStock
                                            ? AppColors.error.withValues(alpha: 0.12)
                                            : stockActual <=
                                                    producto.stockMinimo
                                                ? AppColors.warning
                                                    .withValues(alpha: 0.12)
                                                : AppColors.success
                                                    .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Text(
                                        sinStock
                                            ? 'Sin stock'
                                            : 'Stock: $stockActual',
                                        style: TextStyle(
                                          fontSize: AppText.overline,
                                          fontWeight: FontWeight.bold,
                                          color: sinStock
                                              ? AppColors.error
                                              : stockActual <=
                                                      producto.stockMinimo
                                                  ? AppColors.warning
                                                  : AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const Spacer(),

                                Text(
                                  producto.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppText.bodyLg,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  producto.descripcion,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: AppText.caption,
                                  ),
                                ),

                                const SizedBox(height: 14),

                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: sinStock
                                          ? AppColors.border
                                          : AppColors.primary,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.md),
                                      ),
                                    ),
                                    onPressed: sinStock
                                        ? null
                                        : () => agregarProducto(producto),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Agregar'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            /// PANEL DERECHO
            Container(
              width: 360,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detalle del Pedido',
                    style: TextStyle(
                      fontSize: AppText.heading,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 30),

                  Expanded(
                    child: carrito.isEmpty
                        ? const Center(
                            child: Text('No hay productos agregados'),
                          )
                        : ListView.builder(
                            itemCount: carrito.length,
                            itemBuilder: (context, index) {
                              final item = carrito[index];
                              final producto =
                                  item['producto'] as Producto;
                              final cantidad = item['cantidad'] as int;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8F8),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.md),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      producto.nombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppText.bodyLg,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        cantidadBtn(
                                          Icons.remove,
                                          () => disminuir(index),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Text(
                                            cantidad.toString(),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        cantidadBtn(
                                          Icons.add,
                                          () => aumentar(index),
                                        ),
                                        const Spacer(),
                                        Text(
                                          AppConfig.formatoMoneda((producto.precio * cantidad)),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: AppText.bodyLg,
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

                  Row(
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: AppText.heading,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        AppConfig.formatoMoneda(total),
                        style: const TextStyle(
                          fontSize: AppText.display,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      onPressed: guardarPedido,
                      child: const Text(
                        'Guardar Pedido',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppText.bodyLg,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFechaPicker() {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fecha de entrega',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fechaEntrega ??
                    DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime(DateTime.now().year + 2),
              );
              if (picked != null) setState(() => _fechaEntrega = picked);
            },
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Text(
                    _fechaEntrega != null
                        ? '${_fechaEntrega!.day}/${_fechaEntrega!.month}/${_fechaEntrega!.year}'
                        : 'Seleccionar fecha',
                    style: TextStyle(
                      color: _fechaEntrega != null
                          ? Colors.black87
                          : AppColors.textSecondary,
                      fontSize: AppText.bodyLg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget campo({
    required TextEditingController controller,
    required String titulo,
    required IconData icon,
    required String hint,
  }) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget tipoCard(String tipo) {
    final activo = tipoEntrega == tipo;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => setState(() => tipoEntrega = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: activo ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tipo == 'Domicilio'
                  ? Icons.delivery_dining
                  : Icons.store_outlined,
              size: 18,
              color: activo ? Colors.black : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              tipo,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: activo ? Colors.black : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cantidadBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}
