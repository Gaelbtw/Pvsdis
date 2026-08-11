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
/// [puedeEditarProducto] habilita nombre y precio; [puedeAjustarInventario]
/// habilita las existencias. Son dos permisos distintos (ver
/// `Permiso.gestionarProductos` y `Permiso.ajustarInventario`): hay negocios
/// donde el cajero cuenta inventario pero no toca precios. Cada campo
/// deshabilitado además NO se persiste, para que la vista no sea el único
/// control.
void mostrarEditarProductoDialog(
  BuildContext context, {
  required Map<String, dynamic> producto,
  required bool puedeEditarProducto,
  required bool puedeAjustarInventario,
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
        if (puedeEditarProducto)
          AppTextField(
            controller: nombreCtrl,
            hint: "Nombre del producto",
            icon: Icons.inventory_2_outlined,
            iconColor: AppColors.primaryDark,
            fillColor: AppColors.surface,
          ),
        if (puedeEditarProducto)
          AppTextField(
            controller: precioCtrl,
            hint: "Precio",
            icon: Icons.attach_money,
            iconColor: AppColors.primaryDark,
            keyboardType: TextInputType.number,
          ),
        if (puedeAjustarInventario)
          AppTextField(
            controller: stockCtrl,
            hint: "Inventario disponible",
            icon: Icons.layers_outlined,
            iconColor: AppColors.primaryDark,
            keyboardType: TextInputType.number,
          ),
      ],
      onGuardar: () async {
        if (puedeEditarProducto) {
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
        }

        if (puedeAjustarInventario) {
          await productoController.actualizarStock(
            producto['id_producto'],
            int.tryParse(stockCtrl.text) ?? producto['cantidad'],
          );
        }

        if (!context.mounted) return;
        Navigator.pop(context);

        await onGuardado();

        if (!context.mounted) return;
        Toast.exito(context, "Producto actualizado");
      },
    ),
    // Los TextEditingController viven fuera del árbol de widgets (los crea
    // esta función, no un State), así que hay que liberarlos a mano cuando
    // el diálogo se cierra -- por cualquier vía, incluido descartarlo sin
    // guardar.
  ).whenComplete(() {
    nombreCtrl.dispose();
    precioCtrl.dispose();
    stockCtrl.dispose();
  });
}
