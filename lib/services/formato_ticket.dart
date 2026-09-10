import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/config/app_config.dart';

/// Piezas comunes de los tickets de corte (cierre Z y lectura X).
///
/// Existen para que ambos tickets no puedan verse distintos. Antes cada
/// servicio armaba sus propias filas y encabezados con `pw.Row` a mano, y ya
/// habian empezado a divergir: el cierre listaba pagos a proveedores y el
/// Corte X no, aunque los dos decian reportar el mismo turno.
///
/// Solo texto ASCII en las etiquetas fijas: la fuente por omision del paquete
/// `pdf` es Helvetica con codificacion Latin-1, y un caracter fuera de ese
/// juego (por ejemplo el signo menos tipografico) sale como basura en el
/// papel. Los datos del negocio si pueden traer acentos, que si son Latin-1.
class FormatoTicket {
  FormatoTicket._();

  static const double _cuerpo = 9;

  static pw.Widget encabezado({
    required String negocio,
    required String titulo,
    String? direccion,
  }) {
    return pw.Center(
      child: pw.Column(
        children: [
          pw.Text(
            negocio,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (direccion != null && direccion.trim().isNotEmpty)
            pw.Text(
              direccion,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Encabezado de bloque ("EFECTIVO - LO QUE DEBE ESTAR").
  static pw.Widget titulo(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: _cuerpo, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  /// Par etiqueta/valor de texto (cajero, turno, fechas).
  static pw.Widget dato(String etiqueta, String valor) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(etiqueta, style: const pw.TextStyle(fontSize: _cuerpo)),
        pw.Text(valor, style: const pw.TextStyle(fontSize: _cuerpo)),
      ],
    );
  }

  /// Renglon de dinero. [signo] ocupa siempre el mismo lugar (aunque sea un
  /// espacio) para que la columna de conceptos quede alineada y la cuenta se
  /// lea como cuenta.
  static pw.Widget renglon(String etiqueta, double importe, {String signo = ''}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          signo.isEmpty ? etiqueta : '$signo $etiqueta',
          style: const pw.TextStyle(fontSize: _cuerpo),
        ),
        pw.Text(
          AppConfig.formatoMoneda(importe),
          style: const pw.TextStyle(fontSize: _cuerpo),
        ),
      ],
    );
  }

  /// Resultado de un bloque: el renglon que cierra la cuenta de arriba.
  static pw.Widget total(String etiqueta, double importe) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(etiqueta,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text(AppConfig.formatoMoneda(importe),
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  /// Linea de firma. Un corte es una entrega de dinero entre dos personas: sin
  /// firmas es un papel que cualquiera vuelve a imprimir.
  static pw.Widget firma(String etiqueta, String subtitulo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$etiqueta ____________________',
            style: const pw.TextStyle(fontSize: _cuerpo)),
        pw.Text('        $subtitulo',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    );
  }

  /// Fecha ISO a "14/08/26 08:04". El ticket imprimia el ISO crudo, con
  /// milisegundos incluidos, que no le sirve a nadie parado en el mostrador.
  static String fecha(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${dos(d.year % 100)} ${dos(d.hour)}:${dos(d.minute)}';
  }
}
