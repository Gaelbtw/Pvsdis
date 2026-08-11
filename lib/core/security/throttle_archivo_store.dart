import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'login_throttle.dart';

/// Guarda el estado del [LoginThrottle] en un JSON dentro del directorio de
/// datos de la app, junto a `pos.db` y `sync_session.json`.
///
/// Todas las operaciones son best-effort: si el archivo no existe, está
/// corrupto o el disco falla, se trata como "sin estado guardado" en vez de
/// propagar el error. El throttle es una defensa, no una función crítica —
/// que no se pueda leer su archivo NUNCA debe impedir que alguien entre a
/// cobrar. En el peor caso se degrada al comportamiento anterior (contador
/// solo en memoria).
class ThrottleArchivoStore implements ThrottlePersistencia {
  static const _nombreArchivo = 'login_throttle.json';

  Future<File> _archivo() async {
    final dir = await getApplicationSupportDirectory();
    return File(join(dir.path, _nombreArchivo));
  }

  @override
  Future<Map<String, EstadoThrottle>?> leer() async {
    try {
      final archivo = await _archivo();
      if (!await archivo.exists()) return null;

      final contenido = await archivo.readAsString();
      if (contenido.trim().isEmpty) return null;

      final crudo = jsonDecode(contenido);
      if (crudo is! Map) return null;

      final resultado = <String, EstadoThrottle>{};
      crudo.forEach((clave, valor) {
        final estado = EstadoThrottle.desdeMapa(valor);
        if (estado != null) resultado[clave.toString()] = estado;
      });
      return resultado;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar(Map<String, EstadoThrottle> estado) async {
    try {
      final archivo = await _archivo();

      // Sin nada que recordar se borra el archivo en vez de dejar un `{}`.
      if (estado.isEmpty) {
        if (await archivo.exists()) await archivo.delete();
        return;
      }

      final mapa = estado.map((clave, valor) => MapEntry(clave, valor.aMapa()));
      await archivo.writeAsString(jsonEncode(mapa));
    } catch (_) {
      // Ver la nota de la clase: no se propaga.
    }
  }
}
