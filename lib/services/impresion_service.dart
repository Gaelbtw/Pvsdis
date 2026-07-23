import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/config/app_config.dart';

/// Punto único para imprimir un ticket ya generado, respetando la configuración
/// de impresión del negocio. Si hay auto-impresión activada y una impresora
/// guardada, imprime directo sin abrir el diálogo; si no —o si esa impresora ya
/// no responde— cae al diálogo de impresión estándar. Así ningún call site
/// necesita conocer las opciones de impresión.
class ImpresionService {
  static Future<void> imprimir(pw.Document doc) async {
    final c = AppConfig.actual;
    final url = c.impresoraUrl;

    if (c.autoImprimirTicket && url != null && url.isNotEmpty) {
      try {
        await Printing.directPrintPdf(
          printer: Printer(url: url, name: c.impresoraNombre),
          onLayout: (PdfPageFormat format) async => doc.save(),
        );
        return;
      } catch (_) {
        // La impresora guardada no está disponible (apagada, desconectada,
        // cambió de nombre): en vez de fallar la venta, se abre el diálogo.
      }
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }
}
