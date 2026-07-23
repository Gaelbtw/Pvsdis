import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../controllers/proveedor_controller.dart';
import '../models/proveedores_model.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';
import 'proveedor_detalle_view.dart';

class ProveedorView extends StatefulWidget {
  const ProveedorView({super.key});

  @override
  State<ProveedorView> createState() => _ProveedorViewState();
}

class _ProveedorViewState extends State<ProveedorView> {
  final controller = ProveedorController();

  List<Proveedores> proveedores = [];
  List<Proveedores> filtrados = [];

  @override
  void initState() {
    super.initState();
    cargar();
  }

  void cargar() async {
    final data = await controller.obtenerTodos();

    setState(() {
      proveedores = data;
      filtrados = data;
    });
  }

  void buscar(String query) {
    if (query.isEmpty) {
      setState(() => filtrados = proveedores);
      return;
    }

    final resultado = proveedores.where((p) {
      return p.nombre.toLowerCase().contains(query.toLowerCase()) ||
          p.rfc.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() => filtrados = resultado);
  }

  // 🔥 FORMULARIO
void abrirFormulario({Proveedores? proveedor}) {
  final nombreCtrl = TextEditingController(
    text: proveedor?.nombre ?? "",
  );

  final rfcCtrl = TextEditingController(
    text: proveedor?.rfc ?? "",
  );

  final telefonoCtrl = TextEditingController(
    text: proveedor?.telefono ?? "",
  );

  final direccionCtrl = TextEditingController(
    text: proveedor?.direccion ?? "",
  );

  final direccionFiscalCtrl = TextEditingController(
    text: proveedor?.direccionFiscal ?? "",
  );

  showDialog(
    context: context,
    builder: (_) => FormDialog(
      titulo: proveedor == null ? "Nuevo Proveedor" : "Editar Proveedor",
      subtitulo: "Complete la información del proveedor",
      campos: [
        AppTextField(controller: nombreCtrl, hint: "Nombre"),
        AppTextField(controller: rfcCtrl, hint: "RFC"),
        AppTextField(
          controller: telefonoCtrl,
          hint: "Teléfono",
          keyboardType: TextInputType.phone,
        ),
        AppTextField(controller: direccionCtrl, hint: "Dirección"),
        AppTextField(
          controller: direccionFiscalCtrl,
          hint: "Dirección Fiscal",
          maxLines: 3,
        ),
      ],
      onGuardar: () async {
        if (nombreCtrl.text.isEmpty ||
            rfcCtrl.text.isEmpty ||
            telefonoCtrl.text.isEmpty) {
          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: "Campos incompletos",
              mensaje: "Completa los campos obligatorios.",
              icono: Icons.warning_amber_rounded,
              textoConfirmar: "Aceptar",
              onConfirm: () {},
            ),
          );
          return;
        }

        if (telefonoCtrl.text.length < 10) {
          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: "Teléfono inválido",
              mensaje: "El número telefónico no es válido.",
              icono: Icons.warning_amber_rounded,
              textoConfirmar: "Aceptar",
              onConfirm: () {},
            ),
          );
          return;
        }

        final existentes = await controller.obtenerTodos();

        final duplicado = existentes.any(
          (p) =>
              p.nombre.toLowerCase() == nombreCtrl.text.toLowerCase() &&
              p.idProveedor != proveedor?.idProveedor,
        );

        if (duplicado) {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: "Proveedor duplicado",
              mensaje: "Ya existe un proveedor con ese nombre.",
              icono: Icons.warning_amber_rounded,
              textoConfirmar: "Aceptar",
              onConfirm: () {},
            ),
          );
          return;
        }

        final nuevo = Proveedores(
          idProveedor: proveedor?.idProveedor,
          nombre: nombreCtrl.text,
          rfc: rfcCtrl.text,
          direccion: direccionCtrl.text,
          direccionFiscal: direccionFiscalCtrl.text,
          telefono: telefonoCtrl.text,
        );

        if (proveedor == null) {
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
            titulo: proveedor == null ? "Proveedor agregado" : "Proveedor actualizado",
            mensaje: proveedor == null
                ? "El proveedor ha sido agregado exitosamente."
                : "El proveedor ha sido actualizado exitosamente.",
            icono: Icons.check_circle_outline,
            textoConfirmar: "Aceptar",
            onConfirm: () {},
          ),
        );
      },
    ),
  );
}

  //  ELIMINAR
  void eliminar(int id) async {
    await controller.eliminar(id);
    cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(titulo: "Proveedores", mostrarVolver: true),

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
              // HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: const [
                        Text(
                          "Gestión de Proveedores",

                          style: TextStyle(
                            fontSize: 28,

                            fontWeight: FontWeight.w800,

                            color: AppColors.textPrimary,
                          ),
                        ),

                        SizedBox(height: 8),

                        Text(
                          "Administre y controle todos los proveedores registrados",

                          style: TextStyle(
                            color: AppColors.textSecondary,

                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton.icon(
                    onPressed: () => abrirFormulario(),

                    icon: const Icon(Icons.add),

                    label: const Text("Agregar Proveedor"),

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

              // BUSCADOR
              SizedBox(
                width: 320,

                child: TextField(
                  onChanged: buscar,

                  decoration: InputDecoration(
                    hintText: "Buscar proveedor...",

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

              // TABLA
              _headerTabla(),

              const Divider(height: 1),

              Expanded(
                child: filtrados.isEmpty
                    ? const Center(
                        child: Text("No hay proveedores registrados"),
                      )
                    : ListView.separated(
                        itemCount: filtrados.length,

                        separatorBuilder: (_, _) => const Divider(height: 1),

                        itemBuilder: (_, i) {
                          final p = filtrados[i];

                          return _filaProveedor(p);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // HEADER TABLA
  Widget _headerTabla() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppColors.textMuted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),

      child: const Row(
        children: [
          Expanded(flex: 3, child: Text("PROVEEDOR", style: headerStyle)),

          Expanded(flex: 2, child: Text("RFC", style: headerStyle)),

          Expanded(flex: 2, child: Text("TELÉFONO", style: headerStyle)),

          Expanded(flex: 3, child: Text("DIRECCIÓN", style: headerStyle)),

          Expanded(flex: 2, child: Text("ACCIONES", style: headerStyle)),
        ],
      ),
    );
  }

  // FILA
  Widget _filaProveedor(Proveedores p) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),

      child: Row(
        children: [
          Expanded(
            flex: 3,

            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,

                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,

                    borderRadius: BorderRadius.circular(14),
                  ),

                  child: Icon(
                    Icons.local_shipping_outlined,

                    color: AppColors.primaryDarker,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Text(
                    p.nombre,

                    style: const TextStyle(
                      fontWeight: FontWeight.w700,

                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(flex: 2, child: Text(p.rfc)),

          Expanded(flex: 2, child: Text(p.telefono)),

          Expanded(
            flex: 3,

            child: Text(p.direccion.isEmpty ? "-" : p.direccion),
          ),

          Expanded(
            flex: 2,

            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProveedorDetalleView(proveedor: p)),
                  ),

                  tooltip: "Ver cuenta",

                  icon: const Icon(Icons.account_balance_wallet_outlined),

                  color: AppColors.primaryDark,
                ),

                IconButton(
                  onPressed: () => abrirFormulario(proveedor: p),

                  icon: const Icon(Icons.edit_outlined),

                  color: AppColors.warning,
                ),

                IconButton(
  onPressed: () => confirmarAccion(
    context: context,
    tituloConfirmar: "Eliminar proveedor",
    mensajeConfirmar: "¿Seguro que deseas eliminar este proveedor?",
    iconoConfirmar: Icons.warning_amber_rounded,
    textoConfirmar: "Eliminar",
    accion: () async {
      eliminar(p.idProveedor!);
    },
    tituloExito: "Proveedor eliminado",
    mensajeExito: "El proveedor ha sido eliminado exitosamente.",
  ),

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

  

