// Migración v25 -> v26: columnas de mantenimiento e índices que faltaban para
// los rangos de fecha de los reportes.
//
// Los índices son lo importante de esta migración. Los reportes filtran con
// `date(columna) BETWEEN date(?) AND date(?)`, y envolver la columna en una
// función impide usar un índice normal: SQLite tiene que evaluar `date()` fila
// por fila, es decir recorrer la tabla entera. Ventas y Compras ya tenían el
// índice sobre la expresión; Devoluciones, Apartados y los abonos no.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

Future<bool> _indice(Database db, String nombre) async {
  final filas = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
    [nombre],
  );
  return filas.isNotEmpty;
}

/// Plan de ejecución de una consulta. Si menciona el índice, el planificador
/// lo está usando; si dice `SCAN`, está recorriendo la tabla completa.
Future<String> _plan(Database db, String sql, [List<Object?> args = const []]) async {
  final filas = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
  return filas.map((f) => f['detail']).join(' | ');
}

Future<void> _revertirAV25(Database db) async {
  await db.execute('ALTER TABLE configuracion DROP COLUMN equipo_codigo');
  await db.execute('ALTER TABLE configuracion DROP COLUMN auditoria_meses_retencion');
  await db.execute('ALTER TABLE configuracion DROP COLUMN auditoria_purga_ultima');
  await db.execute('DROP INDEX IF EXISTS idx_devoluciones_fecha_dia');
  await db.execute('DROP INDEX IF EXISTS idx_apartado_abonos_fecha_dia');
  await db.execute('DROP INDEX IF EXISTS idx_apartados_fecha_creacion_dia');
  await db.execute('DROP INDEX IF EXISTS idx_movimiento_inventario_fecha');
  await db.execute('DROP INDEX IF EXISTS idx_movimiento_inventario_id_producto');
  await db.execute('PRAGMA user_version = 25');
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_v26');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('agrega columnas e índices sin perder la configuración', () async {
    var db = await abrir();

    await db.insert('configuracion', {
      'id': 1,
      'nombre_negocio': 'Abarrotes La Esquina',
      'fondo_caja': 500.0,
      'edicion': 'pro',
    });

    await _revertirAV25(db);
    await db.close();

    db = await abrir();

    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>[
        'equipo_codigo',
        'auditoria_meses_retencion',
        'auditoria_purga_ultima',
      ]),
    );

    for (final indice in [
      'idx_devoluciones_fecha_dia',
      'idx_apartado_abonos_fecha_dia',
      'idx_apartados_fecha_creacion_dia',
      'idx_movimiento_inventario_fecha',
      'idx_movimiento_inventario_id_producto',
    ]) {
      expect(await _indice(db, indice), isTrue, reason: 'falta $indice');
    }

    final fila = (await db.query('configuracion', where: 'id = 1')).single;
    expect(fila['nombre_negocio'], 'Abarrotes La Esquina');
    expect(fila['fondo_caja'], 500.0);
    expect(fila['edicion'], 'pro');

    // La retención nace en 24 meses, pero solo para filas NUEVAS: a una
    // configuración que ya existía, ALTER TABLE le deja NULL. Quien lee debe
    // caer al valor por omisión, y así lo hace `purgarAntiguasSiToca`.
    expect(fila['auditoria_purga_ultima'], isNull);
    expect(fila['equipo_codigo'], isNull);
  });

  test('una instalación nueva nace con la retención en 24 meses', () async {
    final db = await abrir();
    await db.insert('configuracion', {'id': 1, 'nombre_negocio': 'Nueva'});

    final fila = (await db.query('configuracion', where: 'id = 1')).single;
    expect(fila['auditoria_meses_retencion'], 24);
    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
  });

  group('los índices de verdad se usan', () {
    test('el rango de fechas de devoluciones no recorre la tabla', () async {
      final db = await abrir();
      final plan = await _plan(
        db,
        'SELECT * FROM Devoluciones '
        'WHERE date(fecha_hora) BETWEEN date(?) AND date(?)',
        ['2026-01-01', '2026-12-31'],
      );
      expect(plan, contains('idx_devoluciones_fecha_dia'));
    });

    test('el rango de movimientos de inventario no recorre la tabla', () async {
      final db = await abrir();
      // La consulta real compara instantes UTC contra la columna cruda, que es
      // justo lo que permite indexarla: con `date(fecha,'localtime')` SQLite
      // no puede usar ningún índice, porque 'localtime' vuelve la expresión no
      // determinista y prohíbe indexarla.
      final plan = await _plan(
        db,
        'SELECT * FROM Movimiento_Inventario WHERE fecha >= ? AND fecha <= ?',
        ['2026-01-01T00:00:00.000Z', '2026-12-31T23:59:59.999Z'],
      );
      expect(plan, contains('idx_movimiento_inventario_fecha'));
    });

    test('el rango de abonos de apartados no recorre la tabla', () async {
      final db = await abrir();
      final plan = await _plan(
        db,
        'SELECT * FROM Apartado_Abonos '
        'WHERE date(fecha) BETWEEN date(?) AND date(?)',
        ['2026-01-01', '2026-12-31'],
      );
      expect(plan, contains('idx_apartado_abonos_fecha_dia'));
    });
  });
}
