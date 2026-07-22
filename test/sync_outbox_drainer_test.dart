// Sub-fase 3g del motor de sincronización: SyncOutboxDrainer. Red falsa,
// DB real en memoria con filas de Sync_Outbox insertadas a mano (no hace
// falta pasar por SyncOutboxWriter para probar el drainer en aislamiento).
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
import 'package:pvapp/core/sync/outbox/sync_outbox_drainer.dart';
import 'package:pvapp/core/sync/sync_client.dart';

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

Future<int> _encolar(Database db, {required String entidad, String? guid, String operacion = 'CREAR'}) {
  final g = guid ?? 'guid-${DateTime.now().microsecondsSinceEpoch}';
  return db.insert('Sync_Outbox', {
    'entidad': entidad,
    'guid_registro': g,
    'operacion': operacion,
    'datos_json': jsonEncode({'id': g, 'nombre': 'x'}),
    'fecha_creacion': DateTime.now().toUtc().toIso8601String(),
    'intentos': 0,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_outbox_drainer_test');
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

  test('lote exitoso: borra todas las filas del outbox', () async {
    await _encolar(db, entidad: 'Cliente', guid: 'g1');
    await _encolar(db, entidad: 'Cliente', guid: 'g2');

    final auth = authConSesion();
    await auth.inicializar();
    final fakeHttp = _FakeHttpClient(
      (_) async => _respuesta(200,
          cuerpo: jsonEncode({
            'resultados': [
              {'entidad': 'Cliente', 'id': 'g1', 'resultado': 'Insertado'},
              {'entidad': 'Cliente', 'id': 'g2', 'resultado': 'Actualizado'},
            ],
          })),
    );
    final drainer = SyncOutboxDrainer(syncClient: SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth));

    final resultado = await drainer.drenar(db);

    expect(resultado.subidos, 2);
    expect(resultado.omitidosPorServidor, 0);
    expect(resultado.fallidos, 0);
    expect(await db.query('Sync_Outbox'), isEmpty);
  });

  test('OmitidoServidorGana: borra la fila y marca la entidad para re-pull', () async {
    await _encolar(db, entidad: 'Cliente', guid: 'g1');

    final auth = authConSesion();
    await auth.inicializar();
    final fakeHttp = _FakeHttpClient(
      (_) async => _respuesta(200,
          cuerpo: jsonEncode({
            'resultados': [
              {'entidad': 'Cliente', 'id': 'g1', 'resultado': 'OmitidoServidorGana'},
            ],
          })),
    );
    final drainer = SyncOutboxDrainer(syncClient: SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth));

    final resultado = await drainer.drenar(db);

    expect(resultado.subidos, 0);
    expect(resultado.omitidosPorServidor, 1);
    expect(resultado.entidadesAPullearDeNuevo, {'Cliente'});
    expect(await db.query('Sync_Outbox'), isEmpty);
  });

  test('fallo de red de un lote: incrementa intentos, no borra, y sigue con el siguiente lote', () async {
    // 27 filas con tamanoLote=25 -> 2 lotes. El primero falla, el segundo
    // tiene éxito -- verifica que no hay loop infinito y que el segundo
    // lote sí se intenta (progreso hacia adelante pase lo que pase con el
    // primero).
    for (var i = 0; i < 27; i++) {
      await _encolar(db, entidad: 'Cliente', guid: 'g$i');
    }

    final auth = authConSesion();
    await auth.inicializar();
    var llamada = 0;
    final fakeHttp = _FakeHttpClient((request) async {
      llamada++;
      if (llamada == 1) return _respuesta(500, cuerpo: '{"title":"boom"}');

      final body = jsonDecode(request is http.Request ? request.body : '') as Map<String, dynamic>;
      final cambios = body['cambios'] as List;
      return _respuesta(200,
          cuerpo: jsonEncode({
            'resultados': cambios
                .map((c) => {'entidad': c['entidad'], 'id': (c['datos'] as Map)['id'], 'resultado': 'Insertado'})
                .toList(),
          }));
    });
    final drainer =
        SyncOutboxDrainer(syncClient: SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth));

    final resultado = await drainer.drenar(db);

    expect(llamada, 2); // no reintentó el lote 1 infinitamente dentro de esta misma llamada
    expect(resultado.fallidos, 25); // el primer lote completo (25 filas)
    expect(resultado.subidos, 2); // el segundo lote (2 filas restantes)

    final restantes = await db.query('Sync_Outbox');
    expect(restantes, hasLength(25)); // las del lote fallido siguen ahí
    expect(restantes.every((f) => f['intentos'] == 1), isTrue);
    expect(restantes.every((f) => f['ultimo_error'] != null), isTrue);
  });

  test('un segundo drenar() sí reintenta las filas que fallaron antes', () async {
    await _encolar(db, entidad: 'Cliente', guid: 'g1');

    final auth = authConSesion();
    await auth.inicializar();
    var llamada = 0;
    final fakeHttp = _FakeHttpClient((_) async {
      llamada++;
      if (llamada == 1) return _respuesta(500);
      return _respuesta(200,
          cuerpo: jsonEncode({
            'resultados': [
              {'entidad': 'Cliente', 'id': 'g1', 'resultado': 'Insertado'},
            ],
          }));
    });
    final drainer = SyncOutboxDrainer(syncClient: SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth));

    final primero = await drainer.drenar(db);
    expect(primero.fallidos, 1);
    expect(await db.query('Sync_Outbox'), hasLength(1));

    final segundo = await drainer.drenar(db);
    expect(segundo.subidos, 1);
    expect(await db.query('Sync_Outbox'), isEmpty);
  });

  test('filas con intentos = -1 (esperando prerrequisito) se ignoran, no se drenan', () async {
    final id = await _encolar(db, entidad: 'Venta', guid: 'g1');
    await db.update('Sync_Outbox', {'intentos': -1}, where: 'id = ?', whereArgs: [id]);

    final auth = authConSesion();
    await auth.inicializar();
    final fakeHttp = _FakeHttpClient((_) async => _respuesta(200, cuerpo: jsonEncode({'resultados': []})));
    final drainer = SyncOutboxDrainer(syncClient: SyncClient(http: ApiHttpClient(client: fakeHttp), authService: auth));

    final resultado = await drainer.drenar(db);

    expect(fakeHttp.llamadas, 0); // nunca se llegó a llamar push, no había nada elegible
    expect(resultado.subidos, 0);
    expect(await db.query('Sync_Outbox'), hasLength(1)); // sigue ahí, sin tocar
  });
}
