// Pruebas de ApiHttpClient (sin red real: usa un http.Client falso vía
// http.BaseClient). Cubre la traducción de códigos HTTP a las excepciones
// de api_exceptions.dart -- en particular, que el mensaje real del backend
// se propague en un 401 (bug encontrado y corregido en revisión: antes se
// descartaba el cuerpo de la respuesta para todo 401, así que un login con
// credenciales inválidas hubiera mostrado "la sesión expiró" en vez del
// mensaje real del backend).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:pvapp/core/sync/network/api_exceptions.dart';
import 'package:pvapp/core/sync/network/api_http_client.dart';

/// http.Client falso: responde según una función provista, sin tocar la red.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => _responder(request);
}

http.StreamedResponse _respuesta(int status, {String? cuerpo}) {
  final bytes = utf8.encode(cuerpo ?? '');
  return http.StreamedResponse(Stream.value(bytes), status);
}

void main() {
  group('respuestas exitosas', () {
    test('200 con cuerpo JSON devuelve el mapa decodificado', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient((_) => _respuesta(200, cuerpo: jsonEncode({'ok': true}))),
      );

      final resultado = await client.get('/api/lo-que-sea');

      expect(resultado, {'ok': true});
    });

    test('204 sin cuerpo devuelve null en vez de lanzar', () async {
      final client = ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(204)));

      final resultado = await client.post('/api/logout', body: {});

      expect(resultado, isNull);
    });
  });

  group('401 -- SesionExpiradaException', () {
    test('propaga el mensaje real del backend cuando viene en "title"', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient((_) => _respuesta(401, cuerpo: jsonEncode({'title': 'Credenciales inválidas.'}))),
      );

      await expectLater(
        client.post('/api/auth/login', body: {}),
        throwsA(isA<SesionExpiradaException>().having((e) => e.mensaje, 'mensaje', 'Credenciales inválidas.')),
      );
    });

    test('propaga el mensaje cuando viene en "detail"', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient(
          (_) => _respuesta(401, cuerpo: jsonEncode({'detail': 'La cuenta está bloqueada.'})),
        ),
      );

      await expectLater(
        client.post('/api/auth/login', body: {}),
        throwsA(isA<SesionExpiradaException>().having((e) => e.mensaje, 'mensaje', 'La cuenta está bloqueada.')),
      );
    });

    test('sin cuerpo usa el mensaje genérico por defecto', () async {
      final client = ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(401)));

      await expectLater(
        client.get('/api/sync/entidades'),
        throwsA(
          isA<SesionExpiradaException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('sesión'),
          ),
        ),
      );
    });

    test('cuerpo no-JSON usa el mensaje genérico por defecto', () async {
      final client = ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(401, cuerpo: '<html>401</html>')));

      await expectLater(client.get('/api/sync/entidades'), throwsA(isA<SesionExpiradaException>()));
    });
  });

  group('otros códigos de error -- ErrorRespuestaApi', () {
    test('400 con "detail" conserva el status code y el mensaje', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient((_) => _respuesta(400, cuerpo: jsonEncode({'detail': 'Email inválido.'}))),
      );

      await expectLater(
        client.post('/api/auth/login', body: {}),
        throwsA(
          isA<ErrorRespuestaApi>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.mensaje, 'mensaje', 'Email inválido.'),
        ),
      );
    });

    test('500 sin cuerpo interpretable usa un mensaje genérico con el status code', () async {
      final client = ApiHttpClient(client: _FakeHttpClient((_) => _respuesta(500)));

      await expectLater(
        client.get('/api/sync/entidades'),
        throwsA(isA<ErrorRespuestaApi>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('errores de transporte -- ErrorRed', () {
    test('SocketException se traduce a ErrorRed', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient((_) => throw const SocketException('sin red')),
      );

      await expectLater(client.get('/api/sync/entidades'), throwsA(isA<ErrorRed>()));
    });

    test('http.ClientException se traduce a ErrorRed', () async {
      final client = ApiHttpClient(
        client: _FakeHttpClient((_) => throw http.ClientException('conexión rechazada')),
      );

      await expectLater(client.get('/api/sync/entidades'), throwsA(isA<ErrorRed>()));
    });
  });
}
