import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/database/database_helper.dart';
import '../core/utils/csv.dart';

/// Exporta reportes a CSV en la carpeta de datos de la app.
///
/// No usa un diálogo "Guardar como" a propósito: el archivo va siempre a
/// `exportaciones/` (junto a `backups/`), con un nombre que lleva la fecha y
/// el rango, y después se abre esa carpeta en el Explorador. Para una terminal
/// de punto de venta —donde suele operar alguien que no es el dueño del
/// equipo— es más predecible que dejar elegir una ruta cualquiera, y evita el
/// caso clásico de "lo guardé pero no sé dónde".
class ExportacionService {
  final _dbHelper = DatabaseHelper();

  /// Escribe [contenido] como `<nombreBase>_<timestamp>.csv` y devuelve la
  /// ruta completa.
  ///
  /// Se escribe con [utf8] explícito: `writeAsString` usa UTF-8 por defecto,
  /// pero dejarlo implícito aquí sería frágil -- el BOM que agrega
  /// [construirCsv] solo sirve si los bytes de verdad salen en UTF-8.
  Future<String> guardarCsv({
    required String nombreBase,
    required String contenido,
  }) async {
    final dir = Directory(await _dbHelper.getExportDirectoryPath());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ruta = p.join(dir.path, '${nombreBase}_${_timestamp()}.csv');
    await File(ruta).writeAsString(contenido, encoding: utf8);
    return ruta;
  }

  /// Exporta una tabla y devuelve la ruta del archivo generado.
  Future<String> exportarTabla({
    required String nombreBase,
    required List<String> encabezados,
    required List<List<Object?>> filas,
  }) {
    return guardarCsv(
      nombreBase: nombreBase,
      contenido: construirCsv(encabezados: encabezados, filas: filas),
    );
  }

  /// Abre en el Explorador de Windows la carpeta que contiene [rutaArchivo],
  /// con el archivo ya seleccionado.
  ///
  /// Best-effort: si falla (otro sistema operativo, Explorer no disponible),
  /// no se propaga el error. El archivo ya está escrito y la UI muestra la
  /// ruta de todos modos, así que no poder abrir la carpeta es un detalle de
  /// comodidad, no un fallo de la exportación.
  Future<void> abrirCarpeta(String rutaArchivo) async {
    if (!Platform.isWindows) return;
    try {
      // UN SOLO argumento: `/select,` y la ruta van pegados. Explorer no
      // acepta `/select,` y la ruta como argumentos separados -- ignora la
      // opción y abre una ventana en Documentos, que parece que la
      // exportación falló cuando en realidad el archivo sí se escribió.
      //
      // Tampoco se mira el código de salida: explorer.exe devuelve 1 incluso
      // cuando funciona.
      await Process.run('explorer.exe', ['/select,$rutaArchivo']);
    } catch (_) {
      // Ignorado a propósito (ver doc de arriba).
    }
  }

  /// `20260808_143052` -- ordenable alfabéticamente y sin caracteres que
  /// Windows prohíba en nombres de archivo (los `:` de un ISO-8601 sí lo son).
  String _timestamp() {
    final v = DateTime.now();
    final y = v.year.toString();
    final m = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    final hh = v.hour.toString().padLeft(2, '0');
    final mm = v.minute.toString().padLeft(2, '0');
    final ss = v.second.toString().padLeft(2, '0');
    // Llaves en `${d}`: sin ellas `$d_` se leería como la variable `d_`.
    return '$y$m${d}_$hh$mm$ss';
  }
}
