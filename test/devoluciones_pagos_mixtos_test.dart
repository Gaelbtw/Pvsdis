// Prueba de integración: una devolución sobre una venta pagada con varios
// métodos sigue calculando el importe sobre precio_neto (agnóstico al
// método de pago), y el corte de caja del día debe reflejar el reembolso
// como una salida 100% de efectivo, sin importar que la venta original se
// haya pagado con tarjeta/transferencia.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/devoluciones_controller.dart';
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
  late CajaController cajaController;
  late int idCaja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_devoluciones_pagos_mixtos_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventas = VentasController();
    devoluciones = DevolucionesController();
    cajaController = CajaController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
    });
    idCaja = await cajaController.abrirCaja(fondoInicial: 0);
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

  test('la devolución de una venta con pagos mixtos calcula el importe correcto y sale como efectivo', () async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto',
      'descripcion': '',
      'precio': 100.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 10});

    // Venta de $200 (2 unidades) pagada con Efectivo $80 + Tarjeta $120.
    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 100.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 80.0},
        {'metodo_pago': 'Tarjeta', 'monto': 120.0},
      ],
    );

    final idDevolucion = await devoluciones.devolverParcial(
      idVenta: idVenta,
      motivo: 'Una unidad defectuosa',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    // El importe se calcula sobre precio_neto (100.0, sin descuentos),
    // completamente ajeno a cómo se compuso el pago original.
    final comprobante = await devoluciones.obtenerComprobante(idDevolucion);
    expect(comprobante.importe, 100.0);

    final auditorias = await db.query(
      'Auditorias',
      where: "tabla = 'Ventas' AND accion = 'DEVOLUCION' AND id_registro = ?",
      whereArgs: [idVenta],
    );
    expect(auditorias, hasLength(1));
    expect(auditorias.first['descripcion'], contains('reembolsado en efectivo'));

    // El resumen de la caja debe reflejar el reembolso como salida de
    // efectivo, no de tarjeta (que fue el método usado para ese 60% de la
    // venta original). Fondo inicial de la caja es 0, así que
    // efectivoEsperado equivale directamente al neto de efectivo.
    final resumen = await cajaController.calcularResumenCaja(idCaja);
    expect(resumen.ventasEfectivo, 80.0); // lo cobrado en efectivo, sin tocar
    expect(resumen.ventasTarjeta, 120.0); // lo cobrado en tarjeta, sin tocar
    expect(resumen.devoluciones, 100.0);
    expect(resumen.efectivoEsperado, -20.0); // 80 recibido - 100 reembolsado en efectivo
  });

  test('la cancelación total de una venta con 3 métodos también se reembolsa en efectivo', () async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto',
      'descripcion': '',
      'precio': 300.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 5});

    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 300.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
        {'metodo_pago': 'Tarjeta', 'monto': 100.0},
        {'metodo_pago': 'Transferencia', 'monto': 100.0},
      ],
    );

    final idDevolucion = await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Cliente canceló');

    final comprobante = await devoluciones.obtenerComprobante(idDevolucion);
    expect(comprobante.importe, 300.0);

    final auditorias = await db.query(
      'Auditorias',
      where: "tabla = 'Ventas' AND accion = 'CANCEL' AND id_registro = ?",
      whereArgs: [idVenta],
    );
    expect(auditorias.first['descripcion'], contains('reembolsado en efectivo'));

    final resumen = await cajaController.calcularResumenCaja(idCaja);
    expect(resumen.devoluciones, 300.0);
    expect(resumen.efectivoEsperado, -200.0); // 100 recibido en efectivo - 300 reembolsado
  });
}
