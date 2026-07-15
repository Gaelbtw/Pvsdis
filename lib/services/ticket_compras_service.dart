import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

class TicketComprasService {
  static Future<pw.Document> generarTicket({
    required List<Map<String, dynamic>> carrito,
    required double total,
    required String proveedor
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
              // ENCABEZADO
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
                    if (config.direccion != null) pw.Text(config.direccion!),
                    if (config.telefono != null) pw.Text("Tel: ${config.telefono}"),
                    pw.SizedBox(height: 5),
                    pw.Text("Ticket de compra"),
                  ],
                ),
              ),

              pw.Divider(),
              pw.Text(proveedor),

              ...carrito.map((item) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(item['nombre']),
                      ),
                      pw.Text("${item['cantidad']}"),
                      pw.Text(AppConfig.formatoMoneda(item['precio_compra'] as num? ?? 0)),
                    ],
                  ),
                );
              }),

              pw.Divider(),

              pw.SizedBox(height: 5),

              //  TOTAL GRANDE
              pw.Center(
                child: pw.Text(
                  "TOTAL: ${AppConfig.formatoMoneda(total)}",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
            ],
          );
        },
      ),
    );

    return pdf;
  }
}
