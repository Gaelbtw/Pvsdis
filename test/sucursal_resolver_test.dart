// Sub-fase 3d del motor de sincronización: SucursalesClient (GET
// /api/sucursales) y SucursalResolver. Red falsa vía http.BaseClient (mismo
// patrón que auth_service_test.dart), DB real en memoria para Sync_Config
// (mismo patrón que los tests de migración).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/core/sync/network/api_http_client.dart';
import 'package:pvapp/core/sync/network/token_storage.dart';
import 'package:pvapp/core/sync/sucursal/sucursal_resolver.dart';
import 'package:pvapp/core/sync/sucursal/sucursales_client.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _responder;
  int llamadas = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    llamadas++;
    return _responder(request);
  }
}

http.StreamedResponse _respuesta(int status, {String? cuerpo}) =>
    http.StreamedResponse(Stream.value(utf8.encode(cuerpo ?? '')), status);

class _FakeTokenStorage extends TokenStorage {
  SesionSync? guardada;

  @override
  Future<void> guardar(SesionSync sesion) async => guardada = sesion;

  @override
  Future<SesionSync?> leer() async => guardada;

  @override
  Future<void> borrar() async => guardada = null;
}

SesionSync _sesion({String? sucursalId}) => SesionSync(
      usuarioId: 'u1',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Cajero'],
      sucursalId: sucursalId,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: 'tenant-1',
    );

String _sucursalesJson(List<Map<String, dynamic>> sucursales) => jsonEncode(sucursales);

Map<String, dynamic> _sucursal({
  required String id,
  required String nombre,
  bool esPrincipal = false,
}) =>
    {
      'id': id,
      'nombre': nombre,
      'direccion': null,
      'telefono': null,
      'esPrincipal': esPrincipal,
      'activo': true,
      'fechaCreacion': '2026-01-01T00:00:00Z',
    };

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sucursal_resolver_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SucursalesClient', () {
    test('obtenerTodas parsea la lista de sucursales', () async {
      final fakeHttp = _FakeHttpClient(
        (_) async => _respuesta(200, cuerpo: _sucursalesJson([
              _sucursal(id: 'guid-1', nombre: 'Principal', esPrincipal: true),
              _sucursal(id: 'guid-2', nombre: 'Sucursal Norte'),
            ])),
      );

      final storageConSesion = _FakeTokenStorage()..guardada = _sesion();
      final authConSesion = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storageConSesion);
      await authConSesion.inicializar();

      final client = SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: authConSesion);
      final sucursales = await client.obtenerTodas();

      expect(sucursales, hasLength(2));
      expect(sucursales.first.id, 'guid-1');
      expect(sucursales.first.esPrincipal, isTrue);
      expect(sucursales.last.nombre, 'Sucursal Norte');
    });
  });

  group('SucursalResolver.sucursalIdConocido', () {
    test('devuelve el de la sesión si ya viene asignado en el login', () async {
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: 'guid-de-sesion');
      final auth = AuthService(http: ApiHttpClient(client: _FakeHttpClient((_) async => _respuesta(200))), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(authService: auth);
      expect(await resolver.sucursalIdConocido(db), 'guid-de-sesion');
    });

    test('cae a la caché de Sync_Config si la sesión no trae sucursal', () async {
      await db.insert('Sync_Config', {'id': 1, 'sucursal_id': 'guid-cacheado', 'sucursal_nombre': 'Cacheada'});

      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: _FakeHttpClient((_) async => _respuesta(200))), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(authService: auth);
      expect(await resolver.sucursalIdConocido(db), 'guid-cacheado');
    });

    test('devuelve null si no hay sesión con sucursal ni caché', () async {
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: _FakeHttpClient((_) async => _respuesta(200))), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(authService: auth);
      expect(await resolver.sucursalIdConocido(db), isNull);
    });
  });

  group('SucursalResolver.resolverYCachear', () {
    test('si ya hay sucursal conocida, no llama a la red', () async {
      final fakeHttp = _FakeHttpClient((_) async => _respuesta(500));
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: 'guid-ya-conocida');
      final auth = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(
        authService: auth,
        client: SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: auth),
      );

      final resultado = await resolver.resolverYCachear(db);
      expect(resultado, 'guid-ya-conocida');
      expect(fakeHttp.llamadas, 0);
    });

    test('resuelve la sucursal esPrincipal y la cachea en Sync_Config', () async {
      final fakeHttp = _FakeHttpClient(
        (_) async => _respuesta(200, cuerpo: _sucursalesJson([
              _sucursal(id: 'guid-secundaria', nombre: 'Secundaria'),
              _sucursal(id: 'guid-principal', nombre: 'Principal', esPrincipal: true),
            ])),
      );
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(
        authService: auth,
        client: SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: auth),
      );

      final resultado = await resolver.resolverYCachear(db);
      expect(resultado, 'guid-principal');

      final cache = await db.query('Sync_Config', where: 'id = 1');
      expect(cache.first['sucursal_id'], 'guid-principal');
      expect(cache.first['sucursal_nombre'], 'Principal');

      // Segunda llamada: ya está cacheada, no debe volver a pegarle a la red.
      final llamadasAntes = fakeHttp.llamadas;
      final resultado2 = await resolver.resolverYCachear(db);
      expect(resultado2, 'guid-principal');
      expect(fakeHttp.llamadas, llamadasAntes);
    });

    test('usa la primera sucursal si ninguna está marcada esPrincipal', () async {
      final fakeHttp = _FakeHttpClient(
        (_) async => _respuesta(200, cuerpo: _sucursalesJson([
              _sucursal(id: 'guid-a', nombre: 'A'),
              _sucursal(id: 'guid-b', nombre: 'B'),
            ])),
      );
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(
        authService: auth,
        client: SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: auth),
      );

      expect(await resolver.resolverYCachear(db), 'guid-a');
    });

    test('devuelve null (sin cachear nada) si la llamada de red falla', () async {
      final fakeHttp = _FakeHttpClient((_) async => _respuesta(500, cuerpo: '{"title":"boom"}'));
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(
        authService: auth,
        client: SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: auth),
      );

      expect(await resolver.resolverYCachear(db), isNull);
      final cache = await db.query('Sync_Config', where: 'id = 1');
      expect(cache, isEmpty);
    });

    test('devuelve null si el tenant no tiene ninguna sucursal', () async {
      final fakeHttp = _FakeHttpClient((_) async => _respuesta(200, cuerpo: _sucursalesJson(const [])));
      final storage = _FakeTokenStorage()..guardada = _sesion(sucursalId: null);
      final auth = AuthService(http: ApiHttpClient(client: fakeHttp), storage: storage);
      await auth.inicializar();

      final resolver = SucursalResolver(
        authService: auth,
        client: SucursalesClient(http: ApiHttpClient(client: fakeHttp), authService: auth),
      );

      expect(await resolver.resolverYCachear(db), isNull);
    });
  });
}
