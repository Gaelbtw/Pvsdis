import 'package:flutter/material.dart';
import '../controllers/categoria_controller.dart';
import '../models/categoria_model.dart';
import '../widgets/nav_bar.dart';
import '../widgets/custom_alert.dart';

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
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFFFAF8F4),

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),

        child: Container(
          width: 420,

          padding: const EdgeInsets.all(28),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                categoria == null ? "Nueva categoría" : "Editar categoría",

                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D2B28),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Complete la información de la categoría",

                style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
              ),

              const SizedBox(height: 24),

              TextField(
                controller: ctrl,

                decoration: InputDecoration(
                  hintText: "Nombre de categoría",

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
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,

                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),

                    child: const Text(
                      "Cancelar",

                      style: TextStyle(color: Colors.black87),
                    ),
                  ),

                  const SizedBox(width: 12),

                  ElevatedButton(
                    onPressed: () async {
                      if (ctrl.text.trim().isEmpty){
                        showDialog(
                          context: context,
                          builder: (_) => const CustomAlert(
                            titulo: "Campo vacío",
                            mensaje: "El nombre de la categoría no puede estar vacío.",
                            icono: Icons.warning_amber_rounded,
                            textoConfirmar: "Aceptar",
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

                      Navigator.pop(context);

                      cargar();

                      showDialog(
                        context: context,
                        builder: (_) => CustomAlert(
                          titulo: categoria == null
                              ? "Categoría agregada"
                              : "Categoría actualizada",

                          mensaje: categoria == null
                              ? "La categoría ha sido agregada exitosamente."
                              : "La categoría ha sido actualizada exitosamente.",

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

                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

      appBar: CustomHeader(titulo: "Categorías", mostrarVolver: true),

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
              const Text(
                "Gestión de categorías",

                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D2B28),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Administre las categorías disponibles dentro del sistema",

                style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
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
                        fillColor: const Color(0xFFF8F6F2),

                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
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
                      backgroundColor: const Color(0xFFF2C500),

                      foregroundColor: Colors.black87,

                      elevation: 0,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6E6A64),
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
                              color: const Color(0xFFFCFBF9),

                              borderRadius: BorderRadius.circular(24),

                              border: Border.all(
                                color: const Color(0xFFF0EBE5),
                              ),
                            ),

                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,

                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7D6),

                                    borderRadius: BorderRadius.circular(16),
                                  ),

                                  child: const Icon(
                                    Icons.category_outlined,
                                    color: Color(0xFFB27B00),
                                  ),
                                ),

                                const SizedBox(width: 16),

                                Expanded(
                                  child: Text(
                                    c.nombre,

                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2D2B28),
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
                                          showDialog(
                                            context: context,
                                            builder: (_) => CustomAlert(
                                              titulo: "Eliminar categoria",
                                              mensaje:
                                                  "¿Seguro que deseas eliminar esta categoria?",
                                              icono:
                                                  Icons.warning_amber_rounded,
                                              textoConfirmar: "Eliminar",

                                              onConfirm: () async {
                                                eliminar(c.idCategoria!);

                                                //Navigator.pop(context);

                                                showDialog(
                                                  context: context,
                                                  builder: (_) => CustomAlert(
                                                    titulo:
                                                        "Categoría eliminada",
                                                    mensaje:
                                                        "La categoría ha sido eliminada exitosamente.",
                                                    icono: Icons
                                                        .check_circle_outline,
                                                    textoConfirmar: "Aceptar",

                                                    onConfirm: () {
                                                  
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
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
