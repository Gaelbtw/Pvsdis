import 'package:flutter/material.dart';

import '../../controllers/producto_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/motivo_ajuste_inventario.dart';
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

  final stockOriginal = producto['cantidad'] as int;
  var motivo = MotivoAjusteInventario.porDefectoAjuste;

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
        // El motivo solo tiene sentido junto al campo de existencias, y solo
        // se guarda si la cantidad realmente cambió (ver onGuardar). Va en un
        // StatefulBuilder porque `campos` es una lista fija de widgets: sin
        // él, el desplegable no repintaría la opción elegida.
        if (puedeAjustarInventario)
          StatefulBuilder(
            builder: (context, setEstadoCampo) => DropdownButtonFormField<MotivoAjusteInventario>(
              initialValue: motivo,
              decoration: InputDecoration(
                labelText: "Motivo del ajuste",
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
              items: MotivoAjusteInventario.values
                  .map((m) => DropdownMenuItem(value: m, child: Text(m.etiqueta)))
                  .toList(),
              onChanged: (v) => setEstadoCampo(() => motivo = v ?? motivo),
            ),
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
              // Preserva los datos que este diálogo no edita: `toMap()`
              // sobrescribe la fila COMPLETA al guardar, así que omitirlos
              // aquí los borraría de la base de datos.
              codigoBarras: producto['codigo_barras'],
              sku: producto['sku'],
              ivaTasa: (producto['iva_tasa'] as num?)?.toDouble(),
            ),
          );
        }

        if (puedeAjustarInventario) {
          final nuevoStock = int.tryParse(stockCtrl.text) ?? stockOriginal;
          // Sin cambio no se llama al controlador: registraría una entrada de
          // auditoría ("modificado de 8 a 8") por el solo hecho de abrir el
          // diálogo y guardar, ensuciando el historial.
          if (nuevoStock != stockOriginal) {
            await productoController.actualizarStock(
              producto['id_producto'],
              nuevoStock,
              motivo: motivo,
            );
          }
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
