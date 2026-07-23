import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../controllers/devoluciones_controller.dart';
import '../core/config/app_config.dart';

class TicketDevolucionService {
  static Future<pw.Document> generarTicket(ComprobanteDevolucion comprobante) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;

    pdf.addPage(
      pw.Page(
        pageFormat: AppConfig.formatoPapel,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      config.nombreNegocio,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      comprobante.tipo == 'Cancelacion'
                          ? 'Comprobante de cancelación'
                          : 'Comprobante de devolución',
                    ),
                  ],
                ),
              ),

              pw.Divider(),

              pw.Text('Venta original: #${comprobante.idVenta}'),
              pw.Text('Fecha: ${comprobante.fechaHora}'),
              pw.Text('Atendió: ${comprobante.usuario}'),
              pw.SizedBox(height: 5),
              pw.Text('Motivo: ${comprobante.motivo}'),

              pw.Divider(),

              ...comprobante.items.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(item['nombre'].toString()),
                      ),
                      pw.Text(
                        "${item['cantidad']} x ${AppConfig.formatoMoneda(item['precio'] as num)}",
                      ),
                    ],
                  ),
                );
              }),

              pw.Divider(),

              pw.Center(
                child: pw.Text(
                  "TOTAL DEVUELTO: ${AppConfig.formatoMoneda(comprobante.importe)}",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 20),

              pw.Center(
                child: pw.Text(config.mensajeTicket),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}
