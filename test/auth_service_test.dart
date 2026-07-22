// Pruebas de AuthService (sin red real: usa un http.Client falso vía
// http.BaseClient, y un TokenStorage falso en memoria vía subclase). Cubre
// login/logout, el refresco proactivo del access token, y la traducción de
// SesionExpiradaException -> ErrorRespuestaApi en login() (bug encontrado y
// corregido en revisión: un login con credenciales inválidas devuelve 401,
// que ApiHttpClient traduce a SesionExpiradaException -- correcto para un
// request autenticado que dejó de serlo, pero confuso para un intento de
// login recién hecho).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/core/sync/network/api_exceptions.dart';
import 'package:pvapp/core/sync/network/api_http_client.dart';
import 'package:pvapp/core/sync/network/token_storage.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => _responder(request);
}

http.StreamedResponse _respuesta(int status, {String? cuerpo}) =>
    http.StreamedResponse(Stream.value(utf8.encode(cuerpo ?? '')), status);

/// TokenStorage sin tocar disco: guarda en memoria para el test.
class _FakeTokenStorage extends TokenStorage {
  SesionSync? guardada;

  @override
  Future<void> guardar(SesionSync sesion) async => guardada = sesion;

  @override
  Future<SesionSync?> leer() async => guardada;

  @override
  Future<void> borrar() async => guardada = null;
}

String _loginResponseJson({
  String accessToken = 'access-1',
  String refreshToken = 'refresh-1',
  DateTime? expiraEn,
}) {
  return jsonEncode({
    'usuarioId': 'u1',
    'email': 'a@b.com',
    'nombreCompleto': 'Persona Uno',
    'roles': ['Cajero'],
    'sucursalId': null,
    'accessToken': accessToken,
    'accessTokenExpiraEn': (expiraEn ?? DateTime.now().toUtc().add(const Duration(minutes: 30))).toIso8601String(),
    'refreshToken': refreshToken,
  });
}

void main() {
  group('login', () {
    test('éxito: guarda la sesión y la deja disponible en sesionActual', () async {
      final http_ = ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(200, cuerpo: _loginResponseJson())));
      final storage = _FakeTokenStorage();
      final auth = AuthService(http: http_, storage: storage);

      final sesion = await auth.login('a@b.com', 'clave123');

      expect(sesion.accessToken, 'access-1');
      expect(auth.estaAutenticado, isTrue);
      expect(auth.sesionActual?.accessToken, 'access-1');
      expect(storage.guardada?.accessToken, 'access-1');
    });

    test('credenciales inválidas (401) se traduce a ErrorRespuestaApi con el mensaje del backend', () async {
      final http_ = ApiHttpClient(
        client: _FakeHttpClient((_) => _respuesta(401, cuerpo: jsonEncode({'title': 'Credenciales inválidas.'}))),
      );
      final auth = AuthService(http: http_, storage: _FakeTokenStorage());

      await expectLater(
        auth.login('a@b.com', 'clave-mala'),
        throwsA(
          isA<ErrorRespuestaApi>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.mensaje, 'mensaje', 'Credenciales inválidas.'),
        ),
      );
      // No debe quedar autenticado tras un intento fallido.
      expect(auth.estaAutenticado, isFalse);
    });
  });

  group('logout', () {
    test('borra la sesión local aunque el backend no responda (best-effort)', () async {
      final http_ = ApiHttpClient(client: _FakeHttpClient((_) => throw const SocketException('sin red')));
      final storage = _FakeTokenStorage()
        ..guardada = SesionSync(
          usuarioId: 'u1',
          email: 'a@b.com',
          nombreCompleto: 'Persona Uno',
          roles: const [],
          accessToken: 'a',
          accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
          refreshToken: 'r',
        );
      final auth = AuthService(http: http_, storage: storage);
      await auth.inicializar();

      await auth.logout();

      expect(auth.estaAutenticado, isFalse);
      expect(storage.guardada, isNull);
    });
  });

  group('obtenerAccessTokenValido', () {
    test('sin sesión lanza SesionExpiradaException', () async {
      final auth = AuthService(http: ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(200))));
      await expectLater(auth.obtenerAccessTokenValido(), throwsA(isA<SesionExpiradaException>()));
    });

    test('token vigente (no por expirar) se devuelve sin llamar al backend', () async {
      var llamadas = 0;
      final http_ = ApiHttpClient(
        client: _FakeHttpClient((_) {
          llamadas++;
          return _respuesta(200, cuerpo: _loginResponseJson());
        }),
      );
      final auth = AuthService(http: http_, storage: _FakeTokenStorage());
      await auth.login('a@b.com', 'clave123'); // 1 llamada (login)

      final token = await auth.obtenerAccessTokenValido();

      expect(token, 'access-1');
      expect(llamadas, 1); // no se agregó una llamada de refresh
    });

    test('token por expirar se refresca y devuelve el nuevo', () async {
      final http_ = ApiHttpClient(
        client: _FakeHttpClient((request) {
          if (request.url.path.contains('refresh-token')) {
            return _respuesta(200, cuerpo: _loginResponseJson(accessToken: 'access-2', refreshToken: 'refresh-2'));
          }
          return _respuesta(
            200,
            cuerpo: _loginResponseJson(expiraEn: DateTime.now().toUtc().add(const Duration(seconds: 10))),
          );
        }),
      );
      final storage = _FakeTokenStorage();
      final auth = AuthService(http: http_, storage: storage);
      await auth.login('a@b.com', 'clave123'); // expira en 10s: dentro del margen de 60s

      final token = await auth.obtenerAccessTokenValido();

      expect(token, 'access-2');
      expect(auth.sesionActual?.refreshToken, 'refresh-2');
      expect(storage.guardada?.accessToken, 'access-2');
    });

    test('sin red durante el refresco devuelve el token viejo en vez de lanzar', () async {
      final http_ = ApiHttpClient(
        client: _FakeHttpClient((request) {
          if (request.url.path.contains('refresh-token')) {
            throw const SocketException('sin red');
          }
          return _respuesta(
            200,
            cuerpo: _loginResponseJson(expiraEn: DateTime.now().toUtc().add(const Duration(seconds: 10))),
          );
        }),
      );
      final auth = AuthService(http: http_, storage: _FakeTokenStorage());
      await auth.login('a@b.com', 'clave123');

      final token = await auth.obtenerAccessTokenValido();

      expect(token, 'access-1'); // el token original del login, sin cambios
    });

    test('refresh token rechazado por el backend limpia la sesión y lanza SesionExpiradaException', () async {
      final http_ = ApiHttpClient(
        client: _FakeHttpClient((request) {
          if (request.url.path.contains('refresh-token')) {
            return _respuesta(401, cuerpo: jsonEncode({'title': 'El token de actualización no es válido.'}));
          }
          return _respuesta(
            200,
            cuerpo: _loginResponseJson(expiraEn: DateTime.now().toUtc().add(const Duration(seconds: 10))),
          );
        }),
      );
      final storage = _FakeTokenStorage();
      final auth = AuthService(http: http_, storage: storage);
      await auth.login('a@b.com', 'clave123');

      await expectLater(
        auth.obtenerAccessTokenValido(),
        throwsA(
          isA<SesionExpiradaException>()
              .having((e) => e.mensaje, 'mensaje', 'El token de actualización no es válido.'),
        ),
      );
      expect(auth.estaAutenticado, isFalse);
      expect(storage.guardada, isNull);
    });
  });
}
