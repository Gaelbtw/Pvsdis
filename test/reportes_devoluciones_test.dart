// Pruebas de que los reportes excluyen/descuentan devoluciones
// correctamente: las ventas canceladas no cuentan como ingreso, y las
// parcialmente devueltas cuentan por su monto neto. (La cobertura de corte
// de caja por devoluciones vive ahora en test/caja_controller_test.dart y
// test/devoluciones_sin_caja_test.dart, contra la caja persistente en vez
// del corte por día calendario.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late DevolucionesController devoluciones;
  late ReporteController reportes;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reportes_devoluciones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    devoluciones = DevolucionesController();
    reportes = ReporteController();

    // DevolucionesController exige caja abierta; sin SessionManager.setUser
    // cae en id_usuario=1 (ver `?? 1`), así que se siembra ese usuario
    // (requerido por la FK de Cajas.id_usuario) y su caja abierta.
    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
    });
    await db.insert('Cajas', {
      'id_usuario': 1,
      'fecha_apertura': DateTime.now().toIso8601String(),
      'fondo_inicial': 500,
      'estado': 'Abierta',
    });
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

    final total = precio * cantidad;

    final idVenta = await db.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': fecha ?? DateTime.now().toIso8601String(),
      'total': total,
      'metodo_pago': metodoPago,
      'estado': 'Activa',
    });

    // Estas ventas se insertan directo con `db.insert` (sin pasar por
    // VentasController) para simular datos ya existentes; se agrega la fila
    // de Venta_Pagos a mano para que quede consistente con lo que dejaría
    // una venta real.
    await db.insert('Venta_Pagos', {
      'id_venta': idVenta,
      'metodo_pago': metodoPago,
      'monto': total,
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
}
