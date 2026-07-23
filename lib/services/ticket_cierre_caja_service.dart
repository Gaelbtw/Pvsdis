import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

class TicketCierreCajaService {
  static Future<pw.Document> generarCierre({
    required String fechaApertura,
    required String fechaCierre,
    required String cajero,

    required double total,
    required double efectivo,
    required double tarjeta,
    required double transferencia,
    required double cambioEntregado,

    required double fondo,
    required double devoluciones,
    required double contado,

    required double esperado,
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
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
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

              _row("Total", total),
              _row("Efectivo", efectivo),
              _row("Tarjeta", tarjeta),
              _row("Transferencia", transferencia),
              if (cambioEntregado > 0) _row("Cambio entregado", -cambioEntregado),
              if (devoluciones > 0) _row("Devoluciones", -devoluciones),

              pw.Divider(),

              // CAJA
              pw.Text("CAJA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),

              _row("Fondo inicial", fondo),
              _row("Contado", contado),

              pw.Divider(),

              // RESULTADO
              pw.Text("RESULTADO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),

              _row("Esperado", esperado),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Diferencia"),
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

              pw.Center(
                child: pw.Text("Cierre generado correctamente"),
              ),

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
