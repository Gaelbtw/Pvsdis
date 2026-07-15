import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

class TicketService {
  static Future<pw.Document> generarTicket({
    required List<Map<String, dynamic>> carrito,
    required double total,
    required String metodoPago,
    required double recibido,
    required double cambio,
    double subtotal = 0,
    double descuento = 0,
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
                    if (config.rfc != null) pw.Text("RFC: ${config.rfc}"),
                    pw.SizedBox(height: 5),
                    pw.Text("Ticket de venta"),
                  ],
                ),
              ),

              pw.Divider(),

              // PRODUCTOS
              ...carrito.map((item) {
                final descuentoLinea = (item['descuento_monto'] as num?)?.toDouble() ?? 0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(item['nombre']),
                          ),
                          pw.Text(
                            "${item['cantidad']} x ${AppConfig.formatoMoneda(item['precio'] as num)}",
                          ),
                        ],
                      ),
                      if (descuentoLinea > 0)
                        pw.Text(
                          "  Descuento: -${AppConfig.formatoMoneda(descuentoLinea)}",
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                    ],
                  ),
                );
              }),

              pw.Divider(),

              pw.Text("Método de pago: $metodoPago"),

              if (config.tasaImpuestoPorcentaje > 0) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  "IVA (${config.tasaImpuestoPorcentaje.toStringAsFixed(2)}%) incluido",
                ),
              ],

              pw.SizedBox(height: 5),

              if (descuento > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Subtotal"),
                    pw.Text(AppConfig.formatoMoneda(subtotal)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Descuento"),
                    pw.Text("-${AppConfig.formatoMoneda(descuento)}"),
                  ],
                ),
                pw.SizedBox(height: 3),
              ],

              pw.Center(
                child: pw.Text(
                  "TOTAL: ${AppConfig.formatoMoneda(total)}",
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.Text("Efectivo:  $recibido"),
              pw.Text("Cambio: $cambio"),

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
