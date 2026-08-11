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
  /// entornos, pruebas). Usar [validar] antes para dar un mensaje decente al
  /// usuario: aquí solo se normaliza (se quitan espacios y la barra final).
  static void actualizar(String nuevaUrl) {
    final limpia = nuevaUrl.trim();
    _baseUrl = limpia.endsWith('/')
        ? limpia.replaceAll(RegExp(r'/+$'), '')
        : limpia;
  }

  /// Comprueba que [url] sea utilizable como base del API. Devuelve el motivo
  /// del rechazo, o `null` si es válida.
  ///
  /// Antes no se validaba nada: cualquier texto se aceptaba y el error solo
  /// aparecía como un fallo de red genérico en el primer request.
  static String? validar(String url) {
    final limpia = url.trim();
    if (limpia.isEmpty) return 'Escribe la dirección del servidor.';

    final uri = Uri.tryParse(limpia);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Dirección inválida. Debe incluir http:// o https:// y el nombre o IP del servidor '
          '(por ejemplo, https://192.168.1.100:5242).';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Solo se admiten direcciones http:// o https:// (recibido "${uri.scheme}://").';
    }
    return null;
  }

  /// `true` si [url] manda los datos sin cifrar hacia otra máquina.
  ///
  /// Sobre HTTP plano viajan en claro el token JWT de la sesión de
  /// sincronización y todo lo que se sincroniza: ventas, clientes, precios.
  /// Cualquiera en la misma red (un WiFi de tienda, por ejemplo) puede leerlo
  /// o alterarlo. No se bloquea porque muchas instalaciones sincronizan
  /// contra un servidor propio en la LAN sin TLS, pero la pantalla de
  /// configuración sí lo advierte.
  ///
  /// `localhost`/`127.0.0.1` no cuentan: ahí el tráfico no sale de la máquina.
  static bool esInseguro(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'http') return false;

    final host = uri.host.toLowerCase();
    return host != 'localhost' && host != '127.0.0.1' && host != '::1';
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
