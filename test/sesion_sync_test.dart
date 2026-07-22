// Pruebas de SesionSync (puro, sin red ni Flutter): vencimiento del access
// token, el margen de refresco preventivo, y el roundtrip a/desde mapa que
// usa TokenStorage para persistir la sesión.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/sync/models/sync_auth_models.dart';

void main() {
  SesionSync sesionConVencimiento(DateTime accessTokenExpiraEn) {
    return SesionSync(
      usuarioId: 'u1',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Cajero'],
      accessToken: 'token-acceso',
      accessTokenExpiraEn: accessTokenExpiraEn,
      refreshToken: 'token-refresco',
    );
  }

  group('accessTokenExpirado', () {
    test('false si el vencimiento está en el futuro', () {
      final sesion = sesionConVencimiento(DateTime.now().toUtc().add(const Duration(minutes: 10)));
      expect(sesion.accessTokenExpirado, isFalse);
    });

    test('true si el vencimiento ya pasó', () {
      final sesion = sesionConVencimiento(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
      expect(sesion.accessTokenExpirado, isTrue);
    });
  });

  group('accessTokenPorExpirar (margen preventivo de 60s)', () {
    test('false si falta bastante más de 60s para vencer', () {
      final sesion = sesionConVencimiento(DateTime.now().toUtc().add(const Duration(minutes: 5)));
      expect(sesion.accessTokenPorExpirar, isFalse);
    });

    test('true si vence dentro del margen de 60s', () {
      final sesion = sesionConVencimiento(DateTime.now().toUtc().add(const Duration(seconds: 30)));
      expect(sesion.accessTokenPorExpirar, isTrue);
    });

    test('true si ya expiró (también cae dentro del margen)', () {
      final sesion = sesionConVencimiento(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
      expect(sesion.accessTokenPorExpirar, isTrue);
    });
  });

  group('toMap / fromMap', () {
    test('el roundtrip conserva todos los campos', () {
      final original = SesionSync(
        usuarioId: 'u1',
        email: 'a@b.com',
        nombreCompleto: 'Persona Uno',
        roles: const ['Cajero', 'Supervisor'],
        sucursalId: 's1',
        accessToken: 'token-acceso',
        accessTokenExpiraEn: DateTime.utc(2026, 1, 1, 12),
        refreshToken: 'token-refresco',
        tenantId: 'tenant-1',
      );

      final restaurada = SesionSync.fromMap(original.toMap());

      expect(restaurada.usuarioId, original.usuarioId);
      expect(restaurada.email, original.email);
      expect(restaurada.nombreCompleto, original.nombreCompleto);
      expect(restaurada.roles, original.roles);
      expect(restaurada.sucursalId, original.sucursalId);
      expect(restaurada.accessToken, original.accessToken);
      expect(restaurada.accessTokenExpiraEn, original.accessTokenExpiraEn);
      expect(restaurada.refreshToken, original.refreshToken);
      expect(restaurada.tenantId, original.tenantId);
    });

    test('sucursalId y tenantId nulos sobreviven el roundtrip', () {
      final original = sesionConVencimiento(DateTime.utc(2026, 1, 1));
      final restaurada = SesionSync.fromMap(original.toMap());

      expect(restaurada.sucursalId, isNull);
      expect(restaurada.tenantId, isNull);
    });
  });

  group('desdeLogin', () {
    test('decodifica el tenant_id del access token automáticamente', () {
      // Header y payload de un JWT real con claim tenant_id="t-99" (armado a
      // mano para no depender de dart:convert en el test de datos fijos).
      const tokenConTenant =
          'eyJhbGciOiJub25lIn0.eyJ0ZW5hbnRfaWQiOiJ0LTk5In0.firma';

      final login = LoginResponse(
        usuarioId: 'u1',
        email: 'a@b.com',
        nombreCompleto: 'Persona Uno',
        roles: const ['Cajero'],
        accessToken: tokenConTenant,
        accessTokenExpiraEn: DateTime.utc(2026, 1, 1),
        refreshToken: 'r1',
      );

      final sesion = SesionSync.desdeLogin(login);

      expect(sesion.tenantId, 't-99');
      expect(sesion.usuarioId, 'u1');
    });
  });
}
