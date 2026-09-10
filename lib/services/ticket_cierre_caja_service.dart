import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';
import '../controllers/caja_controller.dart';
import '../models/conteo_denominaciones.dart';
import 'formato_ticket.dart';

/// Ticket de **cierre de caja (Corte Z)**.
///
/// El corte impreso es el documento con el que se entrega el dinero, y hasta
/// ahora no se podia comprobar con el papel en la mano: traia casi todos los
/// datos correctos, pero repartidos en bloques que no sumaban entre si. El
/// fondo inicial caia en una seccion propia DESPUES de las ventas, y el
/// "Efectivo esperado" aparecia al final sin nada que lo respaldara.
///
/// Ahora el ticket tiene tres bloques y cada uno cierra solo:
///
/// 1. **EFECTIVO** — los sumandos con su signo y el esperado como resultado.
/// 2. **CONTEO** — lo que el cajero declaro, denominacion por denominacion, y
///    el contado como resultado. La diferencia sale de restar los dos.
/// 3. **NO PASA POR EL CAJON** — tarjeta y transferencia, fuera del arqueo,
///    porque ese dinero nunca estuvo en el cajon.
class TicketCierreCajaService {
  static Future<pw.Document> generarCierre({
    required String fechaApertura,
    required String fechaCierre,
    required String cajero,
    required ResumenCaja resumen,
    required double contado,
    required double diferencia,
    ConteoDenominaciones? conteo,
    bool pedirFirmas = false,
    String? observacionesApertura,
    String? observacionesCierre,
  }) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;
    final turno = AppConfig.turnoDeIso(fechaApertura);

    pdf.addPage(
      pw.Page(
        pageFormat: AppConfig.formatoPapel, // termico
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              FormatoTicket.encabezado(
                negocio: config.nombreNegocio,
                titulo: 'CORTE DE CAJA (Z)',
                direccion: config.direccion,
              ),

              pw.Divider(),

              FormatoTicket.dato('Cajero', cajero),
              if (turno != null) FormatoTicket.dato('Turno', turno),
              FormatoTicket.dato('Apertura', FormatoTicket.fecha(fechaApertura)),
              FormatoTicket.dato('Cierre', FormatoTicket.fecha(fechaCierre)),
              FormatoTicket.dato('Tickets', '${resumen.ticketsCerrados}'),
              if (observacionesApertura != null && observacionesApertura.isNotEmpty)
                pw.Text('Obs. apertura: $observacionesApertura'),
              if (observacionesCierre != null && observacionesCierre.isNotEmpty)
                pw.Text('Obs. cierre: $observacionesCierre'),

              pw.Divider(),

              // 1. De donde sale el efectivo esperado. Los mismos renglones
              // que dibuja la pantalla (ver `ResumenCaja.renglonesEfectivo`):
              // si alguna vez difirieran, el cajero tendria dos cuentas
              // distintas del mismo turno y ninguna forma de saber cual vale.
              FormatoTicket.titulo('EFECTIVO - LO QUE DEBE ESTAR'),
              // El primer renglon es siempre el fondo inicial: es la base de la
              // cuenta, no una suma, y por eso lleva un espacio donde los
              // demas llevan su signo.
              for (final (i, r) in resumen.renglonesEfectivo.indexed)
                FormatoTicket.renglon(
                  r.etiqueta,
                  r.importe,
                  signo: i == 0 ? ' ' : (r.suma ? '+' : '-'),
                ),
              pw.Divider(),
              FormatoTicket.total('= ESPERADO', resumen.efectivoEsperado),

              // 2. Lo que se conto. Sin el desglose, el total contado es un
              // numero sin respaldo: si manana se discute el faltante, esto es
              // la unica evidencia de que se conto.
              pw.SizedBox(height: 8),
              FormatoTicket.titulo('CONTEO DEL CAJON'),
              if (conteo != null && !conteo.sinCapturar)
                for (final r in conteo.renglones)
                  FormatoTicket.renglon('  ${r.etiqueta}', r.importe)
              else
                pw.Text('  (sin desglose por denominacion)'),
              pw.Divider(),
              FormatoTicket.total('= CONTADO', contado),

              pw.SizedBox(height: 10),
              _veredicto(diferencia),

              // 3. Fuera del arqueo, a proposito.
              pw.Divider(),
              FormatoTicket.titulo('NO PASA POR EL CAJON'),
              FormatoTicket.renglon('  Tarjeta', resumen.ventasTarjeta),
              FormatoTicket.renglon('  Transferencia', resumen.ventasTransferencia),
              if (resumen.anticiposTarjeta > 0)
                FormatoTicket.renglon('  Anticipos c/tarjeta', resumen.anticiposTarjeta),
              if (resumen.anticiposTransferencia > 0)
                FormatoTicket.renglon('  Anticipos c/transf.', resumen.anticiposTransferencia),
              FormatoTicket.renglon('  Total', resumen.totalNoEfectivo),

              pw.Divider(),
              FormatoTicket.total('VENDIDO EN EL TURNO', resumen.totalVentas),

              if (pedirFirmas) ...[
                pw.Divider(),
                pw.SizedBox(height: 6),
                FormatoTicket.firma('Entrega', cajero),
                pw.SizedBox(height: 10),
                FormatoTicket.firma('Recibe', 'nombre y firma'),
              ],

              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                  'Pv Control - ${FormatoTicket.fecha(fechaCierre)}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  /// El resultado del arqueo, centrado y grande. Es lo unico del ticket que
  /// alguien busca de un vistazo.
  static pw.Widget _veredicto(double diferencia) {
    final cuadra = diferencia.abs() < 0.005;
    final etiqueta = cuadra
        ? 'CUADRA EXACTO'
        : diferencia > 0
            ? '***  SOBRANTE  ***'
            : '***  FALTANTE  ***';

    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(etiqueta, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (!cuadra)
            pw.Text(
              AppConfig.formatoMoneda(diferencia),
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: diferencia > 0 ? PdfColors.green : PdfColors.red,
              ),
            ),
        ],
      ),
    );
  }
}
