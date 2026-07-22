/// Excepciones del cliente HTTP hacia el backend EsqPos.API. Separadas a
/// propósito de las excepciones de SQLite (`db_exceptions.dart`): quien
/// llama necesita reaccionar distinto -- un error de red no es un error de
/// datos, y una sesión expirada dispara un refresh/relogin, no un mensaje
/// de validación.

/// Error base de cualquier llamada al backend. Los demás tipos de esta
/// jerarquía lo extienden; capturar `on ErrorApi` alcanza para manejar
/// cualquier falla de sincronización de forma genérica.
class ErrorApi implements Exception {
  final String mensaje;

  ErrorApi(this.mensaje);

  @override
  String toString() => mensaje;
}

/// No hubo forma de completar el request: backend caído, sin conexión,
/// timeout, DNS, etc. No implica necesariamente que el dispositivo esté
/// offline (el backend puede estar simplemente apagado), pero para la UI
/// el tratamiento es el mismo: mostrar "sin conexión" y seguir operando
/// con los datos locales.
class ErrorRed extends ErrorApi {
  ErrorRed([String mensaje = 'No se pudo conectar con el servidor. Verifica tu conexión.']) : super(mensaje);
}

/// El backend respondió pero con un código de error HTTP (4xx/5xx) que no
/// es una sesión expirada. Conserva el `statusCode` y el cuerpo crudo por
/// si quien llama necesita distinguir casos (ej. 400 de validación vs 500).
class ErrorRespuestaApi extends ErrorApi {
  final int statusCode;
  final String? cuerpo;

  ErrorRespuestaApi(this.statusCode, String mensaje, {this.cuerpo}) : super(mensaje);
}

/// 401 Unauthorized: el access token expiró, es inválido, o el refresh
/// también falló. Quien llama (típicamente `SyncClient`, que ya intentó un
/// refresh automático) debe mandar al usuario a loguearse de nuevo contra
/// el backend -- no confundir con el login local de cajeros
/// (`AuthController`/`Usuarios`), que sigue funcionando sin esto.
class SesionExpiradaException extends ErrorApi {
  SesionExpiradaException([String mensaje = 'La sesión con el servidor expiró. Vuelve a iniciar sesión.'])
      : super(mensaje);
}
