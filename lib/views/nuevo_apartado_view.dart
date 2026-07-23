import 'package:flutter/material.dart';

import '../controllers/apartados_controller.dart';
import '../controllers/cliente_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/promociones_controller.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/descuento_utils.dart';
import '../core/utils/pagos_mixtos.dart';
import '../core/utils/promociones_engine.dart';
import '../models/carrito_venta.dart';
import '../models/cliente_model.dart';
import '../models/producto_model.dart';
import '../models/promocion_model.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';
import '../widgets/ventas/pagos_mixtos_section.dart';

/// Crea un apartado: selecciona cliente, arma el carrito (mismo motor de
/// cálculo/promociones que una venta) y, opcionalmente, cobra un anticipo
/// con el mismo `PagosMixtosSection` que usa el cobro normal.
class NuevoApartadoView extends StatefulWidget {
  const NuevoApartadoView({super.key});

  @override
  State<NuevoApartadoView> createState() => _NuevoApartadoViewState();
}

class _NuevoApartadoViewState extends State<NuevoApartadoView> {
  final _apartadosController = ApartadosController();
  final _clienteController = ClienteController();
  final _productoController = ProductoController();
  final _promocionesController = PromocionesController();

  List<Cliente> _clientes = [];
  List<Cliente> _clientesFiltrados = [];
  Cliente? _clienteSeleccionado;
  final _busquedaClienteCtrl = TextEditingController();

  List<Producto> _productos = [];
  Map<int, int> _stockDisponible = {};
  final _carrito = CarritoVenta();
  final _busquedaProductoCtrl = TextEditingController();
  String _busquedaProducto = '';

  List<Promocion> _promocionesActivas = [];
  DateTime? _fechaLimite;

  final _anticipoCtrl = TextEditingController(text: '0');
  double _montoAnticipo = 0;
  List<Map<String, dynamic>> _pagosAnticipo = [];
  ResultadoValidacionPagos _resultadoPagos = validarPagosMixtos(total: 0, pagos: const []);

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final clientes = await _clienteController.obtenerTodos();
    final productosData = await _productoController.obtenerConStock();
    final promociones = await _promocionesController.obtenerActivasVigentes();

    final stock = <int, int>{};
    final productos = <Producto>[];
    for (final row in productosData) {
      final p = Producto.fromMap(row);
      productos.add(p);
      if (p.idProducto != null) {
        stock[p.idProducto!] = (row['disponible'] as int?) ?? 0;
      }
    }

    if (!mounted) return;
    setState(() {
      _clientes = clientes;
      _clientesFiltrados = clientes;
      _productos = productos;
      _stockDisponible = stock;
      _promocionesActivas = promociones;
      _cargando = false;
    });
  }

  void _buscarCliente(String query) {
    final q = query.toLowerCase();
    setState(() {
      _clientesFiltrados =
          q.isEmpty ? _clientes : _clientes.where((c) => c.nombre.toLowerCase().contains(q)).toList();
    });
  }

  List<Producto> get _productosFiltrados {
    final q = _busquedaProducto.toLowerCase();
    if (q.isEmpty) return _productos;
    return _productos.where((p) => p.nombre.toLowerCase().contains(q)).toList();
  }

  ResultadoPromociones get _resultadoPromociones =>
      evaluarPromociones(carrito: _carrito.items, promocionesActivas: _promocionesActivas);

  VentaCalculada get _calculo => calcularVenta(
        carrito: _carrito.items,
        descuentosPromocionPorLinea: _resultadoPromociones.descuentoPorLinea,
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        descuentoMaximoPorcentaje: AppConfig.actual.descuentoMaximoPorcentaje,
      );

  void _actualizarAnticipo(String value) {
    final monto = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    setState(() => _montoAnticipo = monto.clamp(0, _calculo.total > 0 ? _calculo.total : 0).toDouble());
  }

  Future<void> _elegirFechaLimite() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaLimite ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (elegida != null) setState(() => _fechaLimite = elegida);
  }

  Future<void> _crear() async {
    if (_clienteSeleccionado == null) {
      _mostrarError('Selecciona un cliente para el apartado.');
      return;
    }
    if (_carrito.items.isEmpty) {
      _mostrarError('Agrega al menos un producto.');
      return;
    }
    if (_montoAnticipo > 0 && !_resultadoPagos.esValido) {
      _mostrarError(_resultadoPagos.mensajeError ?? 'Revisa los pagos del anticipo.');
      return;
    }

    setState(() => _guardando = true);
    try {
      await _apartadosController.crear(
        idCliente: _clienteSeleccionado!.idCliente!,
        carrito: _carrito.items,
        montoAnticipo: _montoAnticipo,
        pagosAnticipo: _montoAnticipo > 0 ? _pagosAnticipo : const [],
        descuentoGlobalTipo: _carrito.descuentoGlobalTipo,
        descuentoGlobalValor: _carrito.descuentoGlobalValor,
        fechaLimite: _fechaLimite,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'Apartado creado',
          mensaje: 'El apartado se registró correctamente.',
          icono: Icons.check_circle_outline,
          textoConfirmar: 'Aceptar',
          onConfirm: () => Navigator.pop(context),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _mostrarError(String mensaje) {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'No se pudo crear el apartado',
        mensaje: mensaje,
        icono: Icons.error_outline,
        textoConfirmar: 'Aceptar',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calculo = _calculo;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: 'Nuevo apartado', mostrarVolver: true),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.bodyLg)),
                          const SizedBox(height: 10),
                          if (_clienteSeleccionado != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLighter,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _clienteSeleccionado!.nombre,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() => _clienteSeleccionado = null),
                                    child: const Text('Cambiar'),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            TextField(
                              controller: _busquedaClienteCtrl,
                              onChanged: _buscarCliente,
                              decoration: InputDecoration(
                                hintText: 'Buscar cliente...',
                                prefixIcon: const Icon(Icons.search),
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 140,
                              child: ListView.builder(
                                itemCount: _clientesFiltrados.length,
                                itemBuilder: (_, i) {
                                  final c = _clientesFiltrados[i];
                                  return ListTile(
                                    title: Text(c.nombre),
                                    onTap: () => setState(() => _clienteSeleccionado = c),
                                  );
                                },
                              ),
                            ),
                          ],
                          const Divider(height: 30),
                          const Text('Productos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.bodyLg)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _busquedaProductoCtrl,
                            onChanged: (v) => setState(() => _busquedaProducto = v),
                            decoration: InputDecoration(
                              hintText: 'Buscar producto...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: GridView.builder(
                              itemCount: _productosFiltrados.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.3,
                              ),
                              itemBuilder: (_, i) {
                                final p = _productosFiltrados[i];
                                final disponible = _stockDisponible[p.idProducto] ?? 0;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  onTap: disponible <= _carrito.cantidadEnCarrito(p.idProducto)
                                      ? null
                                      : () => setState(() => _carrito.agregar(p)),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(AppRadius.md),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
                                        const Spacer(),
                                        Text('\$${p.precio.toStringAsFixed(2)}',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text('Disponible: $disponible', style: const TextStyle(fontSize: AppText.overline)),
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
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Carrito', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.bodyLg)),
                            const SizedBox(height: 10),
                            if (_carrito.items.isEmpty)
                              const Text('No hay productos agregados')
                            else
                              ...List.generate(_carrito.items.length, (i) {
                                final item = _carrito.items[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text('${item['nombre']}')),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                                        onPressed: () => setState(() => _carrito.cambiarCantidad(i, -1)),
                                      ),
                                      Text('${item['cantidad']}'),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 18),
                                        onPressed: (_stockDisponible[item['id_producto']] ?? 0) <=
                                                (item['cantidad'] as int)
                                            ? null
                                            : () => setState(() => _carrito.cambiarCantidad(i, 1)),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            const Divider(height: 30),
                            InkWell(
                              onTap: _elegirFechaLimite,
                              child: Row(
                                children: [
                                  const Icon(Icons.event, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _fechaLimite == null
                                        ? 'Sin fecha límite (opcional)'
                                        : 'Vence: ${_fechaLimite!.day}/${_fechaLimite!.month}/${_fechaLimite!.year}',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total'),
                                Text('\$${calculo.total.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.subtitle)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('Anticipo (opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _anticipoCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: _actualizarAnticipo,
                              decoration: InputDecoration(
                                hintText: '\$0.00',
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.md),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            if (_montoAnticipo > 0) ...[
                              const SizedBox(height: 16),
                              PagosMixtosSection(
                                total: _montoAnticipo,
                                onCambio: (pagos, resultado) {
                                  setState(() {
                                    _pagosAnticipo = pagos;
                                    _resultadoPagos = resultado;
                                  });
                                },
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _guardando ? null : _crear,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                ),
                                child: Text(_guardando ? 'Guardando...' : 'Crear apartado'),
                              ),
                            ),
                          ],
                        ),
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
    _busquedaClienteCtrl.dispose();
    _busquedaProductoCtrl.dispose();
    _anticipoCtrl.dispose();
    super.dispose();
  }
}
