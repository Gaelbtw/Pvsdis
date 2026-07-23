import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../controllers/devoluciones_controller.dart';
import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../services/ticket_devolucion_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';

/// Detalle de una venta: sus productos, lo que llevan de devuelto/pendiente,
/// el historial de devoluciones previas, y las acciones de cancelación
/// total / devolución parcial. Sin SQL aquí: todo pasa por
/// [DevolucionesController].
class DetalleVentaView extends StatefulWidget {
  final int idVenta;

  const DetalleVentaView({super.key, required this.idVenta});

  @override
  State<DetalleVentaView> createState() => _DetalleVentaViewState();
}

class _DetalleVentaViewState extends State<DetalleVentaView> {
  final _controller = DevolucionesController();

  VentaDetalle? detalle;
  bool cargando = true;

  /// id_producto -> cantidad seleccionada para devolución parcial.
  final Map<int, int> seleccion = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);

    final d = await _controller.obtenerDetalleVenta(widget.idVenta);

    if (!mounted) return;
    setState(() {
      detalle = d;
      seleccion.clear();
      cargando = false;
    });
  }

  int get totalUnidadesSeleccionadas =>
      seleccion.values.fold(0, (a, b) => a + b);

  void _cambiarSeleccion(int idProducto, int delta, int maxPendiente) {
    setState(() {
      final actual = seleccion[idProducto] ?? 0;
      final nuevo = (actual + delta).clamp(0, maxPendiente);
      if (nuevo == 0) {
        seleccion.remove(idProducto);
      } else {
        seleccion[idProducto] = nuevo;
      }
    });
  }

  Future<void> _pedirMotivoYEjecutar({
    required String titulo,
    required String subtitulo,
    required Future<int> Function(String motivo) accion,
  }) async {
    final motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => FormDialog(
        titulo: titulo,
        subtitulo: subtitulo,
        textoGuardar: 'Confirmar',
        campos: [
          AppTextField(
            controller: motivoCtrl,
            hint: 'Motivo (obligatorio)',
            maxLines: 3,
          ),
        ],
        onGuardar: () async {
          final motivo = motivoCtrl.text.trim();

          if (motivo.isEmpty) {
            showDialog(
              context: dialogContext,
              builder: (_) => const CustomAlert(
                titulo: 'Motivo requerido',
                mensaje: 'Debes indicar el motivo antes de continuar.',
                icono: Icons.warning_amber_rounded,
                textoConfirmar: 'Aceptar',
              ),
            );
            return;
          }

          try {
            final idDevolucion = await accion(motivo);

            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);

            await _cargar();

            if (!mounted) return;
            _ofrecerImprimir(idDevolucion);
          } catch (e) {
            if (!dialogContext.mounted) return;
            final mensaje = e.toString().replaceFirst('Exception: ', '');
            showDialog(
              context: dialogContext,
              builder: (_) => CustomAlert(
                titulo: 'No se pudo procesar',
                mensaje: mensaje,
                icono: Icons.error_outline,
                textoConfirmar: 'Aceptar',
              ),
            );
          }
        },
      ),
    );
  }

  void _cancelarVentaCompleta() {
    final d = detalle;
    if (d == null) return;

    _pedirMotivoYEjecutar(
      titulo: 'Cancelar venta',
      subtitulo:
          'Se devolverán todos los productos pendientes de la venta #${d.idVenta} '
          'y se reintegrará su stock. Esta acción no se puede deshacer.',
      accion: (motivo) => _controller.cancelarVenta(idVenta: d.idVenta, motivo: motivo),
    );
  }

  void _devolverSeleccionados() {
    final d = detalle;
    if (d == null || seleccion.isEmpty) return;

    final items = seleccion.entries
        .map((e) => {'id_producto': e.key, 'cantidad': e.value})
        .toList();

    _pedirMotivoYEjecutar(
      titulo: 'Devolver productos',
      subtitulo:
          'Se devolverán $totalUnidadesSeleccionadas unidad(es) seleccionadas '
          'y se reintegrará su stock.',
      accion: (motivo) => _controller.devolverParcial(
        idVenta: d.idVenta,
        motivo: motivo,
        items: items,
      ),
    );
  }

  Future<void> _ofrecerImprimir(int idDevolucion) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'Operación registrada',
        mensaje: 'La operación se registró correctamente. ¿Deseas imprimir el comprobante?',
        icono: Icons.check_circle_outline,
        textoCancelar: 'Cerrar',
        textoConfirmar: 'Imprimir',
        onConfirm: () async {
          final comprobante = await _controller.obtenerComprobante(idDevolucion);
          final pdf = await TicketDevolucionService.generarTicket(comprobante);
          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdf.save(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = detalle;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(
        titulo: d == null ? 'Detalle de venta' : 'Venta #${d.idVenta}',
        mostrarVolver: true,
      ),
      body: cargando || d == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerCard(d),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: _itemsPanel(d)),
                        const SizedBox(width: 16),
                        Expanded(flex: 4, child: _historialPanel(d)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _accionesFooter(d),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(VentaDetalle d) {
    final totalDevuelto = d.devoluciones.fold<double>(
      0,
      (acc, item) => acc + ((item['importe'] as num?)?.toDouble() ?? 0),
    );
    final totalNeto = d.total - totalDevuelto;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _estadoChip(d.estado),
          const SizedBox(width: 20),
          _infoCol('Cliente', d.cliente?.isNotEmpty == true ? d.cliente! : 'Consumidor final'),
          const SizedBox(width: 24),
          _infoCol('Fecha', d.fecha),
          const SizedBox(width: 24),
          _infoCol('Método de pago', d.metodoPago),
          const Spacer(),
          _infoCol('Total original', AppConfig.formatoMoneda(d.total)),
          if (totalDevuelto > 0) ...[
            const SizedBox(width: 24),
            _infoCol('Total neto', AppConfig.formatoMoneda(totalNeto)),
          ],
        ],
      ),
    );
  }

  Widget _infoCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ],
    );
  }

  Widget _estadoChip(String estado) {
    final color = switch (estado) {
      'Cancelada' => AppColors.error,
      'Parcialmente devuelta' => AppColors.warning,
      _ => AppColors.success,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        estado,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _itemsPanel(VentaDetalle d) {
    final puedeOperar = d.estado != 'Cancelada';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Productos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: d.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _itemRow(d.items[i], puedeOperar),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item, bool puedeOperar) {
    final idProducto = item['id_producto'] as int;
    final nombre = item['nombre']?.toString() ?? '';
    final precio = (item['precio'] as num?)?.toDouble() ?? 0;
    final precioNeto = (item['precio_neto'] as num?)?.toDouble() ?? precio;
    final huboDescuento = (precio - precioNeto).abs() >= 0.01;
    final vendida = item['cantidad_vendida'] as int;
    final devuelta = item['cantidad_devuelta'] as int;
    final pendiente = item['cantidad_pendiente'] as int;
    final seleccionada = seleccion[idProducto] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Vendido: $vendida  ·  Devuelto: $devuelta  ·  Pendiente: $pendiente  ·  '
                  '${huboDescuento ? '${AppConfig.formatoMoneda(precioNeto)} c/u pagado (lista: ${AppConfig.formatoMoneda(precio)})' : '${AppConfig.formatoMoneda(precio)} c/u'}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (puedeOperar && pendiente > 0) ...[
            IconButton(
              onPressed: seleccionada > 0
                  ? () => _cambiarSeleccion(idProducto, -1, pendiente)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$seleccionada',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: seleccionada < pendiente
                  ? () => _cambiarSeleccion(idProducto, 1, pendiente)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ] else
            Text(
              pendiente == 0 ? 'Completo' : '—',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  Widget _historialPanel(VentaDetalle d) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historial de devoluciones', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          Expanded(
            child: d.devoluciones.isEmpty
                ? Center(
                    child: Text(
                      'Sin devoluciones registradas.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: d.devoluciones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final item = d.devoluciones[i];
                      final tipo = item['tipo']?.toString() ?? 'Parcial';
                      final importe = (item['importe'] as num?)?.toDouble() ?? 0;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  tipo == 'Cancelacion' ? 'Cancelación' : 'Devolución parcial',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  AppConfig.formatoMoneda(importe),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item['fecha_hora']}  ·  ${item['usuario_nombre'] ?? 'N/D'}',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['motivo']?.toString() ?? '',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _accionesFooter(VentaDetalle d) {
    if (d.estado == 'Cancelada') {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _cancelarVentaCompleta,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar venta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: totalUnidadesSeleccionadas > 0 ? _devolverSeleccionados : null,
            icon: const Icon(Icons.assignment_return_outlined),
            label: Text(
              totalUnidadesSeleccionadas > 0
                  ? 'Devolver seleccionados ($totalUnidadesSeleccionadas)'
                  : 'Selecciona productos para devolver',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}
