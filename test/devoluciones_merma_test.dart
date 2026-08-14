// Pruebas de la devolución con merma: cuando la mercancía regresa inservible,
// se devuelve el dinero pero las piezas NO vuelven al inventario.
//
// Lo importante es que las dos mitades de la operación se separen bien: el
// dinero (que siempre sale de la caja) y la mercancía (que puede o no volver).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late DevolucionesController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_merma_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = DevolucionesController();

    SessionManager.setUser(id: 1, nombre: 'Sistema', rol: 'Admin');
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
    SessionManager.clear();
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Venta de 3 piezas de un producto que quedó con 7 en existencia.
  Future<({int idVenta, int idProducto})> crearVenta() async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Playera',
      'descripcion': '',
      'precio': 100.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 7});

    final idVenta = await db.insert('Ventas', {
      'fecha': DateTime.now().toIso8601String(),
      'total': 300.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });
    await db.insert('Detalle_Venta', {
      'id_venta': idVenta,
      'id_producto': idProducto,
      'cantidad': 3,
      'precio': 100.0,
    });

    return (idVenta: idVenta, idProducto: idProducto);
  }

  Future<int> stockDe(int idProducto) async {
    final filas = await db.query(
      'Inventario',
      columns: ['cantidad'],
      where: 'id_producto = ?',
      whereArgs: [idProducto],
    );
    return filas.first['cantidad'] as int;
  }

  Future<double> efectivoDevueltoEnCaja() async {
    final filas = await db.query(
      'Movimiento_Caja',
      where: 'tipo_movimiento = ?',
      whereArgs: ['DevolucionEfectivo'],
    );
    return filas.fold<double>(0, (acc, f) => acc + ((f['monto'] as num).toDouble()));
  }

  test('una devolución normal sí regresa la mercancía al inventario', () async {
    final venta = await crearVenta();

    await controller.devolverParcial(
      idVenta: venta.idVenta,
      motivo: 'Talla equivocada',
      items: [
        {'id_producto': venta.idProducto, 'cantidad': 2},
      ],
    );

    expect(await stockDe(venta.idProducto), 9);
    expect(await efectivoDevueltoEnCaja(), -200);

    final devolucion = (await db.query('Devoluciones')).single;
    expect(devolucion['reintegro_inventario'], 1);
  });

  test('con merma se devuelve el dinero pero el inventario no cambia', () async {
    final venta = await crearVenta();

    await controller.devolverParcial(
      idVenta: venta.idVenta,
      motivo: 'Llegó rota',
      items: [
        {'id_producto': venta.idProducto, 'cantidad': 2},
      ],
      reintegrarInventario: false,
    );

    expect(await stockDe(venta.idProducto), 7, reason: 'la mercancía dañada no vuelve a estar disponible');
    expect(await efectivoDevueltoEnCaja(), -200, reason: 'el reembolso sí salió de la caja');

    final devolucion = (await db.query('Devoluciones')).single;
    expect(devolucion['reintegro_inventario'], 0);
  });

  test('la merma no registra movimiento de inventario (la existencia no cambió)', () async {
    final venta = await crearVenta();

    await controller.devolverParcial(
      idVenta: venta.idVenta,
      motivo: 'Caducada',
      items: [
        {'id_producto': venta.idProducto, 'cantidad': 1},
      ],
      reintegrarInventario: false,
    );

    final movimientos = await db.query(
      'Movimiento_Inventario',
      where: 'tipo_movimiento = ?',
      whereArgs: ['DevolucionVenta'],
    );
    expect(movimientos, isEmpty);
  });

  test('la cancelación total también admite merma', () async {
    final venta = await crearVenta();

    await controller.cancelarVenta(
      idVenta: venta.idVenta,
      motivo: 'Se mojó todo el pedido',
      reintegrarInventario: false,
    );

    expect(await stockDe(venta.idProducto), 7);

    final ventaActualizada =
        (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [venta.idVenta])).single;
    expect(ventaActualizada['estado'], 'Cancelada');

    final auditoria = (await db.query('Auditorias', where: 'accion = ?', whereArgs: ['CANCEL'])).single;
    expect(auditoria['descripcion'].toString(), contains('merma'));
  });

  test('el comprobante sabe si la mercancía se dio de baja', () async {
    final venta = await crearVenta();

    final idDevolucion = await controller.devolverParcial(
      idVenta: venta.idVenta,
      motivo: 'Defecto de fábrica',
      items: [
        {'id_producto': venta.idProducto, 'cantidad': 1},
      ],
      reintegrarInventario: false,
    );

    final comprobante = await controller.obtenerComprobante(idDevolucion);
    expect(comprobante.reintegroInventario, isFalse);
  });
}
