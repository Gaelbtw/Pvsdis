import 'package:pdf/widgets.dart' as pw;

import '../controllers/reporte_controller.dart';
import 'ticket_service.dart';

/// Reconstruye el PDF del ticket de una venta ya registrada a partir de su
/// `id`, reutilizando el snapshot guardado (líneas, totales, pagos y
/// promociones) — sin volver a evaluar el motor de promociones ni recalcular
/// nada. Punto único para reimprimir una venta, ya sea desde el POS
/// ("reimprimir último ticket") o desde Reportes.
class ReimpresionVentaService {
  static final _reporte = ReporteController();

  static Future<pw.Document> generar(int idVenta) async {
    final carrito = await _reporte.obtenerDetalleVentaParaTicket(idVenta);
    final totales = await _reporte.obtenerTotalesVentaParaTicket(idVenta);
    final pagos = await _reporte.obtenerPagosVenta(idVenta);
    final promociones = await _reporte.obtenerPromocionesVenta(idVenta);

    final promocionesParaTicket = promociones
        .map((p) => {
              'nombre': p['nombre_snapshot'],
              'ahorro_total': p['ahorro_total'],
            })
        .toList();

    final ahorroPromociones = promociones.fold<double>(
      0,
      (acc, p) => acc + ((p['ahorro_total'] as num?)?.toDouble() ?? 0),
    );

    return TicketService.generarTicket(
      carrito: carrito,
      total: totales.total,
      subtotal: totales.subtotal,
      descuento: totales.descuentoTotal,
      pagos: pagos,
      cambio: totales.cambio,
      promocionesAplicadas: promocionesParaTicket,
      ahorroPromociones: ahorroPromociones,
    );
  }
}
