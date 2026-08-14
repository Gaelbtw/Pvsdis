// Pruebas del reporte de movimientos de inventario.
//
// Es el reporte que responde "¿dónde quedaron las piezas que faltan?", así que
// lo que se verifica es que clasifique bien entradas y salidas, que aísle la
// merma, que respete los filtros y —lo más fácil de romper— que el rango de
// fechas funcione a pesar de que la bitácora guarda la hora en UTC.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/utils/motivo_ajuste_inventario.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late ReporteController controller;
  late int idProducto;

  final hoy = DateTime.now();

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reporte_movimientos');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = ReporteController();

    idProducto = await db.insert('Producto', {
      'nombre': 'Vaso',
      'descripcion': '',
      'precio': 25.0,
      'estado': 'Activo',
      'sku': 'VAS-1',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 10});
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Inserta un movimiento tal como lo escribe `MovimientoInventarioLogger`:
  /// con la fecha en UTC.
  Future<void> registrar({
    required String tipo,
    required int cantidad,
    String? motivo,
    DateTime? cuando,
  }) async {
    await db.insert('Movimiento_Inventario', {
      'id_producto': idProducto,
      'tipo_movimiento': tipo,
      'cantidad': cantidad,
      'cantidad_anterior': 10,
      'cantidad_nueva': 10,
      'motivo': motivo,
      'fecha': (cuando ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  test('separa piezas que entraron de las que salieron', () async {
    await registrar(tipo: 'EntradaCompra', cantidad: 12);
    await registrar(tipo: 'AjustePositivo', cantidad: 3);
    await registrar(tipo: 'SalidaVenta', cantidad: 5);
    await registrar(tipo: 'AjusteNegativo', cantidad: 2);

    final resumen = await controller.obtenerMovimientosInventario(desde: hoy, hasta: hoy);

    expect(resumen.movimientos, hasLength(4));
    expect(resumen.piezasEntrada, 15);
    expect(resumen.piezasSalida, 7);
  });

  test('la merma se cuenta aparte, dentro de las salidas', () async {
    await registrar(
      tipo: 'AjusteNegativo',
      cantidad: 4,
      motivo: MotivoAjusteInventario.merma.etiqueta,
    );
    await registrar(
      tipo: 'AjusteNegativo',
      cantidad: 1,
      motivo: MotivoAjusteInventario.conteoFisico.etiqueta,
    );

    final resumen = await controller.obtenerMovimientosInventario(desde: hoy, hasta: hoy);

    expect(resumen.piezasSalida, 5);
    expect(resumen.piezasMerma, 4);
  });

  test('trae el nombre y la clave del producto', () async {
    await registrar(tipo: 'SalidaVenta', cantidad: 1);

    final resumen = await controller.obtenerMovimientosInventario(desde: hoy, hasta: hoy);

    expect(resumen.movimientos.single['producto'], 'Vaso');
    expect(resumen.movimientos.single['sku'], 'VAS-1');
  });

  test('filtra por tipo de movimiento', () async {
    await registrar(tipo: 'SalidaVenta', cantidad: 5);
    await registrar(tipo: 'EntradaCompra', cantidad: 8);

    final resumen = await controller.obtenerMovimientosInventario(
      desde: hoy,
      hasta: hoy,
      tipoMovimiento: 'EntradaCompra',
    );

    expect(resumen.movimientos, hasLength(1));
    expect(resumen.piezasEntrada, 8);
    expect(resumen.piezasSalida, 0);
  });

  test('filtra por producto', () async {
    final otro = await db.insert('Producto', {
      'nombre': 'Plato',
      'descripcion': '',
      'precio': 30.0,
      'estado': 'Activo',
    });
    await registrar(tipo: 'SalidaVenta', cantidad: 3);
    await db.insert('Movimiento_Inventario', {
      'id_producto': otro,
      'tipo_movimiento': 'SalidaVenta',
      'cantidad': 9,
      'cantidad_anterior': 20,
      'cantidad_nueva': 11,
      'fecha': DateTime.now().toUtc().toIso8601String(),
    });

    final resumen = await controller.obtenerMovimientosInventario(
      desde: hoy,
      hasta: hoy,
      idProducto: idProducto,
    );

    expect(resumen.movimientos, hasLength(1));
    expect(resumen.piezasSalida, 3);
  });

  test('deja fuera lo que cae fuera del rango', () async {
    await registrar(
      tipo: 'SalidaVenta',
      cantidad: 6,
      cuando: hoy.subtract(const Duration(days: 10)),
    );
    await registrar(tipo: 'SalidaVenta', cantidad: 2);

    final resumen = await controller.obtenerMovimientosInventario(
      desde: hoy.subtract(const Duration(days: 2)),
      hasta: hoy,
    );

    expect(resumen.movimientos, hasLength(1));
    expect(resumen.piezasSalida, 2);
  });

  test('un movimiento de hoy en la noche no se va al día siguiente', () async {
    // La bitácora guarda UTC; con la conversión mal hecha, un movimiento hecho
    // por la noche en América cae en el día siguiente y desaparece del reporte
    // de "hoy". Se usa una hora tardía del día local para ejercer ese caso.
    final estaNoche = DateTime(hoy.year, hoy.month, hoy.day, 22, 30);
    await registrar(tipo: 'SalidaVenta', cantidad: 4, cuando: estaNoche);

    final resumen = await controller.obtenerMovimientosInventario(
      desde: estaNoche,
      hasta: estaNoche,
    );

    expect(resumen.movimientos, hasLength(1));
    expect(resumen.piezasSalida, 4);
  });
}
