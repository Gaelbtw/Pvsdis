import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
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

  List<Categoria> categorias = [];

  @override
  void initState() {
    super.initState();
    cargar();
  }

  void cargar() async {
    final data = await controller.obtenerTodos();

    setState(() {
      categorias = data;
    });
  }

  void eliminar(int id) async {
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

          if (categoria == null) {
            await controller.insertar(nueva);
          } else {
            await controller.actualizar(nueva);
          }

          if (!context.mounted) return;
          Navigator.pop(context);
          cargar();

          Toast.exito(
            context,
            categoria == null ? "Categoría agregada" : "Categoría actualizada",
          );
        },
      ),
    );
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
                      decoration: InputDecoration(
                        hintText: "Nueva categoría",

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

                      foregroundColor: Colors.black87,

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
                                          confirmarAccion(
                                            context: context,
                                            tituloConfirmar: "Eliminar categoria",
                                            mensajeConfirmar:
                                                "¿Seguro que deseas eliminar esta categoria?",
                                            iconoConfirmar: Icons.warning_amber_rounded,
                                            textoConfirmar: "Eliminar",
                                            accion: () async {
                                              eliminar(c.idCategoria!);
                                            },
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
