import 'package:flutter/material.dart';
import '../models/cliente_model.dart';
import '../models/pedidos_model.dart';
import '../services/cliente_services.dart';
import '../services/producto_services.dart';
import '../controllers/pedidos_controller.dart';
import '../widgets/custom_alert.dart';
import 'crearPedido_view.dart';
import '../widgets/nav_bar.dart';

class PedidosView extends StatefulWidget {
  const PedidosView({super.key});

  @override
  State<PedidosView> createState() => _PedidosViewState();
}

class _PedidosViewState extends State<PedidosView> {
  final clienteService = ClienteService();
  final pedidosController = PedidosController();
  final productoService = ProductoService();

  List<Cliente> clientes = [];
  List<Cliente> filtrados = [];
  List<Map<String, dynamic>> _pedidos = [];

  final searchCtrl = TextEditingController();
  Cliente? seleccionado;
  bool _verPedidos = false;

  @override
  void initState() {
    super.initState();
    cargarClientes();
    cargarPedidos();
  }

  Future<void> cargarClientes() async {
    final data = await clienteService.obtenerTodos();
    setState(() {
      clientes = data;
      filtrados = data;
    });
  }

  Future<void> cargarPedidos() async {
    final data = await pedidosController.obtenerPedidosConCliente();
    setState(() => _pedidos = data);
  }

  void buscar(String value) {
    setState(() {
      filtrados = clientes
          .where((c) => c.nombre.toLowerCase().contains(value.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomHeader(titulo: "Pedidos", mostrarVolver: true),
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildToggle(),
            Expanded(
              child:
                  _verPedidos ? _buildPedidosList() : _buildNuevoPedido(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _toggleBtn('Nuevo Pedido', Icons.add_circle_outline, !_verPedidos),
          const SizedBox(width: 12),
          _toggleBtn('Ver Pedidos', Icons.list_alt, _verPedidos),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, IconData icon, bool activo) {
    return GestureDetector(
      onTap: () {
        setState(() => _verPedidos = label == 'Ver Pedidos');
        if (_verPedidos) cargarPedidos();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color:
              activo ? const Color(0xFFE5C100) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  activo ? Colors.black : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: activo ? Colors.black : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── NUEVO PEDIDO ────────────────────────────────────────────────────────────

  Widget _buildNuevoPedido() {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 55,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: buscar,
                    decoration: const InputDecoration(
                      hintText: "Buscar cliente",
                      prefixIcon: Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.builder(
                    itemCount: filtrados.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: 1.2,
                    ),
                    itemBuilder: (context, index) {
                      final cliente = filtrados[index];
                      final isSelected =
                          seleccionado?.idCliente == cliente.idCliente;

                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () =>
                            setState(() => seleccionado = cliente),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFE5C100)
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    const Color(0xFFFFF3B0),
                                child: Text(
                                  cliente.nombre[0],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                cliente.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                cliente.telefono.toString(),
                                style: TextStyle(
                                    color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    side: BorderSide(
                                        color: Colors.grey.shade300),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CrearPedidoView(
                                        idCliente: cliente.idCliente,
                                        nombreCliente: cliente.nombre,
                                      ),
                                    ),
                                  ).then((_) => cargarPedidos()),
                                  icon: const Icon(Icons.add),
                                  label: const Text("Pedido"),
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

        Container(
          width: 340,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: seleccionado == null
              ? const Center(
                  child: Text(
                    "Selecciona un cliente",
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Detalles del Cliente",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),
                    _info("Nombre", seleccionado!.nombre),
                    _info("Telefono",
                        seleccionado!.telefono.toString()),
                    _info("Correo", seleccionado!.correo ?? "-"),
                    _info("Direccion",
                        seleccionado!.direccion ?? "-"),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFFE5C100),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CrearPedidoView(
                              idCliente: seleccionado!.idCliente,
                              nombreCliente: seleccionado!.nombre,
                            ),
                          ),
                        ).then((_) => cargarPedidos()),
                        child: const Text(
                          "Continuar",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ─── VER PEDIDOS ─────────────────────────────────────────────────────────────

  Widget _buildPedidosList() {
    if (_pedidos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "No hay pedidos registrados",
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _pedidos.length,
      itemBuilder: (context, index) {
        final p = _pedidos[index];
        final idPedido = p['id_pedido'] as int;
        final estado = p['estado']?.toString() ?? 'Pendiente';
        final tipo = p['tipo_entrega']?.toString() ?? '';
        final clienteNombre =
            p['cliente_nombre']?.toString() ?? 'Sin cliente';
        final fecha = p['fecha']?.toString() ?? '';
        final fechaEntrega = p['fecha_entrega']?.toString() ?? '';
        final direccion = p['direccion']?.toString() ?? '';
        final total = (p['total'] as num?)?.toDouble() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5C100).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('#',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      idPedido.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clienteNombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 13,
                            color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(fecha,
                            style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13)),
                        const SizedBox(width: 12),
                        Icon(
                          tipo == 'Domicilio'
                              ? Icons.delivery_dining
                              : Icons.store_outlined,
                          size: 13,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(tipo,
                            style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13)),
                      ],
                    ),
                    if (fechaEntrega.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Entrega: $fechaEntrega',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                    if (direccion.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        direccion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _estadoChip(estado),
                  const SizedBox(height: 8),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined,
                        color: Color(0xFFCC9A00)),
                    onPressed: () => _editarPedido(p),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: Icon(Icons.delete_outline,
                        color: Colors.red.shade400),
                    onPressed: () => _confirmarEliminar(idPedido),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _estadoChip(String estado) {
    Color color;
    switch (estado) {
      case 'Entregado':
        color = Colors.green;
        break;
      case 'Cancelado':
        color = Colors.red;
        break;
      case 'En Proceso':
        color = Colors.blue;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _editarPedido(Map<String, dynamic> pedidoMap) {
    String estado = pedidoMap['estado']?.toString() ?? 'Pendiente';
    String tipo = pedidoMap['tipo_entrega']?.toString() ?? 'Domicilio';
    String fechaEntregaStr =
        pedidoMap['fecha_entrega']?.toString() ?? '';
    String direccion = pedidoMap['direccion']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title:
              Text('Editar Pedido #${pedidoMap["id_pedido"]}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Estado',
                    style:
                        TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: estado,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    'Pendiente',
                    'En Proceso',
                    'Entregado',
                    'Cancelado'
                  ]
                      .map((e) => DropdownMenuItem(
                          value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) =>
                      setDialog(() => estado = v!),
                ),
                const SizedBox(height: 16),
                const Text('Tipo de entrega',
                    style:
                        TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _tipoChipDialog('Domicilio', tipo,
                        (v) => setDialog(() => tipo = v)),
                    const SizedBox(width: 12),
                    _tipoChipDialog('Recoger', tipo,
                        (v) => setDialog(() => tipo = v)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Fecha de entrega',
                    style:
                        TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 365)),
                      lastDate:
                          DateTime(DateTime.now().year + 2),
                    );
                    if (picked != null) {
                      setDialog(() {
                        fechaEntregaStr =
                            '${picked.day}/${picked.month}/${picked.year}';
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month,
                            color: Colors.grey, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          fechaEntregaStr.isEmpty
                              ? 'Seleccionar fecha'
                              : fechaEntregaStr,
                          style: TextStyle(
                            color: fechaEntregaStr.isEmpty
                                ? Colors.grey
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (tipo == 'Domicilio') ...[
                  const SizedBox(height: 16),
                  const Text('Dirección',
                      style: TextStyle(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: direccion,
                    onChanged: (v) => direccion = v,
                    decoration: InputDecoration(
                      hintText: 'Calle, colonia, ciudad',
                      filled: true,
                      fillColor: const Color(0xFFF7F7F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(
                          Icons.location_on_outlined),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5C100),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final idPedido =
                    pedidoMap['id_pedido'] as int;
                final estadoAnterior =
                    pedidoMap['estado']?.toString() ??
                        'Pendiente';

                final actualizado = Pedidos(
                  idPedido: idPedido,
                  idCliente: pedidoMap['id_cliente'] as int,
                  fecha: pedidoMap['fecha']?.toString() ?? '',
                  fechaEntrega: fechaEntregaStr,
                  tipoEntrega: tipo,
                  estado: estado,
                  total: (pedidoMap['total'] as num?)
                          ?.toDouble() ??
                      0,
                  direccion:
                      tipo == 'Domicilio' ? direccion : null,
                );

                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);

                await pedidosController.actualizar(actualizado);

                // Ajuste de inventario según cambio de estado
                if (estado == 'Entregado' &&
                    estadoAnterior != 'Entregado') {
                  final detalle = await pedidosController
                      .obtenerDetalle(idPedido);
                  for (final item in detalle) {
                    await productoService.deducirStockPedido(
                      item['id_producto'] as int,
                      item['cantidad'] as int,
                    );
                  }
                } else if (estado == 'Cancelado' &&
                    estadoAnterior == 'Entregado') {
                  final detalle = await pedidosController
                      .obtenerDetalle(idPedido);
                  for (final item in detalle) {
                    await productoService.restaurarStockPedido(
                      item['id_producto'] as int,
                      item['cantidad'] as int,
                    );
                  }
                }

                if (!mounted) return;
                nav.pop();
                cargarPedidos();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      estado == 'Entregado' &&
                              estadoAnterior != 'Entregado'
                          ? 'Pedido entregado — inventario actualizado'
                          : estado == 'Cancelado' &&
                                  estadoAnterior == 'Entregado'
                              ? 'Pedido cancelado — stock restaurado'
                              : 'Pedido editado con éxito',
                    ),
                    backgroundColor: estado == 'Entregado'
                        ? Colors.green
                        : estado == 'Cancelado'
                            ? Colors.red
                            : Colors.blueGrey,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              child: const Text('Guardar',
                  style:
                      TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipoChipDialog(
      String label, String selected, ValueChanged<String> onTap) {
    final activo = selected == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: activo
              ? const Color(0xFFE5C100)
              : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: activo ? Colors.black : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  void _confirmarEliminar(int idPedido) {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'Eliminar Pedido',
        mensaje:
            '¿Deseas eliminar el pedido #$idPedido? Esta acción no se puede deshacer.',
        icono: Icons.delete_outline,
        textoConfirmar: 'Eliminar',
        textoCancelar: 'Cancelar',
        onConfirm: () async {
          final messenger = ScaffoldMessenger.of(context);
          await pedidosController.eliminar(idPedido);
          if (!mounted) return;
          cargarPedidos();
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Pedido eliminado con éxito'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }

  Widget _info(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
