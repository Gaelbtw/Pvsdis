import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';
import '../controllers/caja_controller.dart';

/// Ticket de **Corte X (lectura)**: una foto del estado de la caja SIN
/// cerrarla. A diferencia del cierre (Corte Z), no pide efectivo contado ni
/// calcula diferencia — solo reporta lo vendido y el efectivo que debería
/// haber hasta el momento, para que el cajero/supervisor haga un arqueo
/// parcial durante el turno.
class TicketCorteXService {
  /// [ocultarEfectivoEsperado] omite del ticket el total que debería haber en
  /// el cajón.
  ///
  /// El Corte X es una lectura parcial que el cajero puede imprimir en
  /// cualquier momento del turno. Si trae el efectivo esperado, basta con
  /// sacarlo antes de contar para saber el número exacto y anular el arqueo
  /// ciego de la pantalla de cierre (ver `CajaView.arqueoCiego`). Cerrar solo
  /// la pantalla y dejar abierta esta puerta no serviría de nada.
  static Future<pw.Document> generar({
    required String cajero,
    required String fechaApertura,
    required String fechaCorte,
    required ResumenCaja resumen,
    bool ocultarEfectivoEsperado = false,
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
                    pw.Text("CORTE X (LECTURA)"),
                    pw.SizedBox(height: 5),
                  ],
                ),
              ),
              pw.Divider(),
              pw.Text("Cajero: $cajero"),
              pw.SizedBox(height: 5),
              pw.Text("Apertura: $fechaApertura"),
              pw.Text("Corte:    $fechaCorte"),
              pw.Divider(),
              pw.Text("VENTAS", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              _row("Total", resumen.totalVentas),
              _row("Efectivo", resumen.ventasEfectivo),
              _row("Tarjeta", resumen.ventasTarjeta),
              _row("Transferencia", resumen.ventasTransferencia),
              if (resumen.totalAnticipos > 0) _row("Anticipos apartados", resumen.totalAnticipos),
              if (resumen.cambioEntregado > 0) _row("Cambio entregado", -resumen.cambioEntregado),
              if (resumen.devoluciones > 0) _row("Devoluciones", -resumen.devoluciones),
              if (resumen.entradasEfectivo > 0 || resumen.salidasEfectivo > 0) ...[
                pw.Divider(),
                pw.Text("MOVIMIENTOS", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                if (resumen.entradasEfectivo > 0) _row("Entradas de efectivo", resumen.entradasEfectivo),
                if (resumen.salidasEfectivo > 0) _row("Salidas de efectivo", -resumen.salidasEfectivo),
              ],
              pw.Divider(),
              pw.Text("CAJA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 5),
              _row("Fondo inicial", resumen.fondoInicial),
              if (!ocultarEfectivoEsperado)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Efectivo esperado",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      AppConfig.formatoMoneda(resumen.efectivoEsperado),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text("Lectura parcial - la caja sigue abierta"),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    return pdf;
  }

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
