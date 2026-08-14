import 'package:package_info_plus/package_info_plus.dart';

import '../database/database_helper.dart';

/// Identidad de esta compilación (versión pública, número de build y versión
/// del esquema de base de datos), disponible de forma síncrona desde cualquier
/// parte una vez que [cargar] corrió en el arranque.
///
/// Existe porque hasta ahora la app no sabía qué versión era. Cuando un
/// cliente llamaba, no había forma de preguntarle "¿qué versión tienes?" sin
/// mandarlo a "Agregar o quitar programas" de Windows y esperar que leyera
/// bien. Con varios negocios instalados y actualizaciones repartidas por
/// WhatsApp, no saber qué versión corre cada uno vuelve imposible reproducir
/// un error.
///
/// Es además el prerrequisito de [SoporteService] y de cualquier aviso de
/// actualización dentro de la app.
class AppInfo {
  AppInfo._();

  static const _desconocida = 'desconocida';

  static String _version = _desconocida;
  static String _build = '';

  /// Versión que ve el cliente ("1.0.0"). Sale de `version:` en pubspec.yaml,
  /// que es la misma que usa el instalador (ver `build_installer.ps1`).
  static String get version => _version;

  /// Número de compilación (el "+1" del pubspec). Es interno: sirve para
  /// distinguir dos instaladores publicados con la misma versión pública.
  static String get build => _build;

  /// Lo que se muestra en pantalla y en el reporte de soporte:
  /// "1.0.0 (build 1)".
  static String get versionCompleta =>
      _build.isEmpty ? _version : '$_version (build $_build)';

  /// Versión del esquema de base de datos que maneja esta compilación. Cambia
  /// con cada migración, y es el dato que de verdad importa cuando algo no
  /// cuadra entre dos instalaciones.
  static int get versionEsquema => DatabaseHelper.versionEsquema;

  /// Lee la versión desde los metadatos del ejecutable.
  ///
  /// Falla en silencio a propósito: no saber la versión estorba para
  /// diagnosticar, pero no es razón para que el negocio no pueda abrir la
  /// caja. Si esto falla, la app arranca igual y muestra "desconocida".
  static Future<void> cargar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.trim().isNotEmpty) _version = info.version.trim();
      _build = info.buildNumber.trim();
    } catch (_) {
      // Se queda en 'desconocida'.
    }
  }
}
