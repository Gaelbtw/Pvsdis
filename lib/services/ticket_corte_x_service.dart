import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';
import '../controllers/caja_controller.dart';
import 'formato_ticket.dart';

/// Ticket de **Corte X (lectura)**: una foto del turno SIN cerrarlo. No pide
/// efectivo contado ni calcula diferencia.
///
/// Lleva la misma estructura que el cierre (mismos bloques, mismos renglones,
/// mismo orden) para que comparar un X con el Z del final del turno sea leer
/// dos papeles iguales, y no traducir de un formato a otro.
class TicketCorteXService {
  /// [ocultarEfectivo] omite el bloque completo del efectivo: los sumandos y
  /// el total.
  ///
  /// No basta con esconder el "efectivo esperado", que es lo que se hacia
  /// antes. Si el ticket trae el fondo inicial, las ventas en efectivo, el
  /// cambio y las devoluciones, el esperado se obtiene sumando: el cajero
  /// imprime un Corte X, hace la cuenta y captura ese numero al cerrar. La
  /// regla es la misma de la pantalla (ver `VistaCorte`): si es sumando del
  /// esperado, quien cuenta a ciegas no lo ve antes de cerrar.
  static Future<pw.Document> generar({
    required String cajero,
    required String fechaApertura,
    required String fechaCorte,
    required ResumenCaja resumen,
    bool ocultarEfectivo = false,
  }) async {
    final pdf = pw.Document();
    final config = AppConfig.actual;
    final turno = AppConfig.turnoDeIso(fechaApertura);

    pdf.addPage(
      pw.Page(
        pageFormat: AppConfig.formatoPapel,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              FormatoTicket.encabezado(
                negocio: config.nombreNegocio,
                titulo: 'CORTE X (LECTURA)',
                direccion: config.direccion,
              ),

              pw.Divider(),

              FormatoTicket.dato('Cajero', cajero),
              if (turno != null) FormatoTicket.dato('Turno', turno),
              FormatoTicket.dato('Apertura', FormatoTicket.fecha(fechaApertura)),
              FormatoTicket.dato('Corte', FormatoTicket.fecha(fechaCorte)),
              FormatoTicket.dato('Tickets', '${resumen.ticketsCerrados}'),

              if (!ocultarEfectivo) ...[
                pw.Divider(),
                FormatoTicket.titulo('EFECTIVO - LO QUE DEBE ESTAR'),
                for (final (i, r) in resumen.renglonesEfectivo.indexed)
                  FormatoTicket.renglon(
                    r.etiqueta,
                    r.importe,
                    signo: i == 0 ? ' ' : (r.suma ? '+' : '-'),
                  ),
                pw.Divider(),
                FormatoTicket.total('= ESPERADO', resumen.efectivoEsperado),
              ],

              pw.Divider(),
              FormatoTicket.titulo('NO PASA POR EL CAJON'),
              FormatoTicket.renglon('  Tarjeta', resumen.ventasTarjeta),
              FormatoTicket.renglon('  Transferencia', resumen.ventasTransferencia),
              if (resumen.anticiposTarjeta > 0)
                FormatoTicket.renglon('  Anticipos c/tarjeta', resumen.anticiposTarjeta),
              if (resumen.anticiposTransferencia > 0)
                FormatoTicket.renglon('  Anticipos c/transf.', resumen.anticiposTransferencia),
              FormatoTicket.renglon('  Total', resumen.totalNoEfectivo),

              if (!ocultarEfectivo) ...[
                pw.Divider(),
                FormatoTicket.total('VENDIDO EN EL TURNO', resumen.totalVentas),
              ],

              pw.SizedBox(height: 14),
              pw.Center(
                child: pw.Text(
                  ocultarEfectivo
                      ? 'Lectura parcial - el efectivo se revela al cerrar'
                      : 'Lectura parcial - la caja sigue abierta',
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
}
