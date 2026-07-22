import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sync_auth_models.dart';

/// Persiste la sesión de sincronización (tokens + datos del usuario
/// logueado contra el backend) en un archivo JSON plano, en el mismo
/// directorio de datos de la app que ya usa `DatabaseHelper` (vía
/// `path_provider` -- ver `lib/core/database/database_helper.dart`,
/// `_getBaseDirectoryPath`).
///
/// Decisión de diseño (Fase 2): no se agrega `flutter_secure_storage`. Ese
/// paquete tiene una implementación nativa distinta por plataforma
/// (Keychain en macOS/iOS, Credential Manager en Windows, Keystore en
/// Android) que suma peso, plugins nativos y superficie de configuración
/// solo para guardar dos strings. El archivo queda en el directorio
/// privado de datos de la app, con los mismos permisos de sistema de
/// archivos que ya protegen `pos.db` (que guarda hashes bcrypt de
/// contraseñas locales sin cifrado adicional): no es peor que lo que ya
/// existe hoy en este proyecto. Si más adelante se necesita cifrado en
/// reposo, el cambio queda contenido a esta clase (misma API pública).
class TokenStorage {
  static const _fileName = 'sync_session.json';

  Future<String> _filePath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, _fileName);
  }

  Future<void> guardar(SesionSync sesion) async {
    final file = File(await _filePath());
    await file.writeAsString(jsonEncode(sesion.toMap()));
  }

  /// `null` si nunca se guardó una sesión, o si el archivo está corrupto /
  /// en un formato viejo (se trata igual que "sin sesión" en vez de tumbar
  /// el arranque de la app).
  Future<SesionSync?> leer() async {
    final file = File(await _filePath());
    if (!await file.exists()) return null;

    try {
      final contenido = await file.readAsString();
      if (contenido.trim().isEmpty) return null;
      return SesionSync.fromMap(jsonDecode(contenido) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> borrar() async {
    final file = File(await _filePath());
    if (await file.exists()) {
      await file.delete();
    }
  }
}
