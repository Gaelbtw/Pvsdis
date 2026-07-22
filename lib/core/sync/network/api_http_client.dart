import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config/backend_config.dart';
import 'api_exceptions.dart';

/// Envoltorio delgado sobre `package:http` para hablar con `EsqPos.API`:
/// arma la URL a partir de `BackendConfig.baseUrl`, serializa/deserializa
/// JSON y traduce errores de transporte y códigos HTTP a las excepciones de
/// `api_exceptions.dart`.
///
/// No sabe nada de autenticación -- eso lo agrega quien lo usa, pasando el
/// header `Authorization` ya armado (`AuthService` para login/refresh, que
/// no lo necesitan; `SyncClient` para el resto, que sí). Mantenerlo así de
/// simple evita un ciclo de dependencia entre "el cliente que agrega el
/// token" y "el servicio que sabe refrescar el token".
class ApiHttpClient {
  ApiHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// `GET` con query params opcionales. Devuelve el cuerpo ya decodificado
  /// (`Map`, `List`, o `null` si la respuesta vino vacía, ej. `204`).
  Future<dynamic> get(String path, {Map<String, String>? query, Map<String, String>? headers}) {
    return _ejecutar('GET', BackendConfig.apiUri(path, query), headers: headers);
  }

  /// `POST` con `body` codificado como JSON.
  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) {
    return _ejecutar('POST', BackendConfig.apiUri(path), headers: headers, body: body);
  }

  Future<dynamic> _ejecutar(
    String metodo,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final headersCompletos = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };

    http.Response respuesta;
    try {
      switch (metodo) {
        case 'GET':
          respuesta = await _client.get(uri, headers: headersCompletos).timeout(BackendConfig.timeoutConexion);
          break;
        case 'POST':
          respuesta = await _client
              .post(uri, headers: headersCompletos, body: body != null ? jsonEncode(body) : null)
              .timeout(BackendConfig.timeoutConexion);
          break;
        default:
          throw ArgumentError('Método HTTP no soportado: $metodo');
      }
    } on SocketException {
      throw ErrorRed();
    } on TimeoutException {
      throw ErrorRed('El servidor no respondió a tiempo.');
    } on http.ClientException {
      throw ErrorRed();
    } on HttpException {
      throw ErrorRed();
    }

    return _procesarRespuesta(respuesta);
  }

  dynamic _procesarRespuesta(http.Response respuesta) {
    final exito = respuesta.statusCode >= 200 && respuesta.statusCode < 300;

    // Se decodifica `bodyBytes` como UTF-8 explícitamente en vez de usar
    // `respuesta.body`: ese getter de package:http cae a latin1 si el
    // backend no manda un charset explícito en `Content-Type`, y esta app
    // habla español con acentos/ñ en todas partes (nombres de productos,
    // mensajes de error de FluentValidation, etc.) -- un charset mal
    // detectado los corrompería en silencio ("inválidas" -> "invÃ¡lidas").
    final cuerpoTexto = utf8.decode(respuesta.bodyBytes, allowMalformed: true);

    dynamic decodificado;
    if (cuerpoTexto.isNotEmpty) {
      try {
        decodificado = jsonDecode(cuerpoTexto);
      } catch (_) {
        // Cuerpo no-JSON (ej. una página de error de IIS/nginx delante del
        // API): se ignora el parseo y se usa el mensaje genérico de abajo.
        decodificado = null;
      }
    }

    if (exito) return decodificado;

    if (respuesta.statusCode == 401) {
      // El backend usa 401 para varios casos con mensajes bien distintos:
      // sesión realmente vencida en un endpoint autenticado, pero también
      // "credenciales inválidas" o "cuenta bloqueada" en login, o "token de
      // actualización inválido/expirado" en refresh (todos vía
      // `UnauthorizedAppException`, con el mensaje real en el `title` del
      // ProblemDetails). Se propaga ese mensaje cuando el backend lo manda;
      // el 401 "puro" de JWT bearer (token ausente/corrupto en un endpoint
      // protegido) no trae cuerpo, así que cae al mensaje genérico por
      // defecto de [SesionExpiradaException].
      final mensajeServidor = _extraerMensajeDeError(decodificado);
      throw mensajeServidor != null ? SesionExpiradaException(mensajeServidor) : SesionExpiradaException();
    }

    final mensaje = _extraerMensajeDeError(decodificado) ?? 'Error del servidor (${respuesta.statusCode}).';
    throw ErrorRespuestaApi(respuesta.statusCode, mensaje, cuerpo: cuerpoTexto);
  }

  /// ASP.NET Core (ProblemDetails / FluentValidation) devuelve la razón del
  /// error en distintas formas según el caso -- `{ "title": "..." }` para
  /// `BusinessRuleException`, `{ "detail": "..." }` para problem details
  /// estándar. Se intentan las más comunes antes de caer al mensaje
  /// genérico con el status code.
  String? _extraerMensajeDeError(dynamic decodificado) {
    if (decodificado is! Map<String, dynamic>) return null;
    final valor = decodificado['title'] ?? decodificado['detail'] ?? decodificado['message'];
    return valor is String ? valor : null;
  }

  void close() => _client.close();
}
