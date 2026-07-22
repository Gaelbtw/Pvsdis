import '../auth_service.dart';
import '../models/sucursal_dto.dart';
import '../network/api_http_client.dart';

/// Cliente delgado de `GET /api/sucursales` (`EsqueletoPOS/src/EsqPos.API/
/// Controllers/SucursalesController.cs`). Mismo patrón de inyección que
/// `SyncClient`: arma el header `Authorization` pidiendo un access token
/// vigente a [AuthService], no llama login/refresh por su cuenta.
///
/// Solo la lectura (`ObtenerTodas`) -- crear/editar/desactivar sucursales
/// es una operación administrativa que no le compete al motor de sync del
/// Flutter, que solo necesita resolver A CUÁL sucursal pertenece este
/// dispositivo (ver [SucursalResolver]).
class SucursalesClient {
  SucursalesClient({ApiHttpClient? http, required AuthService authService})
      : _http = http ?? ApiHttpClient(),
        _authService = authService;

  final ApiHttpClient _http;
  final AuthService _authService;

  Future<Map<String, String>> _headersAutenticados() async {
    final token = await _authService.obtenerAccessTokenValido();
    return {'Authorization': 'Bearer $token'};
  }

  /// Todas las sucursales del tenant de la sesión vigente.
  Future<List<SucursalDto>> obtenerTodas() async {
    final respuesta = await _http.get('/api/sucursales', headers: await _headersAutenticados());
    return (respuesta as List<dynamic>)
        .map((e) => SucursalDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
