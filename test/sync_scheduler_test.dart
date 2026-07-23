// Paso 2 del cierre del motor: SyncScheduler. Verifica el guard de
// concurrencia (un tick del timer no se solapa con un disparo manual) y que
// el estado observable publica el conteo de pendientes del outbox, excluyendo
// las filas en dead-letter. DB real en memoria, motor real con probe
// inyectado (mismo patrón que test/sync_engine_test.dart).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/network/api_http_client.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/core/sync/network/conectividad_probe.dart';
import 'package:pvapp/core/sync/network/token_storage.dart';
import 'package:pvapp/core/sync/outbox/sync_outbox_deadletter.dart';
import 'package:pvapp/core/sync/sync_engine.dart';
import 'package:pvapp/core/sync/sync_scheduler.dart';

/// Probe cuya respuesta se libera manualmente vía [compuerta], para poder
/// dejar un ciclo "en vuelo" mientras se dispara el segundo.
class _ProbeControlado extends ConectividadProbe {
  _ProbeControlado(this.compuerta);
  final Completer<void> compuerta;
  int llamadas = 0;

  @override
  Future<bool> hayConexion() async {
    llamadas++;
    await compuerta.future;
    return false; // -> ResultadoSync.sinConexion, sin tocar red
  }
}

class _NuncaConexion extends ConectividadProbe {
  @override
  Future<bool> hayConexion() async => false;
}

class _FakeTokenStorage extends TokenStorage {
  @override
  Future<SesionSync?> leer() async => null;
}

AuthService _authSinSesion() => AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage());

Future<void> _encolar(Database db, String guid, int intentos) => db.insert('Sync_Outbox', {
      'entidad': 'Cliente',
      'guid_registro': guid,
      'operacion': 'CREAR',
      'datos_json': '{}',
      'fecha_creacion': '2026-01-01T00:00:00Z',
      'intentos': intentos,
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_scheduler_test');
    db = await DatabaseHelper().abrirEnRuta(join(tempDir.path, 'test.db'));
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('un segundo disparo mientras hay un ciclo en curso es un no-op (guard de concurrencia)', () async {
    final compuerta = Completer<void>();
    final probe = _ProbeControlado(compuerta);
    final scheduler = SyncScheduler(engine: SyncEngine(authService: _authSinSesion(), conectividadProbe: probe));

    final primera = scheduler.sincronizarAhora(); // arranca y se cuelga en la compuerta
    await Future<void>.delayed(Duration.zero); // deja que el primer ciclo entre al await
    expect(scheduler.estado.value.fase, FaseSync.sincronizando);

    final segunda = await scheduler.sincronizarAhora(); // el guard debe cortarla
    expect(segunda, isNull, reason: 'el segundo disparo se ignora');
    expect(probe.llamadas, 1, reason: 'el motor no corrió una segunda vez');

    compuerta.complete();
    final resultado = await primera;
    expect(resultado, isNotNull);
    expect(resultado!.completo, isFalse); // sinConexion
    expect(scheduler.estado.value.fase, FaseSync.inactivo);
  });

  test('tras un ciclo, el estado publica los pendientes del outbox y excluye el dead-letter', () async {
    await _encolar(db, 'g1', 0); // pendiente normal
    await _encolar(db, 'g2', 3); // pendiente con reintentos
    await _encolar(db, 'g3', -1); // esperando prerrequisito: sigue contando como pendiente
    await _encolar(db, 'g4', SyncOutboxDeadLetter.intentosFallidaPermanente); // dead-letter: NO cuenta

    final scheduler = SyncScheduler(engine: SyncEngine(authService: _authSinSesion(), conectividadProbe: _NuncaConexion()));
    await scheduler.sincronizarAhora();

    expect(scheduler.estado.value.pendientes, 3);
    expect(scheduler.estado.value.fase, FaseSync.inactivo);
  });
}
