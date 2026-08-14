// Prueba de migración v22 -> v23 (SKU e IVA por producto, merma en
// devoluciones, puerto del cajón).
//
// En vez de reescribir a mano todo el esquema anterior, se crea la base con el
// esquema REAL de la app y luego se le quitan justo las novedades de la v23,
// dejándola marcada como v22. Así lo que se migra es una base completa y
// realista —no una maqueta que podría diferir de la de un cliente— y la prueba
// ejercita exactamente el mismo camino de `_onUpgrade` que correrá al
// actualizar la app en el negocio.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

Future<bool> _indiceExiste(Database db, String nombre) async {
  final filas = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
    [nombre],
  );
  return filas.isNotEmpty;
}

/// Deja la base como estaba en la v22: sin las columnas nuevas y con
/// `user_version` en 22, para que al reabrirla con la app se dispare el bloque
/// `oldVersion < 23`.
Future<void> _revertirAV22(Database db) async {
  await db.execute('DROP INDEX IF EXISTS idx_producto_sku');
  await db.execute('ALTER TABLE Producto DROP COLUMN sku');
  await db.execute('ALTER TABLE Producto DROP COLUMN iva_tasa');
  await db.execute('ALTER TABLE Devoluciones DROP COLUMN reintegro_inventario');
  await db.execute('ALTER TABLE configuracion DROP COLUMN cajon_puerto');
  await db.execute('ALTER TABLE configuracion DROP COLUMN cajon_baudios');
  await db.execute('PRAGMA user_version = 22');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;

  /// Última conexión abierta por la prueba. Se guarda aparte porque estas
  /// pruebas abren la base directamente (no por el singleton de
  /// DatabaseHelper), y en Windows no se puede borrar el archivo temporal
  /// mientras siga abierto.
  Database? abierta;

  Future<Database> abrir() async {
    abierta = await DatabaseHelper().abrirEnRuta(path);
    return abierta!;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_migracion_v23');
    path = join(tempDir.path, 'test.db');
  });

  tearDown(() async {
    await abierta?.close();
    abierta = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('agrega SKU, IVA por producto, merma y puerto del cajón sin perder datos', () async {
    // 1. Base al día, con datos, revertida al esquema de la v22.
    var db = await abrir();

    final idCategoria = await db.insert('Categorias', {'nombre': 'Bebidas'});
    final idProducto = await db.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': 'de lata',
      'precio': 18.5,
      'precio_compra': 12.0,
      'stock_minimo': 3,
      'estado': 'Activo',
      'id_categoria': idCategoria,
      'codigo_barras': '7501234567890',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 20});
    final idVenta = await db.insert('Ventas', {
      'fecha': DateTime.now().toIso8601String(),
      'total': 18.5,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });
    final idDevolucion = await db.insert('Devoluciones', {
      'id_venta': idVenta,
      'fecha_hora': DateTime.now().toIso8601String(),
      'tipo': 'Parcial',
      'motivo': 'Producto equivocado',
      'importe': 18.5,
    });

    await _revertirAV22(db);
    await db.close();

    // 2. Reabrir con la app: dispara la migración a la v23.
    db = await abrir();

    final columnasProducto = await _columnas(db, 'Producto');
    expect(columnasProducto, containsAll(<String>['sku', 'iva_tasa']));
    expect(await _columnas(db, 'Devoluciones'), contains('reintegro_inventario'));
    expect(
      await _columnas(db, 'configuracion'),
      containsAll(<String>['cajon_puerto', 'cajon_baudios']),
    );
    expect(await _indiceExiste(db, 'idx_producto_sku'), isTrue);

    // 3. Los datos siguen ahí y las columnas nuevas nacen con el valor que
    //    conserva el comportamiento anterior: sin SKU, sin tasa propia (usa la
    //    general) y devoluciones que sí reintegran al inventario.
    final producto = (await db.query('Producto', where: 'id_producto = ?', whereArgs: [idProducto])).single;
    expect(producto['nombre'], 'Refresco');
    expect(producto['codigo_barras'], '7501234567890');
    expect(producto['sku'], isNull);
    expect(producto['iva_tasa'], isNull);

    final devolucion =
        (await db.query('Devoluciones', where: 'id_devolucion = ?', whereArgs: [idDevolucion])).single;
    expect(devolucion['motivo'], 'Producto equivocado');
    expect(devolucion['reintegro_inventario'], 1);

    // 4. Reabrir otra vez no vuelve a migrar ni rompe nada (idempotencia).
    await db.close();
    db = await abrir();
    expect(await _columnas(db, 'Producto'), containsAll(<String>['sku', 'iva_tasa']));
    expect(
      (await db.query('Producto', where: 'id_producto = ?', whereArgs: [idProducto])).single['nombre'],
      'Refresco',
    );
  });

  test('el índice de SKU impide duplicados pero permite varios sin clave', () async {
    final db = await abrir();

    Future<int> insertar(String nombre, String? sku) => db.insert('Producto', {
          'nombre': nombre,
          'descripcion': '',
          'precio': 10.0,
          'estado': 'Activo',
          'sku': sku,
        });

    await insertar('A', 'CLAVE-1');
    await insertar('B', null);
    await insertar('C', null);

    expect(
      () => insertar('D', 'CLAVE-1'),
      throwsA(isA<DatabaseException>()),
    );
  });
}
