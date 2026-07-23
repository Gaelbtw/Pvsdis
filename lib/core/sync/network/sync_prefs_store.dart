import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Persiste la configuración de conexión de sync que NO depende de tener una
/// sesión iniciada -- hoy solo la URL del backend. Vive en un archivo JSON
/// aparte de `TokenStorage` (`sync_session.json`) a propósito: la URL se
/// configura una vez por dispositivo *antes* de iniciar sesión, y debe
/// sobrevivir un `logout()` (que borra la sesión, pero no a qué backend
/// apunta este dispositivo).
///
/// Mismo patrón e igual directorio que `TokenStorage`
/// (`getApplicationSupportDirectory`, ver
/// `lib/core/sync/network/token_storage.dart`): caché en disco de un par de
/// strings, sin sumar dependencias. Si el archivo no existe o está corrupto,
/// [leerUrlBackend] devuelve `null` y el llamador cae al default de
/// `BackendConfig` en vez de tumbar el arranque.
class SyncPrefsStore {
  static const _fileName = 'sync_prefs.json';

  Future<String> _filePath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, _fileName);
  }

  Future<String?> leerUrlBackend() async {
    final file = File(await _filePath());
    if (!await file.exists()) return null;

    try {
      final contenido = await file.readAsString();
      if (contenido.trim().isEmpty) return null;
      final map = jsonDecode(contenido) as Map<String, dynamic>;
      final url = map['baseUrl'] as String?;
      return (url == null || url.trim().isEmpty) ? null : url;
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarUrlBackend(String url) async {
    final file = File(await _filePath());
    await file.writeAsString(jsonEncode({'baseUrl': url.trim()}));
  }
}
