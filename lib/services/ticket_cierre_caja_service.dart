import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';
import '../controllers/caja_controller.dart';

/// Ticket de **cierre de caja (Corte Z)**: cierra el turno y reporta el
/// desglose completo del resumen ([ResumenCaja]) — ventas por método,
/// anticipos de apartados, movimientos manuales de efectivo y pagos a
/// proveedores — más el arqueo final (esperado vs. contado y su diferencia).
///
/// Recibe el mismo [ResumenCaja] que el Corte X para que ambos tickets muestren
/// EXACTAMENTE los mismos rubros: antes el cierre recibía solo un subconjunto
/// (fondo, ventas, cambio, devoluciones) y el "esperado" impreso no cuadraba
/// con su propio desglose porque faltaban los anticipos y los movimientos.
class TicketCierreCajaService {
  static Future<pw.Document> generarCierre({
    required String fechaApertura,
    required String fechaCierre,
    required String cajero,
    required ResumenCaja resumen,
    required double contado,
    required double diferencia,
    String? observacionesApertura,
    String? observacionesCierre,
  }) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;

    pdf.addPage(
      pw.Page(
        pageFormat: AppConfig.formatoPapel, // térmico
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ENCABEZADO
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      config.nombreNegocio,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("CIERRE DE CAJA"),
                    pw.SizedBox(height: 5),
                  ],
                ),
              ),

              pw.Divider(),

              // INFO GENERAL
              pw.Text("Cajero: $cajero"),
              pw.SizedBox(height: 5),
              pw.Text("Apertura: $fechaApertura"),
              pw.Text("Cierre:   $fechaCierre"),
              if (observacionesApertura != null && observacionesApertura.isNotEmpty)
                pw.Text("Obs. apertura: $observacionesApertura"),
              if (observacionesCierre != null && observacionesCierre.isNotEmpty)
                pw.Text("Obs. cierre: $observacionesCierre"),

              pw.Divider(),

              // VENTAS
              pw.Text("VENTAS", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              _row("Total", resumen.totalVentas),
              _row("Efectivo", resumen.ventasEfectivo),
              _row("Tarjeta", resumen.ventasTarjeta),
              _row("Transferencia", resumen.ventasTransferencia),
              if (resumen.totalAnticipos > 0) _row("Anticipos apartados", resumen.totalAnticipos),
              if (resumen.cambioEntregado > 0) _row("Cambio entregado", -resumen.cambioEntregado),
              if (resumen.devoluciones > 0) _row("Devoluciones", -resumen.devoluciones),

              // MOVIMIENTOS DE EFECTIVO (entradas/salidas manuales y pagos a
              // proveedores): afectan el efectivo esperado, así que se listan
              // para que el arqueo cuadre a la vista.
              if (resumen.entradasEfectivo > 0 ||
                  resumen.salidasEfectivo > 0 ||
                  resumen.pagosProveedoresEfectivo > 0) ...[
                pw.Divider(),
                pw.Text("MOVIMIENTOS DE EFECTIVO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                if (resumen.entradasEfectivo > 0) _row("Entradas de efectivo", resumen.entradasEfectivo),
                if (resumen.salidasEfectivo > 0) _row("Salidas de efectivo", -resumen.salidasEfectivo),
                if (resumen.pagosProveedoresEfectivo > 0)
                  _row("Pagos a proveedores", -resumen.pagosProveedoresEfectivo),
              ],

              pw.Divider(),

              // CAJA
              pw.Text("CAJA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              _row("Fondo inicial", resumen.fondoInicial),

              pw.Divider(),

              // RESULTADO (arqueo)
              pw.Text("RESULTADO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              _row("Efectivo esperado", resumen.efectivoEsperado),
              _row("Efectivo contado", contado),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Diferencia", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    AppConfig.formatoMoneda(diferencia),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: diferencia >= 0 ? PdfColors.green : PdfColors.red,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              pw.Center(child: pw.Text("Cierre generado correctamente")),

              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // Helper para filas
  static pw.Widget _row(String label, double value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label),
        pw.Text(AppConfig.formatoMoneda(value)),
      ],
    );
  }
}
