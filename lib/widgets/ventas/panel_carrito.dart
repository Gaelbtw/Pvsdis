import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/descuento_utils.dart';
import '../../core/utils/promociones_engine.dart';
import '../../models/cliente_model.dart';
import 'linea_carrito.dart';
import 'promociones_aplicadas_section.dart';

/// Mitad derecha del punto de venta: el ticket en curso.
///
/// Agrupa el encabezado con sus acciones (espera, reimpresión, vaciar), el
/// cliente asignado, las líneas del carrito, las promociones aplicadas, el
/// descuento global y la zona de cobro, que llega ya armada en [cobro] para no
/// arrastrar hasta aquí las dependencias del pago.
///
/// No decide nada: todo llega calculado desde `ventas_view`, que sigue siendo
/// la dueña del estado de la venta.
class PanelCarrito extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  /// Desglose ya calculado (una sola vez por cuadro) de la venta en curso.
  final VentaCalculada venta;
  final ResultadoPromociones promociones;

  /// Controlador del campo de cantidad de cada línea, por id de producto.
  final Map<int, TextEditingController> controladoresCantidad;

  final int? lineaSeleccionada;
  final ValueChanged<int> onSeleccionarLinea;

  final Cliente? cliente;

  final int ventasEnEspera;
  final int? ultimaVentaId;

  final bool puedeAplicarDescuentos;
  final bool tieneDescuentoGlobal;

  final VoidCallback onVerEnEspera;
  final VoidCallback onReimprimir;
  final VoidCallback onPausar;
  final VoidCallback onVaciar;
  final VoidCallback onEditarDescuentoGlobal;

  /// Abrir el buscador de clientes (también en F3).
  final VoidCallback onElegirCliente;

  /// Quitar el cliente y dejar la venta como consumidor final.
  final VoidCallback onQuitarCliente;

  /// Mostrar la lista de atajos (también en F1).
  final VoidCallback onAyuda;

  final ValueChanged<int> onEditarDescuentoLinea;
  final void Function(int index, int delta) onCambiarCantidad;
  final void Function(int index, int cantidad) onCantidadTecleada;
  final ValueChanged<int> onQuitarLinea;

  /// La zona de cobro (ver `PanelCobro`).
  final Widget cobro;

  const PanelCarrito({
    super.key,
    required this.items,
    required this.venta,
    required this.promociones,
    required this.controladoresCantidad,
    required this.lineaSeleccionada,
    required this.onSeleccionarLinea,
    required this.cliente,
    required this.ventasEnEspera,
    required this.ultimaVentaId,
    required this.puedeAplicarDescuentos,
    required this.tieneDescuentoGlobal,
    required this.onVerEnEspera,
    required this.onReimprimir,
    required this.onPausar,
    required this.onVaciar,
    required this.onEditarDescuentoGlobal,
    required this.onElegirCliente,
    required this.onQuitarCliente,
    required this.onAyuda,
    required this.onEditarDescuentoLinea,
    required this.onCambiarCantidad,
    required this.onCantidadTecleada,
    required this.onQuitarLinea,
    required this.cobro,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          _encabezado(),
          const SizedBox(height: 10),
          _cliente(),
          const SizedBox(height: 20),
          Expanded(child: _lineas()),
          const Divider(height: 30),
          PromocionesAplicadasSection(
            aplicaciones: promociones.aplicaciones,
            ahorroTotal: promociones.ahorroTotal,
          ),
          if (puedeAplicarDescuentos) _botonDescuentoGlobal(),
          cobro,
        ],
      ),
    );
  }

  Widget _encabezado() {
    return Row(
      children: [
        const Icon(Icons.shopping_cart),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            "Detalle de Venta",
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          tooltip: 'Atajos de teclado (F1)',
          visualDensity: VisualDensity.compact,
          onPressed: onAyuda,
          icon: const Icon(Icons.help_outline),
          color: AppColors.textSecondary,
        ),
        if (ventasEnEspera > 0)
          Badge.count(
            count: ventasEnEspera,
            child: IconButton(
              tooltip: 'Ventas en espera (F8)',
              visualDensity: VisualDensity.compact,
              onPressed: onVerEnEspera,
              icon: const Icon(Icons.pending_actions),
              color: AppColors.textSecondary,
            ),
          ),
        if (ultimaVentaId != null)
          IconButton(
            tooltip: 'Reimprimir último ticket #$ultimaVentaId (F9)',
            visualDensity: VisualDensity.compact,
            onPressed: onReimprimir,
            icon: const Icon(Icons.receipt_long_outlined),
            color: AppColors.textSecondary,
          ),
        if (items.isNotEmpty) ...[
          IconButton(
            tooltip: 'Poner en espera (F7)',
            visualDensity: VisualDensity.compact,
            onPressed: onPausar,
            icon: const Icon(Icons.pause_circle_outline),
            color: AppColors.textSecondary,
          ),
          IconButton(
            tooltip: 'Vaciar carrito (Shift+Supr)',
            visualDensity: VisualDensity.compact,
            onPressed: onVaciar,
            icon: const Icon(Icons.remove_shopping_cart_outlined),
            color: AppColors.error,
          ),
        ],
      ],
    );
  }

  /// El cliente de la venta. Sin cliente muestra un botón para asignarlo: la
  /// venta a crédito, el historial y una factura posterior dependen de que se
  /// pueda hacer aquí, sin cancelar la venta para ir a otra pantalla.
  Widget _cliente() {
    if (cliente == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onElegirCliente,
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Asignar cliente  ·  F3'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: onElegirCliente,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.person, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cliente!.nombre,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Quitar cliente',
              visualDensity: VisualDensity.compact,
              onPressed: onQuitarCliente,
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineas() {
    if (items.isEmpty) {
      return const Center(child: Text("No hay productos"));
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = items[i];
        final id = item['id_producto'] as int;

        // `putIfAbsent` cubre el caso de una línea que llegara sin controlador
        // (antes un `!` reventaba la pantalla completa). El texto NO se
        // reescribe aquí: eso movía el cursor al teclear.
        final controlador = controladoresCantidad.putIfAbsent(
          id,
          () => TextEditingController(text: item['cantidad'].toString()),
        );

        return LineaCarrito(
          item: item,
          calculada: venta.lineas[i],
          cantidadCtrl: controlador,
          seleccionada: i == lineaSeleccionada,
          puedeAplicarDescuentos: puedeAplicarDescuentos,
          onSeleccionar: () => onSeleccionarLinea(i),
          onEditarDescuento: () => onEditarDescuentoLinea(i),
          onCambiarCantidad: (delta) => onCambiarCantidad(i, delta),
          onCantidadTecleada: (cantidad) => onCantidadTecleada(i, cantidad),
          onQuitar: () => onQuitarLinea(i),
        );
      },
    );
  }

  Widget _botonDescuentoGlobal() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: items.isEmpty ? null : onEditarDescuentoGlobal,
          icon: const Icon(Icons.sell_outlined, size: 18),
          label: Text(
            tieneDescuentoGlobal ? "Editar descuento global" : "Aplicar descuento global",
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primaryDark),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ),
    );
  }
}
