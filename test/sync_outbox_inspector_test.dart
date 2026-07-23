// Paso 5 del cierre del motor: SyncOutboxInspector. Verifica la separación
// pendientes/dead-letter y las dos acciones manuales (reintentar/descartar).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/outbox/sync_outbox_deadletter.dart';
import 'package:pvapp/core/sync/outbox/sync_outbox_inspector.dart';

Future<int> _encolar(Database db, {required String entidad, required String guid, required int intentos}) {
  return db.insert('Sync_Outbox', {
    'entidad': entidad,
    'guid_registro': guid,
    'operacion': 'CREAR',
    'datos_json': '{}',
    'fecha_creacion': '2026-01-01T10:00:00Z',
    'intentos': intentos,
    'ultimo_error': intentos < 0 ? 'motivo' : null,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  final inspector = SyncOutboxInspector();

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_outbox_inspector_test');
    db = await DatabaseHelper().abrirEnRuta(join(tempDir.path, 'test.db'));
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('pendientes incluye normales y esperando-prerrequisito; fallidas solo el dead-letter', () async {
    await _encolar(db, entidad: 'Cliente', guid: 'g1', intentos: 0);
    await _encolar(db, entidad: 'Venta', guid: 'g2', intentos: -1);
    await _encolar(db, entidad: 'Producto', guid: 'g3', intentos: SyncOutboxDeadLetter.intentosFallidaPermanente);

    final pendientes = await inspector.pendientes(db);
    final fallidas = await inspector.fallidas(db);

    expect(pendientes.map((i) => i.entidad), ['Cliente', 'Venta']);
    expect(pendientes.firstWhere((i) => i.entidad == 'Venta').esperandoPrerrequisito, isTrue);
    expect(fallidas.map((i) => i.entidad), ['Producto']);
    expect(fallidas.single.esDeadLetter, isTrue);
  });

  test('reintentar devuelve una fila dead-letter a la cola normal', () async {
    final id = await _encolar(db, entidad: 'Producto', guid: 'g1', intentos: SyncOutboxDeadLetter.intentosFallidaPermanente);

    await inspector.reintentar(db, id);

    expect(await inspector.fallidas(db), isEmpty);
    final pendientes = await inspector.pendientes(db);
    expect(pendientes.single.intentos, 0);
    expect(pendientes.single.ultimoError, isNull);
  });

  test('descartar elimina la fila del outbox', () async {
    final id = await _encolar(db, entidad: 'Producto', guid: 'g1', intentos: SyncOutboxDeadLetter.intentosFallidaPermanente);

    await inspector.descartar(db, id);

    expect(await db.query('Sync_Outbox'), isEmpty);
  });

  test('cargar() lee ambos grupos contra la base local', () async {
    await _encolar(db, entidad: 'Cliente', guid: 'g1', intentos: 0);
    await _encolar(db, entidad: 'Producto', guid: 'g2', intentos: SyncOutboxDeadLetter.intentosFallidaPermanente);

    final datos = await inspector.cargar();

    expect(datos.pendientes.single.entidad, 'Cliente');
    expect(datos.fallidas.single.entidad, 'Producto');
  });
}
