import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../views/ventas_view.dart';
import '../controllers/cliente_controller.dart';
import '../models/cliente_model.dart';
import '../widgets/nav_bar.dart';

import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/stat_card.dart';

class ClientesView extends StatefulWidget {
  const ClientesView({super.key});

  @override
  State<ClientesView> createState() => _ClientesViewState();
}

class _ClientesViewState extends State<ClientesView> {
  final controller = ClienteController();

  List<Cliente> clientes = [];
  int? selectedIndex;

  final searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargar();
  }

  void cargar() async {
    final data = await controller.obtenerTodos();

    setState(() {
      clientes = data;

      if (selectedIndex != null && selectedIndex! >= clientes.length) {
        selectedIndex = null;
      }
    });
  }

  void buscar(String query) async {
    if (query.isEmpty) {
      cargar();
    } else {
      final data = await controller.buscar(query);

      setState(() {
        clientes = data;

        if (selectedIndex != null && selectedIndex! >= clientes.length) {
          selectedIndex = null;
        }
      });
    }
  }

  void eliminar(int id) async {
    await controller.eliminar(id);
    cargar();
  }

  // FORMULARIO MODAL (crear si [cliente] es null, editar si no)
  void _mostrarFormulario({Cliente? cliente}) {
    final nombreCtrl = TextEditingController(text: cliente?.nombre);
    final direccionCtrl = TextEditingController(text: cliente?.direccion);
    final telefonoCtrl = TextEditingController(text: cliente?.telefono?.toString());
    final correoCtrl = TextEditingController(text: cliente?.correo);

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: cliente == null ? "Nuevo Cliente" : "Editar Cliente",
        subtitulo: cliente == null
            ? "Complete la información del cliente"
            : "Actualice la información del cliente",
        campos: [
          AppTextField(controller: nombreCtrl, hint: "Nombre"),
          AppTextField(controller: direccionCtrl, hint: "Dirección"),
          AppTextField(
            controller: telefonoCtrl,
            hint: "Teléfono",
            keyboardType: TextInputType.phone,
          ),
          AppTextField(
            controller: correoCtrl,
            hint: "Correo",
            keyboardType: TextInputType.emailAddress,
          ),
        ],
        onGuardar: () async {
          if (cliente == null && nombreCtrl.text.trim().isEmpty) {
            showDialog(
              context: context,
              builder: (_) => CustomAlert(
                titulo: "Error",
                mensaje: "El nombre es obligatorio.",
                icono: Icons.error_outline,
                textoConfirmar: "Aceptar",
                onConfirm: () {},
              ),
            );
            return;
          }

          final nuevo = Cliente(
            idCliente: cliente?.idCliente,
            nombre: nombreCtrl.text,
            direccion: direccionCtrl.text,
            telefono: int.tryParse(telefonoCtrl.text),
            correo: correoCtrl.text,
            fechaRegistro: DateTime.now().toIso8601String(),
          );

          if (cliente == null) {
            await controller.insertar(nuevo);
          } else {
            await controller.actualizar(nuevo);
          }

          if (!context.mounted) return;
          Navigator.pop(context);
          cargar();

          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: cliente == null ? "Cliente agregado" : "Cliente actualizado",
              mensaje: cliente == null
                  ? "El cliente ha sido agregado exitosamente."
                  : "El cliente ha sido actualizado exitosamente.",
              icono: Icons.check_circle_outline,
              textoConfirmar: "Aceptar",
              onConfirm: () {},
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Clientes", mostrarVolver: true),

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

          child: Row(
            children: [
              // 🔥 IZQUIERDA
              Expanded(
                flex: 7,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    // 🔥 TÍTULO
                    const Text(
                      "Gestión de Clientes",

                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Administre clientes registrados y genere ventas rápidamente",

                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),

                    const SizedBox(height: 24),

                    // 🔥 MÉTRICAS
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: "Clientes",
                            value: clientes.length.toString(),
                            icon: Icons.people_alt_outlined,
                            color: AppColors.primary,
                            iconoArribaConFondoTenido: false,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: StatCard(
                            title: "Con teléfono",
                            value: clientes
                                .where((c) => c.telefono != null)
                                .length
                                .toString(),
                            icon: Icons.phone_outlined,
                            color: AppColors.primary,
                            iconoArribaConFondoTenido: false,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: StatCard(
                            title: "Con correo",
                            value: clientes
                                .where((c) => c.correo != null)
                                .length
                                .toString(),
                            icon: Icons.email_outlined,
                            color: AppColors.primary,
                            iconoArribaConFondoTenido: false,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 🔥 BUSCADOR
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,

                            onChanged: buscar,

                            decoration: InputDecoration(
                              hintText: "Buscar cliente...",

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

                        const SizedBox(width: 12),

                        ElevatedButton.icon(
                          onPressed: _mostrarFormulario,

                          icon: const Icon(Icons.add),

                          label: const Text("Nuevo Cliente"),

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
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 🔥 LISTA
                    Expanded(
                      child: clientes.isEmpty
                          ? const Center(
                              child: Text("No hay clientes registrados"),
                            )
                          : ListView.separated(
                              itemCount: clientes.length,

                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),

                              itemBuilder: (_, i) {
                                final c = clientes[i];

                                final selected = selectedIndex == i;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(22),

                                  onTap: () {
                                    setState(() {
                                      selectedIndex = i;
                                    });
                                  },

                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),

                                    padding: const EdgeInsets.all(20),

                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFFFFF8DB)
                                          : AppColors.surfaceAlt,

                                      borderRadius: BorderRadius.circular(22),

                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),

                                    child: Row(
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,

                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,

                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),

                                          child: Center(
                                            child: Text(
                                              c.nombre
                                                  .substring(0, 1)
                                                  .toUpperCase(),

                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                                color: AppColors.primaryDarker,
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 16),

                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,

                                            children: [
                                              Text(
                                                c.nombre,

                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),

                                              const SizedBox(height: 6),

                                              Text(
                                                c.direccion ?? "Sin dirección",

                                                maxLines: 1,

                                                overflow: TextOverflow.ellipsis,

                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,

                                          children: [
                                            Text(
                                              c.telefono?.toString() ?? "-",

                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),

                                            const SizedBox(height: 6),

                                            Text(
                                              _formatearFecha(c.fechaRegistro),

                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
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

              const SizedBox(width: 20),

              // 🔥 PANEL DERECHO
              Expanded(
                flex: 3,

                child: Container(
                  padding: const EdgeInsets.all(24),

                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,

                    borderRadius: BorderRadius.circular(28),

                    border: Border.all(color: AppColors.border),
                  ),

                  child:
                      selectedIndex == null || selectedIndex! >= clientes.length
                      ? const Center(
                          child: Text(
                            "Selecciona un cliente",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : _detalleClienteModern(clientes[selectedIndex!]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // DETALLE MODERNO
  Widget _detalleClienteModern(Cliente c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,

              decoration: BoxDecoration(
                color: AppColors.primaryLight,

                borderRadius: BorderRadius.circular(20),
              ),

              child: Center(
                child: Text(
                  c.nombre.substring(0, 1).toUpperCase(),

                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDarker,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    c.nombre,

                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    c.correo ?? "Sin correo registrado",

                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        _infoModern(Icons.location_on_outlined, "Dirección", c.direccion),

        _infoModern(Icons.phone_outlined, "Teléfono", c.telefono?.toString()),

        _infoModern(Icons.email_outlined, "Correo", c.correo),

        _infoModern(
          Icons.calendar_month_outlined,
          "Registro",
          _formatearFecha(c.fechaRegistro),
        ),

        const Spacer(),

        SizedBox(
          width: double.infinity,
          height: 54,

          child: ElevatedButton.icon(
            onPressed: () {
              final cliente = clientes[selectedIndex!];

              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VentasView(cliente: cliente)),
              );
            },

            icon: const Icon(Icons.point_of_sale),

            label: const Text("Nueva Venta"),

            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,

              foregroundColor: Colors.black87,

              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 52,

          child: OutlinedButton.icon(
            onPressed: () => _mostrarFormulario(cliente: clientes[selectedIndex!]),

            icon: const Icon(Icons.edit_outlined),

            label: const Text("Editar Cliente"),

            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,

              side: const BorderSide(color: AppColors.border),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 52,

          child: ElevatedButton.icon(
  onPressed: () => confirmarAccion(
    context: context,
    tituloConfirmar: "Eliminar cliente",
    mensajeConfirmar: "¿Seguro que deseas eliminar este cliente?",
    iconoConfirmar: Icons.warning_amber_rounded,
    textoConfirmar: "Eliminar",
    accion: () async {
      eliminar(c.idCliente!);
    },
    tituloExito: "Cliente eliminado",
    mensajeExito: "El cliente ha sido eliminado exitosamente.",
  ),

  icon: const Icon(Icons.delete),

  label: const Text("Eliminar Cliente"),

  style: ElevatedButton.styleFrom(
    backgroundColor: const Color(0xFFFFE5E5),

    foregroundColor: Colors.red.shade700,

    elevation: 0,

    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
  ),
),
        ),
      ],
    );
  }

  // INFO ITEM
  Widget _infoModern(IconData icon, String title, String? value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(18),
      ),

      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 20),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value ?? "-",

                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FECHA
  String _formatearFecha(String? fecha) {
    if (fecha == null) return "-";

    final date = DateTime.tryParse(fecha);
    if (date == null) return fecha;

    return "${date.day}/${date.month}/${date.year}";
  }
}
