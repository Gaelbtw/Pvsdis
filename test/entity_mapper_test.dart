// Sub-fase 3b del motor de sincronización: contrato EntityMapper/FkResolver
// y el mapper declarativo SimpleCatalogMapper (Categoria/Cliente/Proveedor),
// ver lib/core/sync/entities/. Prueba con una base sqflite real en memoria
// (mismo patrón que guid_sync_en_creacion_test.dart), no con fakes: lo que
// se está probando ES la traducción contra el esquema SQL real.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/entities/categoria_mapper.dart';
import 'package:pvapp/core/sync/entities/cliente_mapper.dart';
import 'package:pvapp/core/sync/entities/entity_mapper.dart';
import 'package:pvapp/core/sync/entities/entity_mapper_registry.dart';
import 'package:pvapp/core/sync/entities/proveedor_mapper.dart';

const _tenantId = '11111111-1111-1111-1111-111111111111';
const _usuarioIdSync = '22222222-2222-2222-2222-222222222222';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_entity_mapper_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FkResolver', () {
    test('idLocalPorGuid encuentra el id local de una fila existente', () async {
      final idCategoria = await DatabaseHelper.insertarConGuidSync(db, 'Categorias', {'nombre': 'Bebidas'});
      final guid = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria]))
          .first['guid_sync'] as String;

      final resolver = FkResolver(db);
      final idResuelto = await resolver.idLocalPorGuid('Categorias', 'id_categoria', guid);

      expect(idResuelto, idCategoria);
    });

    test('idLocalPorGuid devuelve null si el guid no existe localmente', () async {
      final resolver = FkResolver(db);
      final idResuelto = await resolver.idLocalPorGuid('Categorias', 'id_categoria', 'guid-inexistente');
      expect(idResuelto, isNull);
    });

    test('guidPorIdLocal devuelve el guid_sync de una fila existente', () async {
      final idCategoria = await DatabaseHelper.insertarConGuidSync(db, 'Categorias', {'nombre': 'Bebidas'});
      final guidEsperado = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria]))
          .first['guid_sync'] as String;

      final resolver = FkResolver(db);
      final guid = await resolver.guidPorIdLocal('Categorias', idCategoria);

      expect(guid, guidEsperado);
    });

    test('guidPorIdLocal lanza ArgumentError para una tabla no sincronizable', () async {
      final resolver = FkResolver(db);
      expect(() => resolver.guidPorIdLocal('Reporte', 1), throwsArgumentError);
    });

    test('registrar primea la caché sin necesidad de consultar la base', () async {
      final resolver = FkResolver(db);
      resolver.registrar('Categorias', 'guid-manual', 999);

      // Si no usara la caché, esta consulta fallaría (no existe id 999 en
      // la base real) devolviendo null en vez del valor primeado.
      expect(await resolver.idLocalPorGuid('Categorias', 'id_categoria', 'guid-manual'), 999);
      expect(await resolver.guidPorIdLocal('Categorias', 999), 'guid-manual');
    });
  });

  group('categoriaMapper', () {
    test('aBackend arma el payload camelCase con el sobre común', () async {
      final idCategoria = await DatabaseHelper.insertarConGuidSync(db, 'Categorias', {'nombre': 'Bebidas'});
      final filaLocal = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria])).first;

      final payload = await categoriaMapper.aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: FkResolver(db),
      );

      expect(payload['id'], filaLocal['guid_sync']);
      expect(payload['tenantId'], _tenantId);
      expect(payload['nombre'], 'Bebidas');
      expect(payload['activo'], isTrue);
      expect(payload['isDeleted'], isFalse);
      expect(payload['fechaCreacion'], isNotNull);
      expect(payload['fechaModificacion'], isNotNull);
      // No debe filtrar ninguna columna snake_case cruda al payload.
      expect(payload.containsKey('id_categoria'), isFalse);
      expect(payload.containsKey('guid_sync'), isFalse);
    });

    test('aBackend lanza StateError si la fila no tiene guid_sync', () async {
      final idCategoria = await db.insert('Categorias', {'nombre': 'Sin guid'});
      final filaLocal = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria])).first;

      expect(
        () => categoriaMapper.aBackend(
          filaLocal: filaLocal,
          tenantId: _tenantId,
          usuarioIdSync: _usuarioIdSync,
          resolver: FkResolver(db),
        ),
        throwsStateError,
      );
    });

    test('upsertLocal inserta una fila nueva cuando el guid no existe localmente', () async {
      final resolver = FkResolver(db);
      await categoriaMapper.upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-backend-1',
          'nombre': 'Lácteos',
          'isDeleted': false,
        },
        resolver: resolver,
      );

      final filas = await db.query('Categorias', where: 'guid_sync = ?', whereArgs: ['guid-backend-1']);
      expect(filas, hasLength(1));
      expect(filas.first['nombre'], 'Lácteos');

      // La caché del resolver queda primeada tras el insert (para que un
      // segundo elemento del mismo pull que referencie este guid como FK no
      // dispare otra consulta).
      expect(await resolver.idLocalPorGuid('Categorias', 'id_categoria', 'guid-backend-1'), filas.first['id_categoria']);
    });

    test('upsertLocal actualiza la fila existente cuando el guid ya existe localmente', () async {
      final idCategoria = await DatabaseHelper.insertarConGuidSync(db, 'Categorias', {'nombre': 'Nombre viejo'});
      final guid = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria]))
          .first['guid_sync'] as String;

      await categoriaMapper.upsertLocal(
        db: db,
        elementoBackend: {'id': guid, 'nombre': 'Nombre nuevo', 'isDeleted': false},
        resolver: FkResolver(db),
      );

      final filas = await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria]);
      expect(filas, hasLength(1)); // no duplicó la fila
      expect(filas.first['nombre'], 'Nombre nuevo');
      expect(filas.first['guid_sync'], guid); // no lo tocó
    });

    test('upsertLocal ignora un elemento marcado isDeleted sin fallar', () async {
      await categoriaMapper.upsertLocal(
        db: db,
        elementoBackend: {'id': 'guid-borrado', 'nombre': 'Lo que sea', 'isDeleted': true},
        resolver: FkResolver(db),
      );

      final filas = await db.query('Categorias', where: 'guid_sync = ?', whereArgs: ['guid-borrado']);
      expect(filas, isEmpty);
    });
  });

  group('clienteMapper', () {
    test('aBackend convierte telefono de int local a string backend', () async {
      final idCliente = await DatabaseHelper.insertarConGuidSync(db, 'Clientes', {
        'nombre': 'Cliente Uno',
        'direccion': 'Calle 1',
        'telefono': 5551234567,
        'correo': 'uno@test.com',
      });
      final filaLocal = (await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [idCliente])).first;

      final payload = await clienteMapper.aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: FkResolver(db),
      );

      expect(payload['telefono'], '5551234567');
      expect(payload['email'], 'uno@test.com');
    });

    test('upsertLocal convierte telefono de string backend a int local', () async {
      await clienteMapper.upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-cliente-1',
          'nombre': 'Cliente Backend',
          'direccion': 'Av. Siempre Viva',
          'telefono': '5559876543',
          'email': 'backend@test.com',
          'isDeleted': false,
        },
        resolver: FkResolver(db),
      );

      final filas = await db.query('Clientes', where: 'guid_sync = ?', whereArgs: ['guid-cliente-1']);
      expect(filas.first['telefono'], 5559876543);
      expect(filas.first['correo'], 'backend@test.com');
    });

    test('aBackend tolera telefono null', () async {
      final idCliente = await DatabaseHelper.insertarConGuidSync(db, 'Clientes', {'nombre': 'Sin teléfono'});
      final filaLocal = (await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [idCliente])).first;

      final payload = await clienteMapper.aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: FkResolver(db),
      );

      expect(payload['telefono'], isNull);
    });
  });

  group('proveedorMapper', () {
    test('aBackend mapea nombre local a razonSocial backend', () async {
      final idProveedor = await DatabaseHelper.insertarConGuidSync(db, 'Proveedores', {
        'nombre': 'Distribuidora XYZ',
        'rfc': 'XYZ010101AAA',
        'telefono': '5550001111',
      });
      final filaLocal = (await db.query('Proveedores', where: 'id_proveedor = ?', whereArgs: [idProveedor])).first;

      final payload = await proveedorMapper.aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: FkResolver(db),
      );

      expect(payload['razonSocial'], 'Distribuidora XYZ');
      expect(payload['rfc'], 'XYZ010101AAA');
      expect(payload.containsKey('nombreContacto'), isFalse); // sin columna local, se omite
    });
  });

  group('EntityMapperRegistry', () {
    test('paraEntidad devuelve el mapper correcto para las 3 entidades registradas en 3b', () {
      expect(EntityMapperRegistry.paraEntidad('CategoriaProducto'), categoriaMapper);
      expect(EntityMapperRegistry.paraEntidad('Cliente'), clienteMapper);
      expect(EntityMapperRegistry.paraEntidad('Proveedor'), proveedorMapper);
    });

    test('paraEntidad lanza ArgumentError para una entidad no registrada', () {
      // 'Venta' ya no sirve como ejemplo de "no registrada" desde 3c (ver
      // entity_mapper_3c_test.dart) -- se usa una entidad que no existe ni
      // existirá en el registro del backend.
      expect(() => EntityMapperRegistry.paraEntidad('EntidadQueNoExiste'), throwsArgumentError);
    });

    test('tieneMapper distingue entidades registradas de no registradas', () {
      expect(EntityMapperRegistry.tieneMapper('Cliente'), isTrue);
      expect(EntityMapperRegistry.tieneMapper('EntidadQueNoExiste'), isFalse);
    });

    test('ordenPull incluye las 3 entidades de esta sub-fase', () {
      expect(EntityMapperRegistry.ordenPull, containsAll(['CategoriaProducto', 'Cliente', 'Proveedor']));
    });
  });
}
