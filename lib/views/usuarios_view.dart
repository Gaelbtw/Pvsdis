import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../controllers/usuarios_controller.dart';
import '../core/security/password_hasher.dart';
import '../models/usuarios_model.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
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

  // Nunca se prellena: el valor guardado ya es un hash, no la contraseña
  // real. Al editar, dejarlo vacío significa "no cambiar la contraseña".
  final contraCtrl = TextEditingController();

  String rolSeleccionado = usuario?.rol ?? "Cajero";

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setModalState) {
        return FormDialog(
          titulo: usuario == null ? "Nuevo Usuario" : "Editar Usuario",
          subtitulo: usuario == null
              ? "Complete la información del usuario"
              : "Actualice la información del usuario",
          campos: [
            AppTextField(controller: nombreCtrl, hint: "Nombre de usuario"),
            AppTextField(
              controller: contraCtrl,
              hint: usuario == null
                  ? "Contraseña"
                  : "Nueva contraseña (dejar en blanco para no cambiar)",
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonFormField<String>(
                value: rolSeleccionado,
                decoration: const InputDecoration(border: InputBorder.none),
                items: ["Admin", "Cajero"]
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() {
                    rolSeleccionado = value;
                  });
                },
              ),
            ),
          ],
          onGuardar: () async {
            void mostrarError(String mensaje) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(mensaje)),
              );
            }

            if (nombreCtrl.text.trim().isEmpty) {
              mostrarError("El nombre de usuario es obligatorio");
              return;
            }

            // Al crear, la contraseña es obligatoria. Al
            // editar, puede quedar vacía (no se cambia).
            if (usuario == null && contraCtrl.text.isEmpty) {
              mostrarError("La contraseña es obligatoria");
              return;
            }

            if (contraCtrl.text.isNotEmpty) {
              final errorPolitica = PasswordHasher.validate(contraCtrl.text);
              if (errorPolitica != null) {
                mostrarError(errorPolitica);
                return;
              }
            }

            final nuevo = Usuarios(
              idUsuario: usuario?.idUsuario,
              nombre: nombreCtrl.text.trim(),
              // Al editar sin cambiar contraseña este valor se
              // descarta en UsuariosController.actualizar.
              contra: usuario == null ? contraCtrl.text : "",
              rol: rolSeleccionado,
            );

            if (usuario == null) {
              await usuariosController.insertar(nuevo);
            } else {
              await usuariosController.actualizar(
                nuevo,
                nuevaContrasena: contraCtrl.text.isEmpty ? null : contraCtrl.text,
              );
            }

            if (!context.mounted) return;
            Navigator.pop(context);
            cargarTodo();

            showDialog(
              context: context,
              builder: (_) => CustomAlert(
                titulo: usuario == null ? "Usuario agregado" : "Usuario actualizado",
                mensaje: usuario == null
                    ? "El usuario ha sido agregado exitosamente."
                    : "El usuario ha sido actualizado exitosamente.",
                icono: Icons.check_circle_outline,
                textoConfirmar: "Aceptar",
                onConfirm: () {},
              ),
            );
          },
        );
      },
    ),
  );
}

  // 🔥 ELIMINAR
 void confirmarEliminar(Usuarios u) {
  confirmarAccion(
    context: context,
    tituloConfirmar: "Eliminar Usuario",
    mensajeConfirmar: "¿Desea eliminar a ${u.nombre}?",
    iconoConfirmar: Icons.delete_outline,
    textoConfirmar: "Eliminar",
    accion: () async {
      await usuariosController.eliminar(u.idUsuario!);
      cargarTodo();
    },
    tituloExito: "Usuario eliminado",
    mensajeExito: "El usuario ha sido eliminado exitosamente.",
  );
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Usuarios", mostrarVolver: true),

      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),

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

                            color: AppColors.textPrimary,
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          "Administre usuarios y permisos del sistema",

                          style: TextStyle(
                            color: AppColors.textSecondary,

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
                      backgroundColor: AppColors.primary,

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

                    fillColor: AppColors.surface,

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

                color: AppColors.textMuted,

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

                color: AppColors.textMuted,

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

                color: AppColors.textMuted,

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
                        ? AppColors.primaryLight
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
                            ? AppColors.primaryDarker
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
                    ? AppColors.primaryLight
                    : const Color(0xFFF3F3F3),

                borderRadius: BorderRadius.circular(14),
              ),

              child: Text(
                u.rol,

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontWeight: FontWeight.w700,

                  color: esAdmin ? AppColors.primaryDarker : Colors.black87,
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

                  color: AppColors.warning,
                ),

                IconButton(
                  onPressed: () => confirmarEliminar(u),

                  icon: const Icon(Icons.delete_outline),

                  color: AppColors.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

