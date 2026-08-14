// Prueba de migración v24 -> v25: respaldo del estado de la licencia en la
// base de datos.
//
// `licencia_hash` es la contraparte del archivo `licencia.lic`. Si el archivo
// desaparece pero el hash sigue en la base, la app sabe que este equipo sí tuvo
// licencia y lo dice, en vez de tratarlo como una instalación nueva. Borrar la
// base para evadirlo cuesta todas las ventas, el inventario y los clientes: un
// precio que nadie paga por saltarse una mensualidad.
//
// `licencia_reloj` guarda el día más avanzado visto, para notar que el reloj
// del sistema retrocedió. No bloquea nada por sí solo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

Future<void> _revertirAV24(Database db) async {
  await db.execute('ALTER TABLE configuracion DROP COLUMN licencia_hash');
  await db.execute('ALTER TABLE configuracion DROP COLUMN licencia_reloj');
  await db.execute('PRAGMA user_version = 24');
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_licencia_v25');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('agrega el respaldo de licencia sin tocar lo que ya había', () async {
    var db = await abrir();

    await db.insert('configuracion', {
      'id': 1,
      'nombre_negocio': 'Abarrotes La Esquina',
      'edicion': 'pro',
      'licencia_expira': '2027-08-14',
      'fondo_caja': 500.0,
    });

    await _revertirAV24(db);
    await db.close();

    db = await abrir();

    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>['licencia_hash', 'licencia_reloj']),
    );

    // Las columnas de la v24 y los datos del negocio siguen intactos: la
    // migración agrega, no reconstruye.
    final fila = (await db.query('configuracion', where: 'id = 1')).single;
    expect(fila['nombre_negocio'], 'Abarrotes La Esquina');
    expect(fila['edicion'], 'pro');
    expect(fila['licencia_expira'], '2027-08-14');
    expect(fila['fondo_caja'], 500.0);

    // Nacen vacías: una instalación existente no tenía licencia y no debe
    // parecer que la tuvo.
    expect(fila['licencia_hash'], isNull);
    expect(fila['licencia_reloj'], isNull);
  });

  test('una instalación nueva nace con las columnas', () async {
    final db = await abrir();
    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>[
        'edicion',
        'licencia_expira',
        'licencia_hash',
        'licencia_reloj',
      ]),
    );
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });

  test('reabrir no vuelve a migrar', () async {
    var db = await abrir();
    await _revertirAV24(db);
    await db.close();

    db = await abrir();
    await db.close();
    db = await abrir();

    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>['licencia_hash', 'licencia_reloj']),
    );
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });
}
