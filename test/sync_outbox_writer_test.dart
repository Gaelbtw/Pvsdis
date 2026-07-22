// Sub-fase 3f del motor de sincronización: SyncOutboxWriter. DB real en
// memoria (mismo patrón que los demás tests de mappers), AuthService con
// almacenamiento falso en memoria (sin red -- esta clase nunca llama al
// backend, solo arma y encola payloads localmente).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/core/sync/network/api_http_client.dart';
import 'package:pvapp/core/sync/network/token_storage.dart';
import 'package:pvapp/core/sync/outbox/sync_outbox_writer.dart';

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
      roles: const ['Cajero'],
      sucursalId: null,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: '11111111-1111-1111-1111-111111111111',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_outbox_writer_test');
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
  AuthService authSinSesion() => AuthService(http: ApiHttpClient(), storage: _FakeTokenStorage());

  group('crear', () {
    test('sin sesión de sync: inserta la fila pero no encola nada', () async {
      final auth = authSinSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      final id = await writer.crear(db, entidad: 'Cliente', tabla: 'Clientes', values: {'nombre': 'Cliente Uno'});

      final fila = await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [id]);
      expect(fila.first['guid_sync'], isNotNull); // insertarConGuidSync sí corrió

      final outbox = await db.query('Sync_Outbox');
      expect(outbox, isEmpty);
    });

    test('con sesión: inserta la fila Y encola un CREAR con el payload correcto', () async {
      final auth = authConSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      final id = await writer.crear(db, entidad: 'Cliente', tabla: 'Clientes', values: {'nombre': 'Cliente Uno'});
      final guid = (await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [id])).first['guid_sync'] as String;

      final outbox = await db.query('Sync_Outbox');
      expect(outbox, hasLength(1));
      expect(outbox.first['entidad'], 'Cliente');
      expect(outbox.first['guid_registro'], guid);
      expect(outbox.first['operacion'], 'CREAR');
      expect(outbox.first['intentos'], 0);

      final payload = jsonDecode(outbox.first['datos_json'] as String) as Map<String, dynamic>;
      expect(payload['id'], guid);
      expect(payload['tenantId'], '11111111-1111-1111-1111-111111111111');
      expect(payload['nombre'], 'Cliente Uno');
    });

    test('si el payload no se puede armar todavía (StateError), encola con intentos=-1 sin perder la fila', () async {
      final auth = authConSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      // Producto sin categoría: ProductoMapper.aBackend exige CategoriaId
      // resuelto -- ver producto_mapper.dart.
      final id = await writer.crear(db, entidad: 'Producto', tabla: 'Producto', values: {
        'nombre': 'Sin categoría',
        'precio': 10.0,
      });

      final fila = await db.query('Producto', where: 'id_producto = ?', whereArgs: [id]);
      expect(fila, hasLength(1)); // la fila local se guardó igual, no hubo rollback

      final outbox = await db.query('Sync_Outbox');
      expect(outbox, hasLength(1));
      expect(outbox.first['intentos'], -1);
      expect(outbox.first['datos_json'], '{}');
      expect(outbox.first['ultimo_error'], isNotNull);
    });
  });

  group('actualizar', () {
    test('lanza ArgumentError si la tabla no está en tablasSincronizables', () async {
      final auth = authConSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      expect(
        () => writer.actualizar(db, entidad: 'Cliente', tabla: 'Reporte', idLocal: 1),
        throwsArgumentError,
      );
    });

    test('encola un ACTUALIZAR reflejando el estado ya escrito por el llamador', () async {
      final auth = authConSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      final id = await writer.crear(db, entidad: 'Cliente', tabla: 'Clientes', values: {'nombre': 'Nombre viejo'});
      await db.update('Clientes', {'nombre': 'Nombre nuevo'}, where: 'id_cliente = ?', whereArgs: [id]);

      await writer.actualizar(db, entidad: 'Cliente', tabla: 'Clientes', idLocal: id);

      final outbox = await db.query('Sync_Outbox', where: 'operacion = ?', whereArgs: ['ACTUALIZAR']);
      expect(outbox, hasLength(1));
      final payload = jsonDecode(outbox.first['datos_json'] as String) as Map<String, dynamic>;
      expect(payload['nombre'], 'Nombre nuevo');
    });

    test('no falla si la fila ya no existe (borrada antes de llegar aquí)', () async {
      final auth = authConSesion();
      await auth.inicializar();
      final writer = SyncOutboxWriter(authService: auth);

      final id = await writer.crear(db, entidad: 'Cliente', tabla: 'Clientes', values: {'nombre': 'Efímero'});
      await db.delete('Clientes', where: 'id_cliente = ?', whereArgs: [id]);

      await writer.actualizar(db, entidad: 'Cliente', tabla: 'Clientes', idLocal: id);

      final outbox = await db.query('Sync_Outbox', where: 'operacion = ?', whereArgs: ['ACTUALIZAR']);
      expect(outbox, isEmpty);
    });
  });

  test('revierte junto con el rollback de la transacción si algo falla después', () async {
    final auth = authConSesion();
    await auth.inicializar();
    final writer = SyncOutboxWriter(authService: auth);

    await expectLater(
      db.transaction((txn) async {
        await writer.crear(txn, entidad: 'Cliente', tabla: 'Clientes', values: {'nombre': 'Cliente Uno'});
        throw Exception('algo falla después de encolar');
      }),
      throwsException,
    );

    final clientes = await db.query('Clientes');
    expect(clientes, isEmpty);
    final outbox = await db.query('Sync_Outbox');
    expect(outbox, isEmpty);
  });
}
