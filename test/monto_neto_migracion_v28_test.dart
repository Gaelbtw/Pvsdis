// Migración v27 -> v28: `monto_neto` en `Detalle_Venta` y `Detalle_Apartado`.
//
// Es el importe TOTAL cobrado por la línea, ya con promoción, descuento de
// línea y su parte del descuento global. Hasta la v27 solo se guardaba
// `precio_neto`, que es ese mismo importe dividido entre la cantidad y
// redondeado a dos decimales: tres piezas de $10 con $1 de descuento se
// cobraron en $29.00 pero se reconstruían como 9.67 x 3 = $29.01. La
// devolución entregaba un centavo de más, cada vez.
//
// El respaldo obvio —`precio * cantidad - descuento_monto`— no sirve: el
// ahorro por promoción nunca se guardó en `descuento_monto`, así que una
// línea con combo se devolvía por su precio de lista completo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

Future<void> _revertirAV27(Database db) async {
  await db.execute('ALTER TABLE Detalle_Venta DROP COLUMN monto_neto');
  await db.execute('ALTER TABLE Detalle_Apartado DROP COLUMN monto_neto');
  await db.execute('PRAGMA user_version = 27');
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_v28');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('agrega monto_neto y rellena las líneas viejas desde precio_neto', () async {
    var db = await abrir();

    await db.insert('Producto', {'id_producto': 1, 'nombre': 'Cuaderno', 'precio': 10.0});
    await db.insert('Ventas', {
      'id_venta': 1,
      'fecha': DateTime.now().toIso8601String(),
      'total': 29.0,
      'metodo_pago': 'Efectivo',
    });

    await _revertirAV27(db);

    // Línea vieja CON precio_neto: se rellena.
    await db.insert('Detalle_Venta', {
      'id_detalleV': 1,
      'id_venta': 1,
      'id_producto': 1,
      'cantidad': 3,
      'precio': 10.0,
      'descuento_monto': 1.0,
      'precio_neto': 9.67,
    });

    // Línea aún más vieja, SIN precio_neto: no se inventa un importe.
    await db.insert('Detalle_Venta', {
      'id_detalleV': 2,
      'id_venta': 1,
      'id_producto': 1,
      'cantidad': 2,
      'precio': 10.0,
      'precio_neto': null,
    });

    await abierta!.close();
    abierta = null;

    db = await abrir();

    expect(await db.getVersion(), DatabaseHelper.versionEsquema);
    expect((await _columnas(db, 'Detalle_Venta')).contains('monto_neto'), isTrue);
    expect((await _columnas(db, 'Detalle_Apartado')).contains('monto_neto'), isTrue);

    final filas = await db.query('Detalle_Venta', orderBy: 'id_detalleV');
    expect((filas[0]['monto_neto'] as num).toDouble(), closeTo(29.01, 0.0001),
        reason: 'El respaldo de una línea vieja es precio_neto * cantidad.');
    expect(filas[1]['monto_neto'], isNull,
        reason: 'Sin precio_neto no hay importe que reconstruir; NULL es honesto.');

    // El precio original y el desglose de descuento quedan intactos.
    expect((filas[0]['precio'] as num).toDouble(), 10.0);
    expect((filas[0]['descuento_monto'] as num).toDouble(), 1.0);
  });

  test('migrar dos veces no pisa lo ya escrito', () async {
    var db = await abrir();

    await db.insert('Producto', {'id_producto': 1, 'nombre': 'Pluma', 'precio': 10.0});
    await db.insert('Ventas', {
      'id_venta': 1,
      'fecha': DateTime.now().toIso8601String(),
      'total': 29.0,
      'metodo_pago': 'Efectivo',
    });
    await db.insert('Detalle_Venta', {
      'id_venta': 1,
      'id_producto': 1,
      'cantidad': 3,
      'precio': 10.0,
      'descuento_monto': 1.0,
      'precio_neto': 9.67,
      'monto_neto': 29.0, // el importe exacto que escribió la app
    });

    await db.execute('PRAGMA user_version = 27');
    await abierta!.close();
    abierta = null;

    db = await abrir();

    final fila = (await db.query('Detalle_Venta')).single;
    expect((fila['monto_neto'] as num).toDouble(), 29.0,
        reason: 'El backfill solo toca filas con monto_neto NULL.');
  });
}
