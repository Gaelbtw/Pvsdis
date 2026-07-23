import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

class TicketService {
  static Future<pw.Document> generarTicket({
    required List<Map<String, dynamic>> carrito,
    required double total,
    required List<Map<String, dynamic>> pagos,
    required double cambio,
    double subtotal = 0,
    double descuento = 0,
    List<Map<String, dynamic>>? promocionesAplicadas,
    double ahorroPromociones = 0,
  }) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;

    pdf.addPage(
      pw.Page(
        pageFormat: AppConfig.formatoPapel,
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

              ...pagos.map((p) => pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(p['metodo_pago'].toString()),
                      pw.Text(AppConfig.formatoMoneda((p['monto'] as num).toDouble())),
                    ],
                  )),

              if (config.tasaImpuestoPorcentaje > 0 && !config.mostrarIvaDesglosado) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  "IVA (${config.tasaImpuestoPorcentaje.toStringAsFixed(2)}%) incluido",
                ),
              ],

              pw.SizedBox(height: 5),

              if (promocionesAplicadas != null && promocionesAplicadas.isNotEmpty) ...[
                pw.Text(
                  "Promociones aplicadas",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                ...promocionesAplicadas.map((p) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text("  ${p['nombre']}")),
                        pw.Text("-${AppConfig.formatoMoneda((p['ahorro_total'] as num?) ?? 0)}"),
                      ],
                    )),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Subtotal anterior"),
                    pw.Text(AppConfig.formatoMoneda(subtotal > 0 ? subtotal : total + ahorroPromociones)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Ahorro total"),
                    pw.Text("-${AppConfig.formatoMoneda(ahorroPromociones)}"),
                  ],
                ),
                pw.SizedBox(height: 3),
              ],

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

              if (config.mostrarIvaDesglosado && config.tasaImpuestoPorcentaje > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Subtotal (sin IVA)"),
                    pw.Text(AppConfig.formatoMoneda(total / (1 + config.tasaImpuestoPorcentaje / 100))),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("IVA (${config.tasaImpuestoPorcentaje.toStringAsFixed(2)}%)"),
                    pw.Text(AppConfig.formatoMoneda(
                        total - total / (1 + config.tasaImpuestoPorcentaje / 100))),
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

              if (cambio > 0) pw.Text("Cambio: ${AppConfig.formatoMoneda(cambio)}"),

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
