import 'models/sync_auth_models.dart';
import 'network/api_exceptions.dart';
import 'network/api_http_client.dart';
import 'network/token_storage.dart';

/// Sesión del negocio contra el backend EsqPos.API (login/logout/refresh) y
/// caché en memoria de la sesión vigente. Es el único lugar de la app que
/// debería llamar `/api/auth/*` -- `SyncClient` depende de este servicio
/// para obtener un access token válido, nunca llama login/refresh por su
/// cuenta.
///
/// No confundir con `Authcontroller`/`lib/controllers/auth_controller.dart`,
/// que maneja el login LOCAL de cajeros contra `pos.db` (bcrypt, sin red).
/// Ambos sistemas de sesión son independientes: un dispositivo puede seguir
/// vendiendo offline con su sesión local aunque esta sesión de
/// sincronización esté vencida o nunca se haya iniciado.
class AuthService {
  AuthService({ApiHttpClient? http, TokenStorage? storage})
      : _http = http ?? ApiHttpClient(),
        _storage = storage ?? TokenStorage();

  final ApiHttpClient _http;
  final TokenStorage _storage;

  SesionSync? _sesionActual;

  /// Datos de la sesión de sincronización vigente, o `null` si nunca se hizo
  /// login (o se cerró sesión). Se actualiza en memoria en cada
  /// login/refresh/logout; para leerla desde disco al arrancar la app usa
  /// [inicializar].
  SesionSync? get sesionActual => _sesionActual;

  bool get estaAutenticado => _sesionActual != null;

  /// Carga la sesión persistida (si existe) a memoria. Se llama una vez al
  /// arrancar la app, antes de decidir si mostrar el estado
  /// sincronizado/no-sincronizado. Si el archivo no existe o está corrupto,
  /// [TokenStorage.leer] ya devuelve `null` en vez de lanzar.
  Future<void> inicializar() async {
    _sesionActual = await _storage.leer();
  }

  /// Inicia sesión contra el backend y persiste el resultado. Lanza
  /// [ErrorRed] si no hay red, o [ErrorRespuestaApi] con el mensaje real del
  /// backend ("Credenciales inválidas.", "La cuenta está temporalmente
  /// bloqueada...", etc.) si el login falla.
  ///
  /// Login es `[AllowAnonymous]`, pero el backend igual devuelve 401 para
  /// credenciales inválidas (vía `UnauthorizedAppException`), y
  /// [ApiHttpClient] traduce todo 401 a [SesionExpiradaException] --
  /// correcto para un request autenticado que dejó de serlo, pero un tipo
  /// confuso para "el intento de login que acabas de hacer fue rechazado"
  /// (el usuario está EN la pantalla de login, no hay sesión que "expiró").
  /// Por eso acá se recapturan y se re-lanzan como [ErrorRespuestaApi],
  /// conservando el mensaje real que ya trae el backend.
  Future<SesionSync> login(String email, String password) async {
    final Map<String, dynamic> respuesta;
    try {
      respuesta = await _http.post(
        '/api/auth/login',
        body: LoginRequest(email: email, password: password).toJson(),
      ) as Map<String, dynamic>;
    } on SesionExpiradaException catch (e) {
      throw ErrorRespuestaApi(401, e.mensaje);
    }

    final sesion = SesionSync.desdeLogin(LoginResponse.fromJson(respuesta));
    await _storage.guardar(sesion);
    _sesionActual = sesion;
    return sesion;
  }

  /// Cierra la sesión: revoca el refresh token en el backend (best-effort --
  /// si no hay red, igual se borra la sesión local, porque el usuario ya
  /// decidió salir y no debe quedar atrapado por un backend inalcanzable) y
  /// borra la sesión persistida.
  Future<void> logout() async {
    final sesion = _sesionActual;
    if (sesion != null) {
      try {
        await _http.post('/api/auth/logout', body: RefreshTokenRequest(sesion.refreshToken).toJson());
      } on ErrorApi {
        // Best-effort: el refresh token quedará revocado del lado del
        // servidor solo cuando expire naturalmente, pero el dispositivo ya
        // no lo usará (se borra abajo de todas formas).
      }
    }
    await _storage.borrar();
    _sesionActual = null;
  }

  /// Access token listo para usar en el header `Authorization`. Si está por
  /// expirar (dentro del margen de [SesionSync.accessTokenPorExpirar]) lo
  /// refresca primero de forma proactiva -- así ninguna llamada a
  /// `SyncClient` arranca con un token que vence a mitad de la respuesta.
  ///
  /// Lanza [SesionExpiradaException] si no hay sesión, o si el refresh
  /// falla (el refresh token también expiró o fue revocado): en ambos casos
  /// la sesión local se borra, porque ya no sirve para nada.
  Future<String> obtenerAccessTokenValido() async {
    final sesion = _sesionActual;
    if (sesion == null) throw SesionExpiradaException('No hay una sesión de sincronización iniciada.');

    if (!sesion.accessTokenPorExpirar) return sesion.accessToken;

    return _refrescar(sesion);
  }

  Future<String> _refrescar(SesionSync sesionVieja) async {
    try {
      final respuesta = await _http.post(
        '/api/auth/refresh-token',
        body: RefreshTokenRequest(sesionVieja.refreshToken).toJson(),
      );
      final nueva = SesionSync.desdeLogin(LoginResponse.fromJson(respuesta as Map<String, dynamic>));
      await _storage.guardar(nueva);
      _sesionActual = nueva;
      return nueva.accessToken;
    } on ErrorRed {
      // Sin red: el token viejo puede seguir siendo válido del lado del
      // servidor todavía (el margen de refresco es preventivo, no
      // definitivo). Se devuelve el que había en vez de tumbar la operación
      // -- si de verdad ya expiró, el propio request que lo use recibirá un
      // 401 real y ApiHttpClient lo convertirá en SesionExpiradaException.
      return sesionVieja.accessToken;
    } on ErrorApi catch (e) {
      // El refresh token fue rechazado (expiró, se revocó, o el usuario
      // cerró sesión desde otro dispositivo): no hay forma de recuperar la
      // sesión sin volver a loguearse. A diferencia de login(), acá SÍ es
      // el tipo correcto -- "hay que volver a autenticarse" es exactamente
      // lo que significa. Se conserva el mensaje real del backend cuando
      // vino uno (ej. "El token de actualización no es válido o ha
      // expirado."), cubriendo tanto SesionExpiradaException (401) como
      // ErrorRespuestaApi (otro código de error del endpoint).
      await _storage.borrar();
      _sesionActual = null;
      throw SesionExpiradaException(e.mensaje);
    }
  }
}
