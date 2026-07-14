import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class TicketCorteCajaService {

  static Future<pw.Document> generarCorte({
    required String fecha,
    required String turno,
    required String cajero,
    required String horaApertura,
    required String horaCierre,

    required double total,
    required double efectivo,
    required double tarjeta,

    required double fondo,
    required double salidas,
    required double contado,

    required double esperado,
    required double diferencia,
  }) async {

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // 🧾 térmico
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              // 🏪 ENCABEZADO
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      "Tortilleria la Lomita",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text("CORTE DE CAJA"),
                    pw.SizedBox(height: 5),
                  ],
                ),
              ),

              pw.Divider(),

              // 📅 INFO GENERAL
              pw.Text("Fecha: $fecha"),
              pw.Text("Turno: $turno"),
              pw.Text("Cajero: $cajero"),

              pw.SizedBox(height: 5),

              pw.Text("Apertura: $horaApertura"),
              pw.Text("Cierre:   $horaCierre"),

              pw.Divider(),

              // 💰 VENTAS
              pw.Text("VENTAS", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),

              _row("Total", total),
              _row("Efectivo", efectivo),
              _row("Tarjeta", tarjeta),

              pw.Divider(),

              // 🏦 CAJA
              pw.Text("CAJA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),

              _row("Fondo inicial", fondo),
              _row("Salidas", salidas),
              _row("Contado", contado),

              pw.Divider(),

              // 📊 RESULTADO
              pw.Text("RESULTADO", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),

              _row("Esperado", esperado),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Diferencia"),
                  pw.Text(
                    "\$${diferencia.toStringAsFixed(2)}",
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: diferencia >= 0 ? PdfColors.green : PdfColors.red,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              pw.Center(
                child: pw.Text("Corte generado correctamente"),
              ),

              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // 🔧 Helper para filas
  static pw.Widget _row(String label, double value) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label),
        pw.Text("\$${value.toStringAsFixed(2)}"),
      ],
    );
  }
}