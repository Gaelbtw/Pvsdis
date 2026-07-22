// Pruebas de JwtUtils (puro, sin red ni Flutter): decodificación del
// payload de un JWT y extracción del claim tenant_id.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/sync/network/jwt_utils.dart';

/// Arma un JWT con el payload dado, sin firma real (JwtUtils no la valida).
String _tokenConPayload(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none'}))).replaceAll('=', '');
  final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.firma-invalida';
}

void main() {
  group('decodificarPayload', () {
    test('decodifica un JWT válido con claims', () {
      final token = _tokenConPayload({'tenant_id': 'abc-123', 'sub': 'usuario-1'});

      final claims = JwtUtils.decodificarPayload(token);

      expect(claims, isNotNull);
      expect(claims!['tenant_id'], 'abc-123');
      expect(claims['sub'], 'usuario-1');
    });

    test('token con menos de 3 segmentos devuelve null', () {
      expect(JwtUtils.decodificarPayload('solo.dossegmentos'), isNull);
      expect(JwtUtils.decodificarPayload('unsegmento'), isNull);
    });

    test('token con más de 3 segmentos devuelve null', () {
      expect(JwtUtils.decodificarPayload('a.b.c.d'), isNull);
    });

    test('payload no-JSON devuelve null en vez de lanzar', () {
      final payloadBasura = base64Url.encode(utf8.encode('no soy json')).replaceAll('=', '');
      expect(JwtUtils.decodificarPayload('header.$payloadBasura.firma'), isNull);
    });

    test('payload que decodifica a un valor que no es Map devuelve null', () {
      final payloadLista = base64Url.encode(utf8.encode(jsonEncode([1, 2, 3]))).replaceAll('=', '');
      expect(JwtUtils.decodificarPayload('header.$payloadLista.firma'), isNull);
    });

    test('base64 inválido no lanza, devuelve null', () {
      expect(JwtUtils.decodificarPayload('header.###no-es-base64###.firma'), isNull);
    });
  });

  group('tenantIdDe', () {
    test('devuelve el claim tenant_id cuando existe', () {
      final token = _tokenConPayload({'tenant_id': 'tenant-xyz'});
      expect(JwtUtils.tenantIdDe(token), 'tenant-xyz');
    });

    test('devuelve null si el claim no existe', () {
      final token = _tokenConPayload({'sub': 'usuario-1'});
      expect(JwtUtils.tenantIdDe(token), isNull);
    });

    test('devuelve null si el token no se pudo decodificar', () {
      expect(JwtUtils.tenantIdDe('token-invalido'), isNull);
    });
  });
}
