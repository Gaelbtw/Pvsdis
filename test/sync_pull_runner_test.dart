// Sub-fase 3g del motor de sincronización: SyncPullRunner. Red falsa vía
// http.BaseClient (mismo patrón que auth_service_test.dart), DB real en
// memoria para aplicar los upsertLocal reales de cada mapper.
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
import 'package:pvapp/core/sync/pull/sync_pull_cursor_store.dart';
import 'package:pvapp/core/sync/pull/sync_pull_runner.dart';
import 'package:pvapp/core/sync/sync_client.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _responder;
  final List<Uri> uris = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uris.add(request.url);
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

SesionSync _sesion() => SesionSync(
      usuarioId: 'u1',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Admin'],
      sucursalId: null,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: 'tenant-1',
    );

String _paginaJson({required List<Map<String, dynamic>> elementos, required bool hayMas, required String ultimaFecha}) =>
    jsonEncode({'elementos': elementos, 'hayMas': hayMas, 'ultimaFechaModificacion': ultimaFecha});

Map<String, dynamic> _categoria({required String id, required String nombre}) =>
    {'id': id, 'tenantId': 'tenant-1', 'nombre': nombre, 'isDeleted': false};

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_pull_runner_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  AuthService authConSesion() => AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage()..guardada = _sesion());

  test('pullEntidad aplica los elementos de una sola página y guarda el cursor', () async {
    final auth = authConSesion();
    await auth.inicializar();
    final fakeHttp = _FakeHttpClient(
      (_) async => _respuesta(200,
          cuerpo: _paginaJson(
            elementos: [_categoria(id: 'guid-1', nombre: 'Bebidas')],
            hayMas: false,
            ultimaFecha: '2026-01-01T10:00:00Z',
          )),
    );
    final syncClient = SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth);
    final runner = SyncPullRunner(syncClient: syncClient);

    final aplicados = await runner.pullEntidad(db, 'CategoriaProducto');

    expect(aplicados, 1);
    final categorias = await db.query('Categorias', where: 'guid_sync = ?', whereArgs: ['guid-1']);
    expect(categorias.first['nombre'], 'Bebidas');

    final cursor = await SyncPullCursorStore().obtenerUltimaFecha(db, 'CategoriaProducto');
    expect(cursor, DateTime.parse('2026-01-01T10:00:00Z'));

    // Primera llamada: sin cursor previo, no debe mandar `desde`.
    expect(fakeHttp.uris.first.queryParameters.containsKey('desde'), isFalse);
  });

  test('pagina mientras hayMas sea true, aplicando todas las páginas', () async {
    final auth = authConSesion();
    await auth.inicializar();
    var llamada = 0;
    final fakeHttp = _FakeHttpClient((_) async {
      llamada++;
      if (llamada == 1) {
        return _respuesta(200,
            cuerpo: _paginaJson(
              elementos: [_categoria(id: 'guid-1', nombre: 'Página 1')],
              hayMas: true,
              ultimaFecha: '2026-01-01T10:00:00Z',
            ));
      }
      return _respuesta(200,
          cuerpo: _paginaJson(
            elementos: [_categoria(id: 'guid-2', nombre: 'Página 2')],
            hayMas: false,
            ultimaFecha: '2026-01-01T11:00:00Z',
          ));
    });
    final syncClient = SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth);
    final runner = SyncPullRunner(syncClient: syncClient);

    final aplicados = await runner.pullEntidad(db, 'CategoriaProducto');

    expect(aplicados, 2);
    expect(llamada, 2);
    expect(await db.query('Categorias', where: 'guid_sync = ?', whereArgs: ['guid-1']), hasLength(1));
    expect(await db.query('Categorias', where: 'guid_sync = ?', whereArgs: ['guid-2']), hasLength(1));

    // La segunda llamada debe pedir `desde` la fecha que devolvió la primera.
    expect(fakeHttp.uris[1].queryParameters['desde'], contains('2026-01-01T10:00:00'));
  });

  test('una segunda llamada a pullEntidad reutiliza el cursor guardado', () async {
    final auth = authConSesion();
    await auth.inicializar();
    final fakeHttp = _FakeHttpClient(
      (_) async => _respuesta(200,
          cuerpo: _paginaJson(elementos: const [], hayMas: false, ultimaFecha: '2026-01-01T09:00:00Z')),
    );
    final syncClient = SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth);
    final runner = SyncPullRunner(syncClient: syncClient);

    await SyncPullCursorStore().guardarUltimaFecha(db, 'CategoriaProducto', DateTime.parse('2025-12-01T00:00:00Z'));

    await runner.pullEntidad(db, 'CategoriaProducto');

    expect(fakeHttp.uris.first.queryParameters['desde'], contains('2025-12-01T00:00:00'));
  });

  test('pullEntidades procesa varias entidades en el orden dado', () async {
    final auth = authConSesion();
    await auth.inicializar();
    final entidadesVistas = <String>[];
    final fakeHttp = _FakeHttpClient((request) async {
      entidadesVistas.add(request.url.pathSegments.last);
      return _respuesta(200, cuerpo: _paginaJson(elementos: const [], hayMas: false, ultimaFecha: '2026-01-01T00:00:00Z'));
    });
    final syncClient = SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth);
    final runner = SyncPullRunner(syncClient: syncClient);

    await runner.pullEntidades(db, entidades: ['CategoriaProducto', 'Cliente', 'Proveedor']);

    expect(entidadesVistas, ['CategoriaProducto', 'Cliente', 'Proveedor']);
  });
}
