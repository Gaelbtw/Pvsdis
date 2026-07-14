import 'package:flutter/material.dart';
import '../views/ventas_view.dart';
//import 'package:punto_de_venta_lomita/views/ventas_view.dart';
import '../controllers/cliente_controller.dart';
import '../models/cliente_model.dart';
import '../widgets/nav_bar.dart';

import '../widgets/custom_alert.dart';

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

  // FORMULARIO MODAL
  void _mostrarFormulario() {
  final nombreCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final correoCtrl = TextEditingController();

  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFFFAF8F4),

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),

      child: Container(
        width: 520,

        padding: const EdgeInsets.all(28),

        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: Color(0xFFB27B00),
                    size: 28,
                  ),

                  SizedBox(width: 10),

                  Text(
                    "Nuevo Cliente",

                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2D2B28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                "Complete la información del cliente",

                style: TextStyle(
                  color: Color(0xFF6E6A64),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 24),

              _input(nombreCtrl, "Nombre"),

              const SizedBox(height: 16),

              _input(direccionCtrl, "Dirección"),

              const SizedBox(height: 16),

              _input(
                telefonoCtrl,
                "Teléfono",
                keyboard: TextInputType.phone,
              ),

              const SizedBox(height: 16),

              _input(
                correoCtrl,
                "Correo",
                keyboard: TextInputType.emailAddress,
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,

                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),

                    child: const Text(
                      "Cancelar",

                      style: TextStyle(
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  ElevatedButton(
                    onPressed: () async {

                      if (nombreCtrl.text.trim().isEmpty) {
                        showDialog(
                          context: context,
                          builder: (_) => CustomAlert(
                            titulo: "Error",
                            mensaje: "El nombre es obligatorio.",
                            icono: Icons.error_outline,
                            textoConfirmar: "Aceptar",

                            onConfirm: () {
                            },
                          )
                        );
                        return; 
                      }

                      await controller.insertar(
                        Cliente(
                          idCliente: null,
                          nombre: nombreCtrl.text,
                          direccion: direccionCtrl.text,
                          telefono: int.tryParse(
                            telefonoCtrl.text,
                          ),
                          correo: correoCtrl.text,
                          fechaRegistro:
                              DateTime.now().toIso8601String(),
                        ),
                      );

                      Navigator.pop(context);

                      cargar();

                      showDialog(
                        context: context,
                        builder: (_) => CustomAlert(
                          titulo: "Cliente agregado",
                          mensaje:
                              "El cliente ha sido agregado exitosamente.",
                          icono: Icons.check_circle_outline,
                          textoConfirmar: "Aceptar",

                          onConfirm: () {
                          },
                        ),
                      );
                    },

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF2C500),

                      foregroundColor: Colors.black87,

                      elevation: 0,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    child: const Text(
                      "Guardar",

                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _mostrarFormularioEditar(Cliente cliente) {
  final nombreCtrl = TextEditingController(text: cliente.nombre);

  final direccionCtrl = TextEditingController(
    text: cliente.direccion,
  );

  final telefonoCtrl = TextEditingController(
    text: cliente.telefono?.toString(),
  );

  final correoCtrl = TextEditingController(
    text: cliente.correo,
  );

  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: const Color(0xFFFAF8F4),

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),

      child: Container(
        width: 520,

        padding: const EdgeInsets.all(28),

        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const Row(
                children: [
                  Icon(
                    Icons.edit_outlined,
                    color: Color(0xFFB27B00),
                    size: 28,
                  ),

                  SizedBox(width: 10),

                  Text(
                    "Editar Cliente",

                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2D2B28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                "Actualice la información del cliente",

                style: TextStyle(
                  color: Color(0xFF6E6A64),
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 24),

              _input(nombreCtrl, "Nombre"),

              const SizedBox(height: 16),

              _input(direccionCtrl, "Dirección"),

              const SizedBox(height: 16),

              _input(
                telefonoCtrl,
                "Teléfono",
                keyboard: TextInputType.phone,
              ),

              const SizedBox(height: 16),

              _input(
                correoCtrl,
                "Correo",
                keyboard: TextInputType.emailAddress,
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,

                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),

                    child: const Text(
                      "Cancelar",

                      style: TextStyle(
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  ElevatedButton(
                    onPressed: () async {
                      await controller.actualizar(
                        Cliente(
                          idCliente: cliente.idCliente,
                          nombre: nombreCtrl.text,
                          direccion: direccionCtrl.text,
                          telefono: int.tryParse(
                            telefonoCtrl.text,
                          ),
                          correo: correoCtrl.text,
                          fechaRegistro:
                              DateTime.now().toIso8601String(),
                        ),
                      );

                      Navigator.pop(context);

                      cargar();

                      showDialog(
                        context: context,
                        builder: (_) => CustomAlert(
                          titulo: "Cliente actualizado",
                          mensaje:
                              "El cliente ha sido actualizado exitosamente.",
                          icono: Icons.check_circle_outline,
                          textoConfirmar: "Aceptar",

                          onConfirm: () {
                          },
                        ),
                      );
                    },

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF2C500),

                      foregroundColor: Colors.black87,

                      elevation: 0,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    child: const Text(
                      "Guardar",

                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

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
                        color: Color(0xFF2D2B28),
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Administre clientes registrados y genere ventas rápidamente",

                      style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
                    ),

                    const SizedBox(height: 24),

                    // 🔥 MÉTRICAS
                    Row(
                      children: [
                        _statModern(
                          "Clientes",
                          clientes.length.toString(),
                          Icons.people_alt_outlined,
                        ),

                        const SizedBox(width: 14),

                        _statModern(
                          "Con teléfono",
                          clientes
                              .where((c) => c.telefono != null)
                              .length
                              .toString(),
                          Icons.phone_outlined,
                        ),

                        const SizedBox(width: 14),

                        _statModern(
                          "Con correo",
                          clientes
                              .where((c) => c.correo != null)
                              .length
                              .toString(),
                          Icons.email_outlined,
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

                              fillColor: const Color(0xFFF8F6F2),

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
                            backgroundColor: const Color(0xFFF2C500),

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
                                          : const Color(0xFFFCFBF9),

                                      borderRadius: BorderRadius.circular(22),

                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFFF2C500)
                                            : const Color(0xFFF0EBE5),
                                      ),
                                    ),

                                    child: Row(
                                      children: [
                                        Container(
                                          width: 52,
                                          height: 52,

                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF1BF),

                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),

                                          child: Center(
                                            child: Text(
                                              c.nombre
                                                  .substring(0, 1)
                                                  .toUpperCase(),

                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                                color: Color(0xFFB27B00),
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
                                                  color: Color(0xFF2D2B28),
                                                ),
                                              ),

                                              const SizedBox(height: 6),

                                              Text(
                                                c.direccion ?? "Sin dirección",

                                                maxLines: 1,

                                                overflow: TextOverflow.ellipsis,

                                                style: const TextStyle(
                                                  color: Color(0xFF6F6A63),
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
                                                color: Color(0xFF8A847D),
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
                    color: const Color(0xFFFCFBF9),

                    borderRadius: BorderRadius.circular(28),

                    border: Border.all(color: const Color(0xFFF0EBE5)),
                  ),

                  child:
                      selectedIndex == null || selectedIndex! >= clientes.length
                      ? const Center(
                          child: Text(
                            "Selecciona un cliente",
                            style: TextStyle(color: Color(0xFF6E6A64)),
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
                color: const Color(0xFFFFF1BF),

                borderRadius: BorderRadius.circular(20),
              ),

              child: Center(
                child: Text(
                  c.nombre.substring(0, 1).toUpperCase(),

                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB27B00),
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
                      color: Color(0xFF2D2B28),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    c.correo ?? "Sin correo registrado",

                    style: const TextStyle(color: Color(0xFF6F6A63)),
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
              backgroundColor: const Color(0xFFF2C500),

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
            onPressed: () => _mostrarFormularioEditar(clientes[selectedIndex!]),

            icon: const Icon(Icons.edit_outlined),

            label: const Text("Editar Cliente"),

            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,

              side: const BorderSide(color: Color(0xFFE5DED3)),

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
  onPressed: () {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Eliminar cliente",

        mensaje:
            "¿Seguro que deseas eliminar este cliente?",

        icono: Icons.warning_amber_rounded,

        textoConfirmar: "Eliminar",

        onConfirm: () async {
          eliminar(c.idCliente!);

          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: "Cliente eliminado",

              mensaje:
                  "El cliente ha sido eliminado exitosamente.",

              icono: Icons.check_circle_outline,

              textoConfirmar: "Aceptar",

              onConfirm: () {
              },
            ),
          );
        },
      ),
    );
  },

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
          Icon(icon, color: const Color(0xFFCC9600), size: 20),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A847D),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  value ?? "-",

                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D2B28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MÉTRICAS MODERNAS
  Widget _statModern(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),

        decoration: BoxDecoration(
          color: const Color(0xFFFCFBF9),

          borderRadius: BorderRadius.circular(24),

          border: Border.all(color: const Color(0xFFF0EBE5)),
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Container(
              width: 42,
              height: 42,

              decoration: BoxDecoration(
                color: const Color(0xFFFFF4CC),

                borderRadius: BorderRadius.circular(14),
              ),

              child: Icon(icon, color: const Color(0xFFB88300)),
            ),

            const SizedBox(height: 16),

            Text(
              title,

              style: const TextStyle(color: Color(0xFF8A847D), fontSize: 13),
            ),

            const SizedBox(height: 8),

            Text(
              value,

              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2D2B28),
              ),
            ),
          ],
        ),
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

// inputs 
Widget _input(
  TextEditingController controller,
  String hint, {
  int maxLines = 1,
  TextInputType keyboard = TextInputType.text,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboard,

    decoration: InputDecoration(
      hintText: hint,

      filled: true,
      fillColor: Colors.white,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
