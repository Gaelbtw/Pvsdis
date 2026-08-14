// Prueba de migración v23 -> v24: columnas de licencia en `configuracion`.
//
// Las columnas nacen VACÍAS y hoy nadie las lee. Están de una vez para que el
// día que se active el licenciamiento no haya que tocar el esquema en
// instalaciones que ya llevan meses en la calle: una migración que solo agrega
// campos que ya existen es un no-op, y no hay riesgo de que una base con
// ventas reales tenga que reconstruir tablas.
//
// Mismo método que el resto de pruebas de migración: se crea la base con el
// esquema REAL de la app y se le quitan justo las novedades de la v24, en vez
// de maquetar a mano un esquema viejo que podría no parecerse al del cliente.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

/// Deja la base como estaba en la v23.
Future<void> _revertirAV23(Database db) async {
  await db.execute('ALTER TABLE configuracion DROP COLUMN edicion');
  await db.execute('ALTER TABLE configuracion DROP COLUMN licencia_expira');
  await db.execute('PRAGMA user_version = 23');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;
  Database? abierta;

  Future<Database> abrir() async {
    abierta = await DatabaseHelper().abrirEnRuta(path);
    return abierta!;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_licencia_v24');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('agrega las columnas de licencia sin tocar la configuración existente',
      () async {
    var db = await abrir();

    // Configuración con datos del negocio, como la tendría un cliente real.
    await db.insert('configuracion', {
      'id': 1,
      'nombre_negocio': 'Abarrotes La Esquina',
      'simbolo_moneda': r'$',
      'tasa_impuesto': 16.0,
      'fondo_caja': 500.0,
      'stock_minimo': 5,
    });

    await _revertirAV23(db);
    await db.close();

    // Reabrir dispara el bloque `oldVersion < 24`.
    db = await abrir();

    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>['edicion', 'licencia_expira']),
    );

    final fila = (await db.query('configuracion', where: 'id = 1')).single;
    expect(fila['nombre_negocio'], 'Abarrotes La Esquina');
    expect(fila['tasa_impuesto'], 16.0);
    expect(fila['fondo_caja'], 500.0);

    // Nacen en NULL: sin licencia declarada, el comportamiento es el de hoy
    // (todo habilitado). Un DEFAULT 'basica' bloquearía módulos que el
    // cliente ya está usando en el momento de actualizar.
    expect(fila['edicion'], isNull);
    expect(fila['licencia_expira'], isNull);
  });

  test('una instalación nueva nace con las columnas', () async {
    // _onCreate y _onUpgrade tienen que dejar el mismo esquema: si solo se
    // agrega la columna en la migración, una PC recién instalada se queda sin
    // ella y falla justo donde nadie prueba.
    final db = await abrir();
    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>['edicion', 'licencia_expira']),
    );
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });

  test('reabrir no vuelve a migrar ni duplica columnas', () async {
    var db = await abrir();
    await _revertirAV23(db);
    await db.close();

    db = await abrir();
    await db.close();
    db = await abrir();

    final columnas = await _columnas(db, 'configuracion');
    expect(columnas, containsAll(<String>['edicion', 'licencia_expira']));
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });
}
