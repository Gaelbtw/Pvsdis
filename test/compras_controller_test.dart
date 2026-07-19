// Pruebas de ComprasController: compra de contado (con su abono inicial
// atómico), compra a crédito (sin pago inicial), rollback si el pago
// inicial falla (caja cerrada), eliminar sin abonos vs. con abonos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/compras_controller.dart';
import 'package:pvapp/controllers/cuentas_por_pagar_controller.dart';
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
  late ComprasController compras;
  late CuentasPorPagarController cuentasPorPagar;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_compras_controller_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    compras = ComprasController();
    cuentasPorPagar = CuentasPorPagarController();

    SessionManager.clear();
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
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

  Future<int> crearProveedor() => db.insert('Proveedores', {'nombre': 'Proveedor de prueba'});

  Future<void> abrirCaja(int idUsuario) => db.insert('Cajas', {
        'id_usuario': idUsuario,
        'fecha_apertura': DateTime.now().toIso8601String(),
        'fondo_inicial': 0,
        'estado': 'Abierta',
      });

  Future<int> crearProducto() async {
    final id = await db.insert('Producto', {
      'nombre': 'Producto de prueba',
      'descripcion': '',
      'precio': 20,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': 0});
    return id;
  }

  group('insertarCompraCompleta', () {
    test('compra de contado: se guarda con un abono por el total (saldo 0, Pagada)', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor();
      final idProducto = await crearProducto();
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');
      await abrirCaja(idUsuario);

      final idCompra = await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 10, 'precio_compra': 8.0},
        ],
        80.0,
        idProveedor,
        formaPago: 'Contado',
        montoInicialPagado: 80.0,
        pagosIniciales: [
          {'metodo_pago': 'Efectivo', 'monto': 80.0}
        ],
      );

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario.first['cantidad'], 10);

      final saldo = await cuentasPorPagar.saldoPendiente(idCompra);
      expect(saldo, 0.0);

      final cuentas = await cuentasPorPagar.obtenerCuentas();
      final cuenta = cuentas.firstWhere((c) => c['id_compra'] == idCompra);
      expect(cuenta['estado'], 'Pagada');
      expect(cuenta['forma_pago'], 'Contado');

      final abonos = await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(abonos, hasLength(1));
      expect((abonos.first['monto'] as num).toDouble(), 80.0);
    });

    test('compra a crédito sin pago inicial: queda 100% pendiente', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor();
      final idProducto = await crearProducto();
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final vencimiento = DateTime.now().add(const Duration(days: 15));
      final idCompra = await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 5, 'precio_compra': 100.0},
        ],
        500.0,
        idProveedor,
        formaPago: 'Credito',
        fechaVencimiento: vencimiento,
        folioFactura: 'FAC-001',
      );

      final abonos = await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(abonos, isEmpty);

      final saldo = await cuentasPorPagar.saldoPendiente(idCompra);
      expect(saldo, 500.0);

      final cuentas = await cuentasPorPagar.obtenerCuentas();
      final cuenta = cuentas.firstWhere((c) => c['id_compra'] == idCompra);
      expect(cuenta['estado'], 'Pendiente');
      expect(cuenta['folio_factura'], 'FAC-001');
    });

    test('compra a crédito con pago inicial parcial: queda Parcial', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor();
      final idProducto = await crearProducto();
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final idCompra = await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 5, 'precio_compra': 100.0},
        ],
        500.0,
        idProveedor,
        formaPago: 'Credito',
        montoInicialPagado: 200.0,
        pagosIniciales: [
          {'metodo_pago': 'Transferencia', 'monto': 200.0}
        ],
      );

      final saldo = await cuentasPorPagar.saldoPendiente(idCompra);
      expect(saldo, 300.0);

      final cuentas = await cuentasPorPagar.obtenerCuentas();
      final cuenta = cuentas.firstWhere((c) => c['id_compra'] == idCompra);
      expect(cuenta['estado'], 'Parcial');
    });

    test(
      'rollback: pago inicial en efectivo sin caja abierta no deja nada guardado (ni la compra)',
      () async {
        final idUsuario = await crearUsuario('Admin');
        final idProveedor = await crearProveedor();
        final idProducto = await crearProducto();
        SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

        await expectLater(
          compras.insertarCompraCompleta(
            [
              {'id_producto': idProducto, 'cantidad': 5, 'precio_compra': 100.0},
            ],
            500.0,
            idProveedor,
            formaPago: 'Contado',
            montoInicialPagado: 500.0,
            pagosIniciales: [
              {'metodo_pago': 'Efectivo', 'monto': 500.0}
            ],
          ),
          throwsA(isA<Exception>()),
        );

        final todasLasCompras = await db.query('Compras');
        expect(todasLasCompras, isEmpty, reason: 'la compra no debió guardarse si el pago inicial falló');

        final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
        expect(inventario.first['cantidad'], 0, reason: 'el stock tampoco debió incrementarse');
      },
    );
  });

  group('eliminarCompra', () {
    test('elimina una compra sin abonos y revierte el stock', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor();
      final idProducto = await crearProducto();
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final idCompra = await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 10, 'precio_compra': 8.0},
        ],
        80.0,
        idProveedor,
        formaPago: 'Credito',
      );

      await compras.eliminarCompra(idCompra);

      final restante = await db.query('Compras', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(restante, isEmpty);

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario.first['cantidad'], 0);
    });

    test('rechaza eliminar una compra que ya tiene abonos registrados', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor();
      final idProducto = await crearProducto();
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final idCompra = await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 10, 'precio_compra': 8.0},
        ],
        80.0,
        idProveedor,
        formaPago: 'Credito',
        montoInicialPagado: 30.0,
        pagosIniciales: [
          {'metodo_pago': 'Transferencia', 'monto': 30.0}
        ],
      );

      await expectLater(
        compras.eliminarCompra(idCompra),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensaje',
            contains('abonos registrados'),
          ),
        ),
      );

      final sigueExistiendo = await db.query('Compras', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(sigueExistiendo, hasLength(1));
    });
  });
}
