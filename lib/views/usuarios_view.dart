import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/mensaje_error.dart';
import '../controllers/usuarios_controller.dart';
import '../core/security/password_hasher.dart';
import '../core/security/permisos.dart';
import '../core/session/session_manager.dart';
import '../models/usuarios_model.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/toast.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';
import 'permisos_view.dart';
import '../core/security/permisos_service.dart';

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

    // Sin esta guarda, salir de Usuarios mientras la consulta está en vuelo
    // provoca "setState() called after dispose()".
    if (!mounted) return;

    setState(() {
      usuarios = usr;
      _nombresBusqueda = [for (final u in usr) u.nombre.toLowerCase()];
      _recalcularFiltro();
    });
  }

  // 🔥 FILTRO
  //
  // Campo, no getter: se consumía en `isEmpty`, `length` y dentro del
  // `itemBuilder`, así que recorría la lista completa una vez por fila
  // dibujada.
  List<Usuarios> _filtrados = const [];
  List<String> _nombresBusqueda = const [];

  void _recalcularFiltro() {
    final consulta = busqueda.trim().toLowerCase();

    if (consulta.isEmpty) {
      _filtrados = usuarios;
      return;
    }

    _filtrados = [
      for (var i = 0; i < usuarios.length; i++)
        if (_nombresBusqueda[i].contains(consulta)) usuarios[i],
    ];
  }

  // 🔥 FORMULARIO
 void mostrarFormularioUsuario({Usuarios? usuario}) {
  final nombreCtrl = TextEditingController(
    text: usuario?.nombre ?? "",
  );

  // Nunca se prellena: el valor guardado ya es un hash, no la contraseña
  // real. Al editar, dejarlo vacío significa "no cambiar la contraseña".
  final contraCtrl = TextEditingController();

  // Igual que la contraseña: nunca se prellena (se guarda hasheado). En blanco
  // al editar = no tocar el PIN.
  final pinCtrl = TextEditingController();

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
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: rolSeleccionado,
                decoration: const InputDecoration(border: InputBorder.none),
                items: Roles.todos
                    .map((r) => DropdownMenuItem(value: r, child: Text(SessionManager.etiquetaRol(r))))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() {
                    rolSeleccionado = value;
                  });
                },
              ),
            ),
            AppTextField(
              controller: pinCtrl,
              hint: usuario == null
                  ? "PIN (opcional, 4 a 6 dígitos)"
                  : "PIN (en blanco = sin cambios)",
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
          ],
          onGuardar: () async {
            void mostrarError(String mensaje) => Toast.error(context, mensaje);

            if (nombreCtrl.text.trim().isEmpty) {
              mostrarError("Escribe el nombre de usuario.");
              return;
            }

            // El login busca por nombre (sin distinguir mayúsculas) y se
            // queda con la primera coincidencia: dos cuentas homónimas
            // dejarían a una de ellas sin poder entrar nunca.
            if (await usuariosController.nombreEnUso(
              nombreCtrl.text,
              exceptoId: usuario?.idUsuario,
            )) {
              mostrarError("Ya existe un usuario con ese nombre. Elige otro.");
              return;
            }

            // Al crear, la contraseña es obligatoria. Al
            // editar, puede quedar vacía (no se cambia).
            if (usuario == null && contraCtrl.text.isEmpty) {
              mostrarError("Escribe la contraseña.");
              return;
            }

            if (contraCtrl.text.isNotEmpty) {
              final errorPolitica = PasswordHasher.validate(contraCtrl.text);
              if (errorPolitica != null) {
                mostrarError(errorPolitica);
                return;
              }
            }

            // PIN opcional: si se escribió, debe ser 4-6 dígitos y no estar ya
            // en uso por otro usuario (permite el login rápido por PIN).
            final pinIngresado = pinCtrl.text.trim();
            if (pinIngresado.isNotEmpty) {
              final errorPin = validarPin(pinIngresado);
              if (errorPin != null) {
                mostrarError(errorPin);
                return;
              }
              if (await usuariosController.pinEnUso(pinIngresado, exceptoId: usuario?.idUsuario)) {
                mostrarError("Ese PIN ya lo usa otro usuario. Elige otro.");
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
              pin: pinIngresado.isEmpty ? null : pinIngresado,
            );

            try {
              if (usuario == null) {
                await usuariosController.insertar(nuevo);
              } else {
                await usuariosController.actualizar(
                  nuevo,
                  nuevaContrasena: contraCtrl.text.isEmpty ? null : contraCtrl.text,
                  // En blanco = no tocar el PIN existente.
                  nuevoPin: pinIngresado.isEmpty ? null : pinIngresado,
                );
              }
            } catch (e) {
              // Red de seguridad ante una carrera: las validaciones de nombre
              // y PIN de arriba consultan la base ANTES de guardar, así que
              // dos altas simultáneas podrían pasarlas y chocar aquí contra
              // el índice único.
              if (!context.mounted) return;
              Toast.error(context, mensajeDeError(e));
              return;
            }

            if (!context.mounted) return;
            Navigator.pop(context);
            cargarTodo();

            Toast.exito(
              context,
              usuario == null ? "Usuario agregado" : "Usuario actualizado",
            );
          },
        );
      },
    ),
  ).whenComplete(() {
    // Creados por esta función (no por un State), así que no hay dispose()
    // automático: hay que liberarlos al cerrar el diálogo, incluso si se
    // descartó sin guardar. El de la contraseña, además, deja de mantener
    // el texto en claro en memoria.
    nombreCtrl.dispose();
    contraCtrl.dispose();
    pinCtrl.dispose();
  });
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
      // Un usuario con ventas o cortes de caja a su nombre no se puede
      // borrar (FK RESTRICT): su rastro contable debe seguir existiendo.
      await usuariosController.eliminar(u.idUsuario!);
      cargarTodo();
    },
    tituloExito: "Usuario eliminado",
    mensajeExito: "El usuario ha sido eliminado exitosamente.",
  );
}
  @override
  Widget build(BuildContext context) {
    // Defensa en profundidad: hoy solo se llega aquí desde Configuración
    // (que ya exige su propio permiso), pero administrar cuentas es una
    // acción sensible y no debe depender de por dónde se navegó.
    if (!PermisosService.instancia.puedeActual(Permiso.gestionarUsuarios)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: CustomHeader(titulo: "Usuarios", mostrarVolver: true, mostrarInfo: false),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "No tienes permiso para administrar usuarios.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.body),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Usuarios", mostrarVolver: true),

      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),

        child: Container(
          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(AppRadius.pill),

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
                            fontSize: AppText.display,

                            fontWeight: FontWeight.w800,

                            color: AppColors.textPrimary,
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          "Administre usuarios y permisos del sistema",

                          style: TextStyle(
                            color: AppColors.textSecondary,

                            fontSize: AppText.small,
                          ),
                        ),
                      ],
                    ),
                  ),

                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PermisosView()),
                    ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text("Permisos por rol"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(color: AppColors.primaryDark, width: 1.4),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

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
                        borderRadius: BorderRadius.circular(AppRadius.md),
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
                  onChanged: (v) => setState(() {
                    busqueda = v;
                    _recalcularFiltro();
                  }),

                  decoration: InputDecoration(
                    hintText: "Buscar usuario...",

                    prefixIcon: const Icon(Icons.search),

                    filled: true,

                    fillColor: AppColors.surface,

                    contentPadding: const EdgeInsets.symmetric(vertical: 14),

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),

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
                child: _filtrados.isEmpty
                    ? const Center(child: Text("No hay usuarios registrados"))
                    : ListView.separated(
                        itemCount: _filtrados.length,

                        separatorBuilder: (_, _) => const Divider(height: 1),

                        itemBuilder: (_, i) {
                          final u = _filtrados[i];

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

                color: AppColors.textStrong,

                fontSize: AppText.caption,
              ),
            ),
          ),

          Expanded(
            flex: 3,

            child: Text(
              "ROL",

              style: TextStyle(
                fontWeight: FontWeight.w800,

                color: AppColors.textStrong,

                fontSize: AppText.caption,
              ),
            ),
          ),

          Expanded(
            flex: 3,

            child: Text(
              "ACCIONES",

              style: TextStyle(
                fontWeight: FontWeight.w800,

                color: AppColors.textStrong,

                fontSize: AppText.caption,
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

                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),

                  child: Center(
                    child: Text(
                      u.nombre.substring(0, 1).toUpperCase(),

                      style: TextStyle(
                        fontWeight: FontWeight.w800,

                        fontSize: AppText.subtitle,

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

                    fontSize: AppText.body,
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

                borderRadius: BorderRadius.circular(AppRadius.md),
              ),

              child: Text(
                SessionManager.etiquetaRol(u.rol),

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

