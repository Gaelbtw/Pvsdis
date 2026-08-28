// Purga de la bitácora.
//
// `Auditorias` es la tabla que más crece: una fila por venta, por movimiento
// de stock, por cambio de precio y por login. La pantalla no sufre --pagina en
// SQL-- pero el archivo `.db` sí, y con él el respaldo diario a la USB, que es
// lo que de verdad se nota: tarda más cada mes hasta que alguien lo desconecta
// por lento.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/auditoria_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;
  late Database db;
  final hoy = DateTime(2026, 8, 14);

  Future<void> anotar(DateTime cuando, String descripcion) => db.insert(
        'Auditorias',
        {
          'fecha_hora': cuando.toIso8601String(),
          'usuario': 'admin',
          'tabla': 'Producto',
          'accion': 'EDIT',
          'descripcion': descripcion,
        },
      );

  Future<int> cuantas() async {
    // Se cuenta a mano en vez de usar `Sqflite.firstIntValue`: esa vive en
    // `package:sqflite`, e importarla junto a `sqflite_common_ffi` deja dos
    // definiciones de `Database` y `databaseFactory` compitiendo.
    final filas = await db.rawQuery('SELECT COUNT(*) AS n FROM Auditorias');
    return (filas.first['n'] as int?) ?? 0;
  }

  Future<void> configurar({int? meses, DateTime? ultimaPurga}) {
    final valores = <String, Object?>{
      'auditoria_purga_ultima': ultimaPurga?.toIso8601String(),
    };
    if (meses != null) valores['auditoria_meses_retencion'] = meses;
    return db.update('configuracion', valores);
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_purga');
    path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    await db.insert('configuracion', {'id': 1, 'nombre_negocio': 'Prueba'});
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('borra lo viejo y conserva lo reciente', () async {
    await anotar(DateTime(2023, 1, 15), 'hace tres años');
    await anotar(DateTime(2024, 1, 15), 'hace dos años y medio');
    await anotar(DateTime(2026, 1, 15), 'este año');
    await anotar(hoy, 'hoy');
    expect(await cuantas(), 4);

    final borradas =
        await AuditoriaController().purgarAntiguasSiToca(ahora: hoy);

    // Retención por omisión: 24 meses. El corte cae en agosto de 2024.
    expect(borradas, 2);
    expect(await cuantas(), 2);

    final quedan = await db.query('Auditorias', orderBy: 'fecha_hora');
    expect(
      quedan.map((f) => f['descripcion']),
      containsAll(<String>['este año', 'hoy']),
    );
  });

  test('no vuelve a revisar antes de una semana', () async {
    await anotar(DateTime(2020, 1, 1), 'antigua');
    await configurar(ultimaPurga: hoy.subtract(const Duration(days: 3)));

    expect(await AuditoriaController().purgarAntiguasSiToca(ahora: hoy), 0);
    expect(await cuantas(), 1, reason: 'no debía tocar nada todavía');
  });

  test('pasada la semana sí vuelve a revisar', () async {
    await anotar(DateTime(2020, 1, 1), 'antigua');
    await configurar(ultimaPurga: hoy.subtract(const Duration(days: 8)));

    expect(await AuditoriaController().purgarAntiguasSiToca(ahora: hoy), 1);
    expect(await cuantas(), 0);
  });

  test('retención en 0 conserva todo', () async {
    // Salida explícita para quien quiera la bitácora íntegra por política
    // contable: no es un valor inválido, es "no purgues nunca".
    await anotar(DateTime(2015, 1, 1), 'muy antigua');
    await configurar(meses: 0);

    expect(await AuditoriaController().purgarAntiguasSiToca(ahora: hoy), 0);
    expect(await cuantas(), 1);
  });

  test('deja anotada la fecha de la revisión', () async {
    await AuditoriaController().purgarAntiguasSiToca(ahora: hoy);

    final fila = (await db.query('configuracion', limit: 1)).single;
    expect(
      DateTime.parse(fila['auditoria_purga_ultima'] as String),
      hoy,
    );
  });

  test('sin fila de configuración no revienta', () async {
    // Primer arranque: la fila de `configuracion` se siembra en cuanto alguien
    // la pide, y la purga corre en segundo plano sin saber si ya pasó.
    await db.delete('configuracion');
    expect(await AuditoriaController().purgarAntiguasSiToca(ahora: hoy), 0);
  });
}
