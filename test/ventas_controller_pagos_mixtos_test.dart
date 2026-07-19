// Pruebas de VentasController.insertarVentaCompleta con pagos mixtos: un
// solo método, varios métodos, cambio, exceso inválido, método no
// reconocido, cómo se guarda Ventas.metodo_pago ('Mixto' con 2+ métodos),
// el desglose en la auditoría, y que un fallo a mitad de la venta revierta
// también las filas ya insertadas en Venta_Pagos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  late VentasController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_ventas_pagos_mixtos_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = VentasController();

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
      'nombre': 'Producto de prueba',
      'descripcion': '',
      'precio': precio,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': stock});
    return id;
  }

  Future<Map<String, dynamic>> ventaGuardada(int idVenta) async {
    final rows = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> pagosGuardados(int idVenta) async {
    return db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVenta], orderBy: 'id');
  }

  test('un solo método (efectivo exacto) se guarda sin cambio', () async {
    final idProducto = await crearProducto(precio: 10);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['metodo_pago'], 'Efectivo');
    expect((venta['cambio'] as num).toDouble(), 0);

    final pagos = await pagosGuardados(idVenta);
    expect(pagos, hasLength(1));
    expect(pagos.first['metodo_pago'], 'Efectivo');
    expect((pagos.first['monto'] as num).toDouble(), 50.0);
  });

  test('efectivo con exceso calcula y persiste el cambio', () async {
    final idProducto = await crearProducto(precio: 10);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect((venta['cambio'] as num).toDouble(), 50.0);
  });

  test('varios métodos que suman exacto se guardan como Mixto', () async {
    final idProducto = await crearProducto(precio: 10);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 30.0},
        {'metodo_pago': 'Tarjeta', 'monto': 20.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['metodo_pago'], 'Mixto');
    expect((venta['cambio'] as num).toDouble(), 0);

    final pagos = await pagosGuardados(idVenta);
    expect(pagos, hasLength(2));
    expect(pagos[0]['metodo_pago'], 'Efectivo');
    expect((pagos[0]['monto'] as num).toDouble(), 30.0);
    expect(pagos[1]['metodo_pago'], 'Tarjeta');
    expect((pagos[1]['monto'] as num).toDouble(), 20.0);
  });

  test('tarjeta con exceso es rechazada y no persiste nada', () async {
    final idProducto = await crearProducto(precio: 10);

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
        ],
        pagos: const [
          {'metodo_pago': 'Tarjeta', 'monto': 100.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
    expect(await db.query('Venta_Pagos'), isEmpty);
  });

  test('efectivo con exceso + tarjeta es rechazado (exceso por método electrónico)', () async {
    final idProducto = await crearProducto(precio: 10);

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 40.0},
          {'metodo_pago': 'Tarjeta', 'monto': 20.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
  });

  test('pago insuficiente es rechazado', () async {
    final idProducto = await crearProducto(precio: 10);

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
  });

  test('método de pago no reconocido es rechazado', () async {
    final idProducto = await crearProducto(precio: 10);

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
        ],
        pagos: const [
          {'metodo_pago': 'Bitcoin', 'monto': 50.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
  });

  test('la auditoría de creación incluye el desglose de pagos y el cambio', () async {
    final idProducto = await crearProducto(precio: 10);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 5},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
    );

    final auditorias = await db.query(
      'Auditorias',
      where: "tabla = 'Ventas' AND accion = 'CREATE' AND id_registro = ?",
      whereArgs: [idVenta],
    );
    expect(auditorias, hasLength(1));
    final descripcion = auditorias.first['descripcion'] as String;
    expect(descripcion, contains('Efectivo'));
    expect(descripcion, contains('Cambio entregado'));
  });

  test('rollback: pagos válidos pero stock insuficiente no deja nada guardado (ni Venta_Pagos)', () async {
    final idProductoA = await crearProducto(precio: 10, stock: 50);
    final idProductoB = await crearProducto(precio: 5, stock: 1); // insuficiente para 3

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProductoA, 'nombre': 'A', 'precio': 10.0, 'cantidad': 2},
          {'id_producto': idProductoB, 'nombre': 'B', 'precio': 5.0, 'cantidad': 3},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
          {'metodo_pago': 'Tarjeta', 'monto': 15.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
    expect(await db.query('Detalle_Venta'), isEmpty);
    expect(await db.query('Venta_Pagos'), isEmpty);

    final stockA = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProductoA]);
    expect(stockA.first['cantidad'], 50); // no se descontó nada
  });
}
