import 'package:flutter/material.dart';

import '../../controllers/producto_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/configuracion_model.dart';
import '../../models/producto_model.dart';
import '../app_text_field.dart';
import '../form_dialog.dart';
import '../toast.dart';

/// Diálogo de edición rápida de un producto desde Inventario (nombre,
/// precio e inventario disponible). Antes vivía completo dentro de
/// `inventario_view.dart` (~227 líneas) armado a mano con `Dialog`/`Container`.
void mostrarEditarProductoDialog(
  BuildContext context, {
  required Map<String, dynamic> producto,
  required bool esCajero,
  required Configuracion config,
  required ProductoController productoController,
  required Future<void> Function() onGuardado,
}) {
  final nombreCtrl = TextEditingController(text: producto['nombre']);
  final precioCtrl = TextEditingController(text: producto['precio'].toString());
  final stockCtrl = TextEditingController(text: producto['cantidad'].toString());

  showDialog(
    context: context,
    builder: (_) => FormDialog(
      titulo: "Editar Producto",
      subtitulo: "Actualiza la información del producto.",
      textoGuardar: "Guardar",
      campos: [
        if (!esCajero)
          AppTextField(
            controller: nombreCtrl,
            hint: "Nombre del producto",
            icon: Icons.inventory_2_outlined,
            iconColor: AppColors.primaryDark,
            fillColor: AppColors.surface,
          ),
        if (!esCajero)
          AppTextField(
            controller: precioCtrl,
            hint: "Precio",
            icon: Icons.attach_money,
            iconColor: AppColors.primaryDark,
            keyboardType: TextInputType.number,
          ),
        AppTextField(
          controller: stockCtrl,
          hint: "Inventario disponible",
          icon: Icons.layers_outlined,
          iconColor: AppColors.primaryDark,
          keyboardType: TextInputType.number,
        ),
      ],
      onGuardar: () async {
        await productoController.actualizar(
          Producto(
            idProducto: producto['id_producto'],
            nombre: nombreCtrl.text,
            descripcion: "",
            precio: double.parse(precioCtrl.text),
            categoriaId: producto['id_categoria'],
            estado: producto['estado'] ?? "Activo",
            stockMinimo: config.stockMinimo,
            // Preserva el código existente: este diálogo no lo edita, y
            // toMap() sobrescribe la fila completa al guardar.
            codigoBarras: producto['codigo_barras'],
          ),
        );

        await productoController.actualizarStock(
          producto['id_producto'],
          int.tryParse(stockCtrl.text) ?? producto['cantidad'],
        );

        if (!context.mounted) return;
        Navigator.pop(context);

        await onGuardado();

        if (!context.mounted) return;
        Toast.exito(context, "Producto actualizado");
      },
    ),
  );
}
