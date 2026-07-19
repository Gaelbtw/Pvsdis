import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

/// Recibo de un anticipo/abono de un Apartado: a diferencia de
/// `TicketService.generarTicket` (que representa el cobro completo de una
/// venta), este documento representa solo el pago de *hoy* dentro de un
/// apartado que puede seguir abierto — por eso siempre muestra abonado a la
/// fecha y saldo pendiente, no un "TOTAL" de cierre.
class TicketApartadoService {
  static Future<pw.Document> generarReciboAbono({
    required int idApartado,
    required String clienteNombre,
    required List<Map<String, dynamic>> items,
    required String tipoAbono,
    required double montoAbono,
    required List<Map<String, dynamic>> pagos,
    required double cambio,
    required double totalApartado,
    required double abonadoAFecha,
    required double saldoPendiente,
  }) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      config.nombreNegocio,
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                    if (config.direccion != null) pw.Text(config.direccion!),
                    if (config.telefono != null) pw.Text("Tel: ${config.telefono}"),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      saldoPendiente <= 0 ? "Recibo de liquidación de apartado" : "Recibo de $tipoAbono",
                    ),
                  ],
                ),
              ),

              pw.Divider(),

              pw.Text("Apartado #$idApartado"),
              pw.Text("Cliente: $clienteNombre"),

              pw.Divider(),

              pw.Text("Productos apartados", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ...items.map((item) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(flex: 3, child: pw.Text(item['nombre'].toString())),
                        pw.Text(
                          "${item['cantidad']} x ${AppConfig.formatoMoneda(item['precio_neto'] as num)}",
                        ),
                      ],
                    ),
                  )),

              pw.Divider(),

              ...pagos.map((p) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(p['metodo_pago'].toString()),
                      pw.Text(AppConfig.formatoMoneda((p['monto'] as num).toDouble())),
                    ],
                  )),
              if (cambio > 0) pw.Text("Cambio: ${AppConfig.formatoMoneda(cambio)}"),

              pw.SizedBox(height: 5),

              pw.Center(
                child: pw.Text(
                  "PAGADO HOY: ${AppConfig.formatoMoneda(montoAbono)}",
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),

              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total del apartado"),
                  pw.Text(AppConfig.formatoMoneda(totalApartado)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Abonado a la fecha"),
                  pw.Text(AppConfig.formatoMoneda(abonadoAFecha)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "Saldo pendiente",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    saldoPendiente <= 0 ? "LIQUIDADO" : AppConfig.formatoMoneda(saldoPendiente),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              pw.Center(child: pw.Text(config.mensajeTicket)),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}
