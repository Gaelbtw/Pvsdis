import 'auth_service.dart';
import 'models/sync_dtos.dart';
import 'network/api_http_client.dart';

/// Cliente del contrato `/api/sync` del backend (ver
/// `docs/sync-desktop-fase2.md` §2). Cada llamada arma el header
/// `Authorization: Bearer <token>` pidiendo un access token vigente a
/// [AuthService] (que lo refresca proactivamente si está por vencer), así
/// que quien use esta clase no necesita preocuparse por el ciclo de vida
/// del token.
///
/// Solo hace las llamadas HTTP y parsea la respuesta -- NO decide qué
/// entidades sincronizar, ni persiste nada en `pos.db`. Eso (tablas espejo
/// locales con columna `guid_sync`, cola de outbox para el push) es el
/// siguiente paso de esta integración, según `lib/core/sync/README-fase2.md`.
class SyncClient {
  SyncClient({ApiHttpClient? http, required AuthService authService})
      : _http = http ?? ApiHttpClient(),
        _authService = authService;

  final ApiHttpClient _http;
  final AuthService _authService;

  Future<Map<String, String>> _headersAutenticados() async {
    final token = await _authService.obtenerAccessTokenValido();
    return {'Authorization': 'Bearer $token'};
  }

  /// `GET /api/sync/entidades`. Catálogo de nombres de entidad que el
  /// backend acepta sincronizar (ej. `Producto`, `Venta`, `Promocion`) --
  /// útil para no hardcodear la lista en el cliente y detectar cuando el
  /// backend habilita una entidad nueva.
  Future<List<String>> obtenerEntidades() async {
    final respuesta = await _http.get('/api/sync/entidades', headers: await _headersAutenticados());
    return (respuesta as List<dynamic>).map((e) => e as String).toList();
  }

  /// `GET /api/sync/{entidad}?desde=&limite=`. Pull incremental: [desde] es
  /// la última `ultimaFechaModificacion` que el cliente ya tiene guardada
  /// para esta entidad (UTC); se omite en la primera sincronización. La
  /// respuesta incluye borrados lógicos (`isDeleted: true` dentro de cada
  /// elemento) -- el llamador debe borrar su copia local en vez de
  /// descartarlos.
  ///
  /// [limite] sigue el default del backend (500) si se omite; el backend lo
  /// acota a 1000 igualmente si se pide más.
  Future<SyncPullResponse> pull(String entidad, {DateTime? desde, int? limite}) async {
    final query = <String, String>{
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (limite != null) 'limite': '$limite',
    };
    final respuesta = await _http.get(
      '/api/sync/$entidad',
      query: query,
      headers: await _headersAutenticados(),
    );
    return SyncPullResponse.fromJson(respuesta as Map<String, dynamic>);
  }

  /// `POST /api/sync/push`. Envía un lote de cambios locales. El backend los
  /// aplica en el orden recibido (no es transaccional entre ítems): el
  /// llamador es responsable de ordenar [request] padre-antes-que-hijo (ver
  /// [SyncPushRequest]).
  Future<SyncPushResponse> push(SyncPushRequest request) async {
    final respuesta = await _http.post(
      '/api/sync/push',
      body: request.toJson(),
      headers: await _headersAutenticados(),
    );
    return SyncPushResponse.fromJson(respuesta as Map<String, dynamic>);
  }
}
