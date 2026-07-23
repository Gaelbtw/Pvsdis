import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../models/cliente_model.dart';
import '../services/cliente_services.dart';
import '../controllers/pedidos_controller.dart';
import '../widgets/custom_alert.dart';
import '../widgets/pedidos/editar_pedido_dialog.dart';
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
      backgroundColor: AppColors.surface,
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
              activo ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  activo ? Colors.black : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
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
                    borderRadius: BorderRadius.circular(AppRadius.md),
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
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        onTap: () =>
                            setState(() => seleccionado = cliente),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
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
                                    AppColors.primaryLight,
                                child: Text(
                                  cliente.nombre[0],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppText.titleLg,
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
                                  fontSize: AppText.bodyLg,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                cliente.telefono.toString(),
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    side: BorderSide(
                                        color: AppColors.border),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.sm),
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: seleccionado == null
              ? const Center(
                  child: Text(
                    "Selecciona un cliente",
                    style: TextStyle(fontSize: AppText.bodyLg),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Detalles del Cliente",
                      style: TextStyle(
                        fontSize: AppText.titleLg,
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
                              AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
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
                            fontSize: AppText.bodyLg,
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
                size: 64, color: AppColors.textSecondary),
            SizedBox(height: 16),
            Text(
              "No hay pedidos registrados",
              style: TextStyle(fontSize: AppText.subtitle, color: AppColors.textSecondary),
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('#',
                        style:
                            TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
                    Text(
                      idPedido.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.subtitle,
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
                        fontSize: AppText.bodyLg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 13,
                            color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(fecha,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppText.small)),
                        const SizedBox(width: 12),
                        Icon(
                          tipo == 'Domicilio'
                              ? Icons.delivery_dining
                              : Icons.store_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(tipo,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppText.small)),
                      ],
                    ),
                    if (fechaEntrega.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Entrega: $fechaEntrega',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: AppText.small),
                      ),
                    ],
                    if (direccion.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        direccion,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: AppText.caption),
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
                    AppConfig.formatoMoneda(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: AppText.subtitle),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: Icon(Icons.edit_outlined,
                        color: AppColors.primaryDark),
                    onPressed: () => _editarPedido(p),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: Icon(Icons.delete_outline,
                        color: AppColors.error),
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
        color = AppColors.success;
        break;
      case 'Cancelado':
        color = AppColors.error;
        break;
      case 'En Proceso':
        color = AppColors.info;
        break;
      default:
        color = AppColors.warning;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        estado,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: AppText.caption,
        ),
      ),
    );
  }

  void _editarPedido(Map<String, dynamic> pedidoMap) {
    mostrarEditarPedidoDialog(
      context,
      pedidoMap: pedidoMap,
      pedidosController: pedidosController,
      onGuardado: cargarPedidos,
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
            SnackBar(
              content: const Text('Pedido eliminado con éxito'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 2),
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
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: AppText.bodyLg),
          ),
        ],
      ),
    );
  }
}
