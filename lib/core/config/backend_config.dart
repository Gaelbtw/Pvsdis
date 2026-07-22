/// Configuración de conexión al backend EsqPos.API (contrato `/api/sync` y
/// `/api/auth` -- ver `docs/sync-desktop-fase2.md` en el repo EsqueletoPOS).
///
/// Mismo patrón que `AppConfig` (`app_config.dart`): caché estático en
/// memoria, disponible desde cualquier parte del código (servicios,
/// controllers) sin pasar `BuildContext`. A diferencia de `AppConfig`, esta
/// fase no lo persiste en la base de datos local: elegir a qué backend
/// apuntar es una configuración de instalación (una por dispositivo, no por
/// negocio), y esta app puede seguir operando 100% offline sin él. Cuando
/// exista una pantalla de "Configuración de sincronización", lo más simple
/// es sumar la URL al mismo archivo de sesión que ya usa `TokenStorage`
/// (`lib/core/sync/network/token_storage.dart`) al llamar [actualizar], en
/// vez de agregar una dependencia nueva solo para persistir un string.
class BackendConfig {
  BackendConfig._();

  /// Backend local de desarrollo: `dotnet run` en `EsqPos.API` expone HTTP
  /// en el puerto 5242 por defecto (ver
  /// `src/EsqPos.API/Properties/launchSettings.json` del repo EsqueletoPOS).
  static const String _urlPorDefecto = 'http://localhost:5242';

  static String _baseUrl = _urlPorDefecto;

  static String get baseUrl => _baseUrl;

  /// Cambia el backend en caliente (pantalla de configuración, distintos
  /// entornos, pruebas). No valida el formato de la URL -- el primer
  /// request que falle lo hará evidente (ver `ErrorRed` en
  /// `lib/core/sync/network/api_exceptions.dart`).
  static void actualizar(String nuevaUrl) {
    final limpia = nuevaUrl.trim();
    _baseUrl = limpia.endsWith('/')
        ? limpia.replaceAll(RegExp(r'/+$'), '')
        : limpia;
  }

  /// Restaura la URL por defecto (útil en tests).
  static void restablecer() => _baseUrl = _urlPorDefecto;

  /// Arma la URL completa para un path del API (ej. `/api/sync/entidades`),
  /// agregando query params si se pasan.
  static Uri apiUri(String path, [Map<String, String>? query]) {
    final pathNormalizado = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl$pathNormalizado');
    return (query == null || query.isEmpty) ? uri : uri.replace(queryParameters: query);
  }

  /// `GET /health` -- healthcheck sin autenticación que usa
  /// `ConectividadProbe` para el badge en línea/sin conexión.
  static Uri get healthUri => apiUri('/health');

  /// Timeout de red para llamadas normales del API (login, pull, push).
  static const Duration timeoutConexion = Duration(seconds: 10);
}
