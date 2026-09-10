import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/mensaje_error.dart';
import '../controllers/categoria_controller.dart';
import '../models/categoria_model.dart';
import '../widgets/nav_bar.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/toast.dart';

class CategoriasView extends StatefulWidget {
  const CategoriasView({super.key});

  @override
  State<CategoriasView> createState() => _CategoriasViewState();
}

class _CategoriasViewState extends State<CategoriasView> {
  final controller = CategoriaController();

  /// Campo de alta rápida del encabezado. Existía en pantalla desde siempre
  /// pero sin controlador ni acción: era decorativo. Quien escribía ahí el
  /// nombre y presionaba Enter no obtenía nada, y lo intentaba dos o tres
  /// veces antes de encontrar el botón que sí abre el formulario.
  final _nuevaCtrl = TextEditingController();
  final _nuevaFoco = FocusNode();

  List<Categoria> categorias = [];

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    _nuevaFoco.dispose();
    super.dispose();
  }

  /// Alta desde el campo del encabezado. Deja el foco donde está y limpia el
  /// campo, porque las categorías se dan de alta en tandas: al montar la
  /// tienda se capturan diez seguidas, y abrir un diálogo para cada una es
  /// diez veces el mismo viaje.
  Future<void> _altaRapida() async {
    final nombre = _nuevaCtrl.text.trim();
    if (nombre.isEmpty) return;

    try {
      await controller.insertar(Categoria(nombre: nombre));
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, mensajeDeError(e));
      return;
    }

    if (!mounted) return;
    _nuevaCtrl.clear();
    _nuevaFoco.requestFocus();
    cargar();
    Toast.exito(context, 'Categoría "$nombre" agregada');
  }

  void cargar() async {
    try {
      final data = await controller.obtenerTodos();

      if (!mounted) return;

      setState(() {
        categorias = data;
      });
    } catch (e) {
      // Sin este `catch`, un fallo de la consulta se tragaba en silencio: la
      // lista quedaba vacía y la pantalla decía "no hay nada registrado", que
      // es distinto de "no se pudo leer". Alguien daba de alta un registro que
      // ya existía.
      if (!mounted) return;
      Toast.error(context, mensajeDeError(e));
    }
  }

  /// Devuelve un `Future` a propósito: `confirmarAccion` lo espera para saber
  /// si de verdad se borró, y ya traduce y muestra el rechazo por llave
  /// foránea. Con `void ... async` el aviso de éxito salía antes de que la
  /// base respondiera, aunque el borrado se hubiera rechazado.
  Future<void> eliminar(int id) async {
    await controller.eliminar(id);
    cargar();
  }

  void mostrarFormulario({Categoria? categoria}) {
    final ctrl = TextEditingController();

    if (categoria != null) {
      ctrl.text = categoria.nombre;
    }

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: categoria == null ? "Nueva categoría" : "Editar categoría",
        subtitulo: "Complete la información de la categoría",
        campos: [
          AppTextField(controller: ctrl, hint: "Nombre de categoría"),
        ],
        onGuardar: () async {
          if (ctrl.text.trim().isEmpty) {
            showDialog(
              context: context,
              builder: (_) => const CustomAlert(
                titulo: "Falta el nombre",
                mensaje: "Escribe el nombre de la categoría para continuar.",
                icono: Icons.warning_amber_rounded,
                textoConfirmar: "Entendido",
              ),
            );
            return;
          }

          final nueva = Categoria(
            idCategoria: categoria?.idCategoria,
            nombre: ctrl.text.trim(),
          );

          try {
            if (categoria == null) {
              await controller.insertar(nueva);
            } else {
              await controller.actualizar(nueva);
            }
          } catch (e) {
            if (!mounted) return;
            Toast.error(context, mensajeDeError(e));
            return; // el diálogo sigue abierto para corregir el nombre
          }

          if (!mounted) return;
          Navigator.pop(context);
          cargar();

          Toast.exito(
            context,
            categoria == null ? "Categoría agregada" : "Categoría actualizada",
          );
        },
      ),
    ).whenComplete(() {
      // Creados por esta función, no por un State: sin esto no se
      // liberan nunca (tampoco si el diálogo se descarta sin guardar).
      ctrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Categorías", mostrarVolver: true),

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
              const Text(
                "Gestión de categorías",

                style: TextStyle(
                  fontSize: AppText.display,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Administre las categorías disponibles dentro del sistema",

                style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
              ),

              const SizedBox(height: 28),

              Wrap(
                spacing: 14,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,

                children: [
                  SizedBox(
                    width: 320,

                    child: TextField(
                      controller: _nuevaCtrl,
                      focusNode: _nuevaFoco,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _altaRapida(),
                      decoration: InputDecoration(
                        hintText: "Nueva categoría y Enter",

                        prefixIcon: const Icon(Icons.category_outlined),

                        filled: true,
                        fillColor: AppColors.surface,

                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  ElevatedButton.icon(
                    onPressed: mostrarFormulario,

                    icon: const Icon(Icons.add),

                    label: const Text("Agregar categoría"),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,

                      foregroundColor: AppColors.onPrimary,

                      elevation: 0,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              Expanded(
                child: categorias.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,

                          children: const [
                            Icon(
                              Icons.category_outlined,
                              size: 52,
                              color: Color(0xFFC8C2B8),
                            ),

                            SizedBox(height: 14),

                            Text(
                              "No hay categorías registradas",

                              style: TextStyle(
                                fontSize: AppText.bodyLg,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        itemCount: categorias.length,

                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 18,
                              mainAxisSpacing: 18,
                              childAspectRatio: 2.7,
                            ),

                        itemBuilder: (_, i) {
                          final c = categorias[i];

                          return Container(
                            padding: const EdgeInsets.all(20),

                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,

                              borderRadius: BorderRadius.circular(AppRadius.lg),

                              border: Border.all(
                                color: AppColors.border,
                              ),
                            ),

                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,

                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLighter,

                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                  ),

                                  child: Icon(
                                    Icons.category_outlined,
                                    color: AppColors.primaryDarker,
                                  ),
                                ),

                                const SizedBox(width: 16),

                                Expanded(
                                  child: Text(
                                    c.nombre,

                                    style: const TextStyle(
                                      fontSize: AppText.bodyLg,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),

                                PopupMenuButton(
                                  color: Colors.white,

                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      onTap: () =>
                                          mostrarFormulario(categoria: c),

                                      child: const Text("Editar"),
                                    ),

                                    PopupMenuItem(
                                      onTap: () {
                                        Future.delayed(Duration.zero, () {
                                          if (!context.mounted) return;
                                          confirmarAccion(
                                            context: context,
                                            tituloConfirmar: "Eliminar categoría",
                                            mensajeConfirmar:
                                                "¿Seguro que deseas eliminar esta categoría?",
                                            iconoConfirmar: Icons.warning_amber_rounded,
                                            textoConfirmar: "Eliminar",
                                            accion: () => eliminar(c.idCategoria!),
                                            tituloExito: "Categoría eliminada",
                                            mensajeExito:
                                                "La categoría ha sido eliminada exitosamente.",
                                          );
                                        });
                                      },

                                      child: const Text("Eliminar"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
