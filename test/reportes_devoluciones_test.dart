// Pruebas de que reportes y corte de caja excluyen/descuentan
// devoluciones correctamente: las ventas canceladas no cuentan como
// ingreso, las parcialmente devueltas cuentan por su monto neto, y el
// corte de caja descuenta las devoluciones procesadas en el día (sin
// importar la fecha de la venta original).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/cortecaja_controller.dart';
import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late DevolucionesController devoluciones;
  late ReporteController reportes;
  late CorteCajaController corteCaja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reportes_devoluciones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    devoluciones = DevolucionesController();
    reportes = ReporteController();
    corteCaja = CorteCajaController();
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> crearVenta({
    required double precio,
    required int cantidad,
    String metodoPago = 'efectivo',
    String? fecha,
  }) async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto',
      'descripcion': '',
      'precio': precio,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 100});

    final idVenta = await db.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': fecha ?? DateTime.now().toIso8601String(),
      'total': precio * cantidad,
      'metodo_pago': metodoPago,
      'estado': 'Activa',
    });

    await db.insert('Detalle_Venta', {
      'id_venta': idVenta,
      'id_producto': idProducto,
      'cantidad': cantidad,
      'precio': precio,
    });

    await db.rawUpdate(
      'UPDATE Inventario SET cantidad = cantidad - ? WHERE id_producto = ?',
      [cantidad, idProducto],
    );

    return idVenta;
  }

  Future<int> idProductoDeVenta(int idVenta) async {
    final rows = await db.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
    return rows.first['id_producto'] as int;
  }

  test('el reporte excluye ventas canceladas del conteo y del ingreso', () async {
    final idVentaCancelada = await crearVenta(precio: 100, cantidad: 1);
    await crearVenta(precio: 30, cantidad: 1, metodoPago: 'tarjeta');

    await devoluciones.cancelarVenta(idVenta: idVentaCancelada, motivo: 'Cancelada para prueba');

    final hoy = DateTime.now();
    final resumen = await reportes.obtenerReporteVentas(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    expect(resumen.totalVentas, 1); // solo la de $30, la cancelada se excluye
    expect(resumen.ingresosTotales, 30.0);
  });

  test('el reporte descuenta lo devuelto de una venta parcialmente devuelta', () async {
    final idVenta = await crearVenta(precio: 10, cantidad: 5); // total 50
    final idProducto = await idProductoDeVenta(idVenta);

    await devoluciones.devolverParcial(
      idVenta: idVenta,
      motivo: 'Parcial para prueba',
      items: [
        {'id_producto': idProducto, 'cantidad': 2}, // devuelve $20
      ],
    );

    final hoy = DateTime.now();
    final resumen = await reportes.obtenerReporteVentas(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    expect(resumen.totalVentas, 1); // sigue contando como una venta
    expect(resumen.ingresosTotales, 30.0); // 50 - 20
  });

  test('el listado de ventas sigue mostrando las canceladas con su estado', () async {
    final idVenta = await crearVenta(precio: 100, cantidad: 1);
    await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Cancelada');

    final hoy = DateTime.now();
    final resumen = await reportes.obtenerReporteVentas(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    expect(resumen.ventasRecientes, hasLength(1));
    expect(resumen.ventasRecientes.first['estado'], 'Cancelada');
    expect(resumen.ventasRecientes.first['total_neto'], 0.0);
  });

  test('el corte de caja descuenta devoluciones procesadas hoy del bucket correcto', () async {
    final idVentaEfectivo = await crearVenta(precio: 100, cantidad: 1, metodoPago: 'efectivo');
    await crearVenta(precio: 50, cantidad: 1, metodoPago: 'tarjeta');
    final idProducto = await idProductoDeVenta(idVentaEfectivo);

    await devoluciones.devolverParcial(
      idVenta: idVentaEfectivo,
      motivo: 'Devolución de hoy',
      items: [
        {'id_producto': idProducto, 'cantidad': 1}, // devuelve los $100 completos
      ],
    );

    final resumen = await corteCaja.calcularResumenDelDia(DateTime.now());

    expect(resumen.efectivo, 0.0); // 100 - 100
    expect(resumen.tarjeta, 50.0);
    expect(resumen.total, 50.0);
    expect(resumen.devoluciones, 100.0);
  });

  test('el corte de caja descuenta una devolución de hoy aunque la venta original sea de otro día', () async {
    final ayer = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final idVenta = await crearVenta(precio: 80, cantidad: 1, fecha: ayer);
    final idProducto = await idProductoDeVenta(idVenta);

    // La venta de ayer no aparece en el corte de hoy...
    final antes = await corteCaja.calcularResumenDelDia(DateTime.now());
    expect(antes.efectivo, 0.0);

    // ...pero si se devuelve hoy, el efectivo que sale del cajón hoy sí debe reflejarse.
    await devoluciones.devolverParcial(
      idVenta: idVenta,
      motivo: 'Devolución tardía',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    final despues = await corteCaja.calcularResumenDelDia(DateTime.now());
    expect(despues.efectivo, -80.0);
    expect(despues.devoluciones, 80.0);
  });
}
