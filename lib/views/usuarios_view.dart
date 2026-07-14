import 'package:flutter/material.dart';
import '../controllers/usuarios_controller.dart';
import '../models/usuarios_model.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';

class UsuariosView extends StatefulWidget {
  const UsuariosView({super.key});

  @override
  State<UsuariosView> createState() => _UsuariosViewState();
}

class _UsuariosViewState extends State<UsuariosView> {
  final usuariosController = UsuariosController();

  List<Usuarios> usuarios = [];

  String busqueda = "";

  @override
  void initState() {
    super.initState();
    cargarTodo();
  }

  void cargarTodo() async {
    final usr = await usuariosController.obtenerTodos();

    setState(() {
      usuarios = usr;
    });
  }

  // 🔥 FILTRO
  List<Usuarios> get filtrados {
    return usuarios.where((u) {
      return u.nombre.toLowerCase().contains(busqueda.toLowerCase());
    }).toList();
  }

  // 🔥 FORMULARIO
 void mostrarFormularioUsuario({Usuarios? usuario}) {
  final nombreCtrl = TextEditingController(
    text: usuario?.nombre ?? "",
  );

  final contraCtrl = TextEditingController(
    text: usuario?.contra ?? "",
  );

  String rolSeleccionado = usuario?.rol ?? "Cajero";

  showDialog(
    context: context,

    builder: (_) => StatefulBuilder(
      builder: (context, setModalState) {
        return Dialog(
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
                  Text(
                    usuario == null
                        ? "Nuevo Usuario"
                        : "Editar Usuario",

                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2D2B28),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    usuario == null
                        ? "Complete la información del usuario"
                        : "Actualice la información del usuario",

                    style: const TextStyle(
                      color: Color(0xFF6E6A64),
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 24),

                  _inputFormulario(
                    controller: nombreCtrl,
                    label: "Nombre de usuario",
                  ),

                  const SizedBox(height: 16),

                  _inputFormulario(
                    controller: contraCtrl,
                    label: "Contraseña",
                  ),

                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: DropdownButtonFormField<String>(
                      value: rolSeleccionado,

                      decoration: const InputDecoration(
                        border: InputBorder.none,
                      ),

                      items: ["Admin", "Cajero"]
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r),
                            ),
                          )
                          .toList(),

                      onChanged: (value) {
                        if (value == null) return;

                        setModalState(() {
                          rolSeleccionado = value;
                        });
                      },
                    ),
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
                          if (nombreCtrl.text.isEmpty ||
                              contraCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Completa todos los campos",
                                ),
                              ),
                            );

                            return;
                          }

                          final nuevo = Usuarios(
                            idUsuario: usuario?.idUsuario,

                            nombre: nombreCtrl.text,

                            contra: contraCtrl.text,

                            rol: rolSeleccionado,
                          );

                          if (usuario == null) {
                            await usuariosController.insertar(nuevo);
                          } else {
                            await usuariosController.actualizar(nuevo);
                          }

                          Navigator.pop(context);

                          cargarTodo();

                          showDialog(
                            context: context,

                            builder: (_) => CustomAlert(
                              titulo: usuario == null
                                  ? "Usuario agregado"
                                  : "Usuario actualizado",

                              mensaje: usuario == null
                                  ? "El usuario ha sido agregado exitosamente."
                                  : "El usuario ha sido actualizado exitosamente.",

                              icono: Icons.check_circle_outline,

                              textoConfirmar: "Aceptar",

                              onConfirm: () {
                                Navigator.pop(context);
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
        );
      },
    ),
  );
}

  // 🔥 ELIMINAR
 void confirmarEliminar(Usuarios u) {
  showDialog(
    context: context,

    builder: (_) => CustomAlert(
      titulo: "Eliminar Usuario",

      mensaje: "¿Desea eliminar a ${u.nombre}?",

      icono: Icons.delete_outline,

      textoConfirmar: "Eliminar",


      onConfirm: () async {
        Navigator.pop(context);

        await usuariosController.eliminar(
          u.idUsuario!,
        );

        cargarTodo();

        showDialog(
          context: context,

          builder: (_) => CustomAlert(
            titulo: "Usuario eliminado",

            mensaje:
                "El usuario ha sido eliminado exitosamente.",

            icono: Icons.check_circle_outline,

            textoConfirmar: "Aceptar",

            onConfirm: () {
              Navigator.pop(context);
            },
          ),
        );
      },
    ),
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

      appBar: CustomHeader(titulo: "Usuarios", mostrarVolver: true),

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

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // 🔥 HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: const [
                        Text(
                          "Gestión de Usuarios",

                          style: TextStyle(
                            fontSize: 28,

                            fontWeight: FontWeight.w800,

                            color: Color(0xFF2D2B28),
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          "Administre usuarios y permisos del sistema",

                          style: TextStyle(
                            color: Color(0xFF6E6A64),

                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton.icon(
                    onPressed: () => mostrarFormularioUsuario(),

                    icon: const Icon(Icons.person_add),

                    label: const Text("Nuevo Usuario"),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF2C500),

                      foregroundColor: Colors.black87,

                      elevation: 0,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 🔥 BUSCADOR
              SizedBox(
                width: 320,

                child: TextField(
                  onChanged: (v) => setState(() => busqueda = v),

                  decoration: InputDecoration(
                    hintText: "Buscar usuario...",

                    prefixIcon: const Icon(Icons.search),

                    filled: true,

                    fillColor: const Color(0xFFF8F6F2),

                    contentPadding: const EdgeInsets.symmetric(vertical: 14),

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),

                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 🔥 TABLA
              _headerTabla(),

              const Divider(height: 1),

              Expanded(
                child: filtrados.isEmpty
                    ? const Center(child: Text("No hay usuarios registrados"))
                    : ListView.separated(
                        itemCount: filtrados.length,

                        separatorBuilder: (_, _) => const Divider(height: 1),

                        itemBuilder: (_, i) {
                          final u = filtrados[i];

                          return _filaUsuario(u);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 HEADER TABLA
  Widget _headerTabla() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),

      child: const Row(
        children: [
          Expanded(
            flex: 4,

            child: Text(
              "USUARIO",

              style: TextStyle(
                fontWeight: FontWeight.w800,

                color: Color(0xFF3C3935),

                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            flex: 3,

            child: Text(
              "ROL",

              style: TextStyle(
                fontWeight: FontWeight.w800,

                color: Color(0xFF3C3935),

                fontSize: 12,
              ),
            ),
          ),

          Expanded(
            flex: 3,

            child: Text(
              "ACCIONES",

              style: TextStyle(
                fontWeight: FontWeight.w800,

                color: Color(0xFF3C3935),

                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 FILA
  Widget _filaUsuario(Usuarios u) {
    final esAdmin = u.rol == "Admin";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),

      child: Row(
        children: [
          Expanded(
            flex: 4,

            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,

                  decoration: BoxDecoration(
                    color: esAdmin
                        ? const Color(0xFFFFF1BF)
                        : const Color(0xFFEAEAEA),

                    borderRadius: BorderRadius.circular(14),
                  ),

                  child: Center(
                    child: Text(
                      u.nombre.substring(0, 1).toUpperCase(),

                      style: TextStyle(
                        fontWeight: FontWeight.w800,

                        fontSize: 18,

                        color: esAdmin
                            ? const Color(0xFFB88300)
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                Text(
                  u.nombre,

                  style: const TextStyle(
                    fontWeight: FontWeight.w700,

                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            flex: 3,

            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

              decoration: BoxDecoration(
                color: esAdmin
                    ? const Color(0xFFFFF4CC)
                    : const Color(0xFFF3F3F3),

                borderRadius: BorderRadius.circular(14),
              ),

              child: Text(
                u.rol,

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontWeight: FontWeight.w700,

                  color: esAdmin ? const Color(0xFF9B6A00) : Colors.black87,
                ),
              ),
            ),
          ),

          Expanded(
            flex: 3,

            child: Row(
              children: [
                IconButton(
                  onPressed: () => mostrarFormularioUsuario(usuario: u),

                  icon: const Icon(Icons.edit_outlined),

                  color: Colors.orange.shade800,
                ),

                IconButton(
                  onPressed: () => confirmarEliminar(u),

                  icon: const Icon(Icons.delete_outline),

                  color: Colors.red.shade700,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 INPUT
Widget _inputFormulario({
  required TextEditingController controller,
  required String label,
  int maxLines = 1,
  TextInputType keyboard = TextInputType.text,
}) {
  return TextField(
    controller: controller,
    maxLines: maxLines,
    keyboardType: keyboard,

    decoration: InputDecoration(
      hintText: label,

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
  }

