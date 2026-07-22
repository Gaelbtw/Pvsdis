// Sub-fase 3g del motor de sincronización: SyncEngine de punta a punta.
// Red falsa, DB real en memoria, dependencias inyectadas (mismo patrón que
// el resto de la Fase 3).
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
import 'package:pvapp/core/sync/network/conectividad_probe.dart';
import 'package:pvapp/core/sync/network/token_storage.dart';
import 'package:pvapp/core/sync/outbox/sync_outbox_drainer.dart';
import 'package:pvapp/core/sync/pull/sync_pull_runner.dart';
import 'package:pvapp/core/sync/sucursal/sucursal_resolver.dart';
import 'package:pvapp/core/sync/sucursal/sucursales_client.dart';
import 'package:pvapp/core/sync/sync_client.dart';
import 'package:pvapp/core/sync/sync_engine.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._responder);
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => _responder(request);
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
      usuarioId: '22222222-2222-2222-2222-222222222222',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Admin'],
      sucursalId: null,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: '11111111-1111-1111-1111-111111111111',
    );

class _SiempreConexion extends ConectividadProbe {
  @override
  Future<bool> hayConexion() async => true;
}

class _NuncaConexion extends ConectividadProbe {
  @override
  Future<bool> hayConexion() async => false;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_engine_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sin conexión, no toca nada y devuelve sinConexion', () async {
    final auth = AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage()..guardada = _sesion());
    await auth.inicializar();

    final engine = SyncEngine(authService: auth, conectividadProbe: _NuncaConexion());
    final resultado = await engine.sincronizarUnaVez();

    expect(resultado.completo, isFalse);
    expect(resultado, same(ResultadoSync.sinConexion));
  });

  test('sin sesión de sync, no toca nada y devuelve sinSesion', () async {
    final auth = AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage());
    await auth.inicializar();

    final engine = SyncEngine(authService: auth, conectividadProbe: _SiempreConexion());
    final resultado = await engine.sincronizarUnaVez();

    expect(resultado.completo, isFalse);
    expect(resultado, same(ResultadoSync.sinSesion));
  });

  test('ciclo completo: resuelve sucursal, pullea catálogos, drena el outbox y reescribe pendientes', () async {
    final auth = AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage()..guardada = _sesion());
    await auth.inicializar();

    // Una fila "esperando prerrequisito" (VentaMapper exige sucursal
    // resuelta) encolada antes de que el dispositivo supiera su sucursal --
    // simula el caso borde documentado en sucursal_resolver.dart.
    final idUsuario = await db.insert('Usuarios', {'nombre': 'Cajero', 'contra': 'hash', 'rol': 'Cajero'});
    final idCaja = await DatabaseHelper.insertarConGuidSync(db, 'Cajas', {
      'id_usuario': idUsuario,
      'fecha_apertura': '2026-01-01T08:00:00Z',
      'fondo_inicial': 500.0,
    });
    final idVenta = await DatabaseHelper.insertarConGuidSync(db, 'Ventas', {
      'id_caja': idCaja,
      'fecha': '2026-01-01T10:00:00Z',
      'total': 50.0,
      'metodo_pago': 'efectivo',
    });
    final guidVenta = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta])).first['guid_sync'] as String;
    await db.insert('Sync_Outbox', {
      'entidad': 'Venta',
      'guid_registro': guidVenta,
      'operacion': 'CREAR',
      'datos_json': '{}',
      'fecha_creacion': '2026-01-01T10:00:00Z',
      'intentos': -1,
      'ultimo_error': 'sucursal sin resolver',
    });

    // Una fila normal (ClienteGana no aplica, esta es ServidorGana) lista
    // para subir en el drenado.
    final idCliente = await DatabaseHelper.insertarConGuidSync(db, 'Clientes', {'nombre': 'Cliente Uno'});
    final guidCliente = (await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [idCliente])).first['guid_sync'] as String;
    await db.insert('Sync_Outbox', {
      'entidad': 'Cliente',
      'guid_registro': guidCliente,
      'operacion': 'CREAR',
      'datos_json': jsonEncode({'id': guidCliente, 'nombre': 'Cliente Uno'}),
      'fecha_creacion': '2026-01-01T10:00:00Z',
      'intentos': 0,
    });

    final fakeHttp = _FakeHttpClient((request) async {
      final path = request.url.path;

      if (path == '/api/sucursales') {
        return _respuesta(200,
            cuerpo: jsonEncode([
              {
                'id': 'sucursal-1',
                'nombre': 'Principal',
                'direccion': null,
                'telefono': null,
                'esPrincipal': true,
                'activo': true,
                'fechaCreacion': '2026-01-01T00:00:00Z',
              },
            ]));
      }

      if (path.startsWith('/api/sync/') && request.method == 'GET') {
        // Pull: catálogo vacío para todas las entidades (no es el foco de
        // esta prueba, ver sync_pull_runner_test.dart para el pull en sí).
        return _respuesta(200,
            cuerpo: jsonEncode({'elementos': [], 'hayMas': false, 'ultimaFechaModificacion': '2026-01-01T00:00:00Z'}));
      }

      if (path == '/api/sync/push') {
        final body = jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        final cambios = body['cambios'] as List;
        return _respuesta(200,
            cuerpo: jsonEncode({
              'resultados': cambios
                  .map((c) => {'entidad': c['entidad'], 'id': (c['datos'] as Map)['id'], 'resultado': 'Insertado'})
                  .toList(),
            }));
      }

      return _respuesta(404);
    });

    final apiHttp = ApiHttpClient(client: fakeHttp);
    final syncClient = SyncClient(http: apiHttp, authService: auth);
    final engine = SyncEngine(
      authService: auth,
      syncClient: syncClient,
      conectividadProbe: _SiempreConexion(),
      sucursalResolver: SucursalResolver(authService: auth, client: SucursalesClient(http: apiHttp, authService: auth)),
      pullRunner: SyncPullRunner(syncClient: syncClient),
      drainer: SyncOutboxDrainer(syncClient: syncClient),
    );

    final resultado = await engine.sincronizarUnaVez();

    expect(resultado.completo, isTrue);
    expect(resultado.itemsSubidos, greaterThanOrEqualTo(2)); // Cliente + la Venta reescrita

    // La sucursal quedó resuelta y cacheada.
    final config = await db.query('Sync_Config', where: 'id = 1');
    expect(config.first['sucursal_id'], 'sucursal-1');

    // El outbox quedó completamente drenado (nada pendiente ni sentinelas).
    expect(await db.query('Sync_Outbox'), isEmpty);
  });
}
