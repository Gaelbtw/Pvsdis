// Pruebas de ReporteController.obtenerTotalesPorMetodoPago: agrega
// ingresos por método de pago sobre Venta_Pagos (no sobre
// Ventas.metodo_pago, que vale 'Mixto' cuando hay 2+ métodos), y las
// devoluciones siempre se restan del bucket 'Efectivo' sin importar el
// método de la venta original (el reembolso siempre se entrega en
// efectivo).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/models/configuracion_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late VentasController ventas;
  late DevolucionesController devoluciones;
  late ReporteController reportes;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reporte_pagos_mixtos_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventas = VentasController();
    devoluciones = DevolucionesController();
    reportes = ReporteController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
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
    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> crearProducto({double precio = 10, int stock = 100}) async {
    final id = await db.insert('Producto', {
      'nombre': 'Producto',
      'descripcion': '',
      'precio': precio,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': stock});
    return id;
  }

  test('agrega ingresos por método incluyendo ventas con pagos mixtos', () async {
    final idA = await crearProducto(precio: 60);
    await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idA, 'nombre': 'Producto', 'precio': 60.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 60.0},
      ],
    );

    final idB = await crearProducto(precio: 40);
    await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idB, 'nombre': 'Producto', 'precio': 40.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 40.0},
      ],
    );

    final idC = await crearProducto(precio: 50);
    await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idC, 'nombre': 'Producto', 'precio': 50.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 30.0},
        {'metodo_pago': 'Transferencia', 'monto': 20.0},
      ],
    );

    final hoy = DateTime.now();
    final totales = await reportes.obtenerTotalesPorMetodoPago(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    expect(totales['Efectivo'], 90.0); // 60 + 30
    expect(totales['Tarjeta'], 40.0);
    expect(totales['Transferencia'], 20.0);
  });

  test('una devolución resta del bucket Efectivo aunque la venta original sea con tarjeta', () async {
    final idProducto = await crearProducto(precio: 100);
    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 100.0},
      ],
    );

    await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Cliente canceló');

    final hoy = DateTime.now();
    final totales = await reportes.obtenerTotalesPorMetodoPago(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    // La venta cancelada se excluye del agregado por método (mismo criterio
    // que el resumen de ventas), así que Tarjeta ya no aparece con 100; el
    // punto central de esta prueba es que el reembolso NO resta del bucket
    // Tarjeta (quedaría negativo) sino que el bucket Efectivo, sin ventas en
    // efectivo ese día, se queda en 0 (nunca negativo).
    expect(totales['Tarjeta'] ?? 0, 0);
    expect(totales['Efectivo'] ?? 0, 0);
  });

  test('una devolución parcial resta del bucket Efectivo cuando la venta sí sigue activa', () async {
    final idEfectivo = await crearProducto(precio: 20);
    await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idEfectivo, 'nombre': 'Producto', 'precio': 20.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 20.0},
      ],
    );

    final idTarjeta = await crearProducto(precio: 100);
    final idVentaTarjeta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idTarjeta, 'nombre': 'Producto', 'precio': 100.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 200.0},
      ],
    );

    // Devuelve solo 1 de las 2 unidades: la venta queda "Parcialmente
    // devuelta" (no "Cancelada"), así que su Venta_Pagos original sigue
    // contando íntegro en el bucket Tarjeta.
    await devoluciones.devolverParcial(
      idVenta: idVentaTarjeta,
      motivo: 'Una unidad defectuosa',
      items: [
        {'id_producto': idTarjeta, 'cantidad': 1},
      ],
    );

    final hoy = DateTime.now();
    final totales = await reportes.obtenerTotalesPorMetodoPago(
      desde: hoy,
      hasta: hoy,
      filtrarPorUsuario: false,
    );

    expect(totales['Tarjeta'], 200.0); // Venta_Pagos no se toca, sigue "Activa"
    expect(totales['Efectivo'], 0.0); // 20 recibidos - 100 devueltos, nunca negativo
  });
}
