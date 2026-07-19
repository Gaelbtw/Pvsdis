// Pruebas de que DevolucionesController exige una caja abierta del usuario
// que procesa la devolución: rechaza sin caja (sin tocar stock ni insertar
// nada), y cuando sí hay una usa la caja ACTUAL de quien devuelve — no
// necesariamente la misma bajo la que se hizo la venta original.
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
  late CajaController caja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_devoluciones_sin_caja_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventas = VentasController();
    devoluciones = DevolucionesController();
    caja = CajaController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();

    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
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
      'nombre': 'Producto de prueba',
      'descripcion': '',
      'precio': precio,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': stock});
    return id;
  }

  test('rechaza devolver sin caja abierta, sin tocar stock ni insertar nada', () async {
    // La venta se abre y cierra su propia caja solo para poder crearla;
    // luego se cierra esa caja antes de intentar la devolución.
    final idCajaVenta = await caja.abrirCaja(fondoInicial: 500);
    final idProducto = await crearProducto(stock: 20);

    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
    );
    await caja.cerrarCaja(idCaja: idCajaVenta, efectivoContado: 550);

    await expectLater(
      devoluciones.devolverParcial(
        idVenta: idVenta,
        motivo: 'Sin caja abierta',
        items: [
          {'id_producto': idProducto, 'cantidad': 2},
        ],
      ),
      throwsA(
        isA<Exception>().having((e) => e.toString(), 'mensaje', contains('abrir la caja')),
      ),
    );

    expect(await db.query('Devoluciones'), isEmpty);
    expect(await db.query('Detalle_Devolucion'), isEmpty);

    final stock = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stock.first['cantidad'], 15); // 20 - 5 vendidas, sin reintegro
  });

  test('la devolución usa la caja actualmente abierta de quien la procesa, no la de la venta original',
      () async {
    final idCajaVenta = await caja.abrirCaja(fondoInicial: 500);
    final idProducto = await crearProducto(stock: 20);

    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
    );
    await caja.cerrarCaja(idCaja: idCajaVenta, efectivoContado: 550);

    // Se abre una SEGUNDA caja (turno distinto) y se procesa la devolución
    // ahí: debe quedar ligada a esta caja nueva, no a la de la venta.
    final idCajaDevolucion = await caja.abrirCaja(fondoInicial: 300);

    final idDevolucion = await devoluciones.devolverParcial(
      idVenta: idVenta,
      motivo: 'Producto dañado',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
      ],
    );

    final devolucion =
        (await db.query('Devoluciones', where: 'id_devolucion = ?', whereArgs: [idDevolucion])).first;
    expect(devolucion['id_caja'], idCajaDevolucion);
    expect(devolucion['id_caja'], isNot(idCajaVenta));
  });

  test('el importe reembolsado en efectivo baja el efectivoEsperado de la caja que procesó la devolución',
      () async {
    final idCajaVenta = await caja.abrirCaja(fondoInicial: 0);
    final idProducto = await crearProducto(precio: 50, stock: 20);

    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 100.0},
      ],
    );
    await caja.cerrarCaja(idCaja: idCajaVenta, efectivoContado: 0);

    final idCajaDevolucion = await caja.abrirCaja(fondoInicial: 200);

    await devoluciones.devolverParcial(
      idVenta: idVenta,
      motivo: 'Una unidad defectuosa',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    final resumen = await caja.calcularResumenCaja(idCajaDevolucion);
    expect(resumen.devoluciones, 50.0);
    expect(resumen.ventasEfectivo, 0.0); // esta caja no tuvo ventas propias
    expect(resumen.efectivoEsperado, 150.0); // 200 (fondo) - 50 (reembolso)
  });
}
