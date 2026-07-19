// Pruebas de que VentasController.insertarVentaCompleta exige una caja
// abierta del usuario actual: rechaza sin caja (con rollback completo),
// guarda el id_caja correcto cuando sí hay una, y cada cajero asocia sus
// ventas a su propia caja cuando hay varias abiertas simultáneamente.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
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
  late CajaController caja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_ventas_sin_caja_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventas = VentasController();
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

  Future<int> crearUsuario(String rol, {String nombre = 'usuario'}) {
    return db.insert('Usuarios', {
      'nombre': nombre,
      'contra': PasswordHasher.hash('1234'),
      'rol': rol,
    });
  }

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

  test('rechaza vender sin caja abierta, sin dejar nada guardado', () async {
    final idProducto = await crearProducto();

    await expectLater(
      ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      ),
      throwsA(
        isA<Exception>().having((e) => e.toString(), 'mensaje', contains('abrir la caja')),
      ),
    );

    expect(await db.query('Ventas'), isEmpty);
    expect(await db.query('Venta_Pagos'), isEmpty);
    expect(await db.query('Detalle_Venta'), isEmpty);
  });

  test('con caja abierta, la venta guarda el id_caja correcto', () async {
    final idCaja = await caja.abrirCaja(fondoInicial: 500);
    final idProducto = await crearProducto();

    final idVenta = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 20.0},
      ],
    );

    final venta = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta])).first;
    expect(venta['id_caja'], idCaja);
  });

  test('cada cajero asocia su venta a su propia caja abierta, no a la del otro', () async {
    final idCajero1 = await crearUsuario('Cajero', nombre: 'Cajero1');
    final idCajero2 = await crearUsuario('Cajero', nombre: 'Cajero2');

    SessionManager.setUser(id: idCajero1, nombre: 'Cajero1', rol: 'Cajero');
    final idCaja1 = await caja.abrirCaja(fondoInicial: 200);

    SessionManager.setUser(id: idCajero2, nombre: 'Cajero2', rol: 'Cajero');
    final idCaja2 = await caja.abrirCaja(fondoInicial: 300);

    final idProducto = await crearProducto();

    // Cajero2 vende (sigue siendo el usuario activo de la sesión).
    final idVentaCajero2 = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 10.0},
      ],
    );

    final ventaCajero2 = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVentaCajero2])).first;
    expect(ventaCajero2['id_caja'], idCaja2);
    expect(ventaCajero2['id_caja'], isNot(idCaja1));

    // Cajero1 vende ahora.
    SessionManager.setUser(id: idCajero1, nombre: 'Cajero1', rol: 'Cajero');
    final idVentaCajero1 = await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 10.0},
      ],
    );

    final ventaCajero1 = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVentaCajero1])).first;
    expect(ventaCajero1['id_caja'], idCaja1);
  });

  test('pagos mixtos con cambio quedan reflejados en el resumen de esa caja específica', () async {
    final idCaja = await caja.abrirCaja(fondoInicial: 0);
    final idProducto = await crearProducto(precio: 850);

    await ventas.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 850.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 1000.0},
      ],
    );

    final resumen = await caja.calcularResumenCaja(idCaja);
    expect(resumen.ventasEfectivo, 1000.0);
    expect(resumen.cambioEntregado, 150.0);
    expect(resumen.efectivoEsperado, 850.0); // 0 + 1000 - 150
  });
}
