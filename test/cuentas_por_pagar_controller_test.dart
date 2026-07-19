// Pruebas de CuentasPorPagarController: abono parcial, liquidación, pago
// mayor al saldo (rechazado), compra vencida, pago en efectivo sin caja
// abierta (rechazado) vs. con caja abierta (sí reduce el efectivo esperado
// del corte), pago electrónico (no reduce el efectivo esperado), reportes,
// y que un abono inválido no deja nada a medias (rollback).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/compras_controller.dart';
import 'package:pvapp/controllers/cuentas_por_pagar_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
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
  late CuentasPorPagarController cuentasPorPagar;
  late CajaController caja;
  late ComprasController compras;
  late ReporteController reportes;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_cxp_controller_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    cuentasPorPagar = CuentasPorPagarController();
    caja = CajaController();
    compras = ComprasController();
    reportes = ReporteController();

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

  Future<int> crearProveedor(String nombre) => db.insert('Proveedores', {'nombre': nombre});

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

  Future<int> crearCompraACredito({
    required int idUsuario,
    required int idProveedor,
    required int idProducto,
    required double total,
    DateTime? fechaVencimiento,
  }) {
    SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');
    return compras.insertarCompraCompleta(
      [
        {'id_producto': idProducto, 'cantidad': 1, 'precio_compra': total},
      ],
      total,
      idProveedor,
      formaPago: 'Credito',
      fechaVencimiento: fechaVencimiento,
    );
  }

  group('registrarAbono', () {
    test('un abono parcial reduce el saldo y deja la compra en Parcial', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 1000,
      );

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra,
        monto: 400,
        pagos: [
          {'metodo_pago': 'Transferencia', 'monto': 400}
        ],
      );

      final saldo = await cuentasPorPagar.saldoPendiente(idCompra);
      expect(saldo, 600.0);

      final cuenta = (await cuentasPorPagar.obtenerCuentas()).firstWhere((c) => c['id_compra'] == idCompra);
      expect(cuenta['estado'], 'Parcial');
    });

    test('liquidarCompra paga exactamente el saldo pendiente restante', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 1000,
      );

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra,
        monto: 400,
        pagos: [
          {'metodo_pago': 'Transferencia', 'monto': 400}
        ],
      );

      await cuentasPorPagar.liquidarCompra(
        idCompra: idCompra,
        pagos: [
          {'metodo_pago': 'Tarjeta', 'monto': 600}
        ],
      );

      final saldo = await cuentasPorPagar.saldoPendiente(idCompra);
      expect(saldo, 0.0);

      final cuenta = (await cuentasPorPagar.obtenerCuentas()).firstWhere((c) => c['id_compra'] == idCompra);
      expect(cuenta['estado'], 'Pagada');
    });

    test('rechaza un pago mayor al saldo pendiente, sin dejar nada guardado', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 500,
      );

      await expectLater(
        cuentasPorPagar.registrarAbono(
          idCompra: idCompra,
          monto: 600,
          pagos: [
            {'metodo_pago': 'Transferencia', 'monto': 600}
          ],
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'mensaje', contains('saldo pendiente')),
        ),
      );

      final abonos = await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(abonos, isEmpty);
    });

    test('rechaza cuando la suma de métodos de pago no coincide con el monto (rollback)', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 500,
      );

      await expectLater(
        cuentasPorPagar.registrarAbono(
          idCompra: idCompra,
          monto: 300,
          pagos: [
            {'metodo_pago': 'Transferencia', 'monto': 250}
          ],
        ),
        throwsA(isA<Exception>()),
      );

      final abonos = await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra]);
      expect(abonos, isEmpty, reason: 'un abono inválido no debe dejar nada guardado');
    });

    test('pago en efectivo sin caja abierta es rechazado', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 500,
      );

      await expectLater(
        cuentasPorPagar.registrarAbono(
          idCompra: idCompra,
          monto: 200,
          pagos: [
            {'metodo_pago': 'Efectivo', 'monto': 200}
          ],
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'mensaje', contains('abrir la caja')),
        ),
      );
    });

    test('pago en efectivo con caja abierta reduce el efectivo esperado del corte', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 500,
      );

      final idCaja = await caja.abrirCaja(fondoInicial: 1000);

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra,
        monto: 200,
        pagos: [
          {'metodo_pago': 'Efectivo', 'monto': 200}
        ],
      );

      final resumen = await caja.calcularResumenCaja(idCaja);
      expect(resumen.pagosProveedoresEfectivo, 200.0);
      expect(resumen.efectivoEsperado, 800.0); // 1000 fondo - 200 pago a proveedor

      final abono = (await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra])).first;
      expect(abono['id_caja'], idCaja);
    });

    test('pago electrónico (tarjeta/transferencia) no reduce el efectivo esperado', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor A');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 500,
      );

      final idCaja = await caja.abrirCaja(fondoInicial: 1000);

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra,
        monto: 200,
        pagos: [
          {'metodo_pago': 'Transferencia', 'monto': 200}
        ],
      );

      final resumen = await caja.calcularResumenCaja(idCaja);
      expect(resumen.pagosProveedoresEfectivo, 0.0);
      expect(resumen.efectivoEsperado, 1000.0);

      final abono = (await db.query('Abonos', where: 'id_compra = ?', whereArgs: [idCompra])).first;
      expect(abono['id_caja'], isNull, reason: 'un pago 100% electrónico no necesita ligarse a una caja');
    });
  });

  group('vencimientos', () {
    test('una compra a crédito con fecha límite pasada y saldo aparece como vencida', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor Vencido');
      final idProducto = await crearProducto();
      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 300,
        fechaVencimiento: DateTime.now().subtract(const Duration(days: 5)),
      );

      final vencidas = await cuentasPorPagar.obtenerCuentasVencidas();
      expect(vencidas.map((c) => c['id_compra']), contains(idCompra));

      // Al liquidarla, deja de estar vencida (ya no tiene saldo pendiente).
      await cuentasPorPagar.liquidarCompra(
        idCompra: idCompra,
        pagos: [
          {'metodo_pago': 'Transferencia', 'monto': 300}
        ],
      );
      final vencidasDespues = await cuentasPorPagar.obtenerCuentasVencidas();
      expect(vencidasDespues.map((c) => c['id_compra']), isNot(contains(idCompra)));
    });

    test('próximos vencimientos incluye compras que vencen pronto pero no las ya vencidas', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor Próximo');
      final idProducto = await crearProducto();

      final idCompraProxima = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 100,
        fechaVencimiento: DateTime.now().add(const Duration(days: 3)),
      );
      final idCompraVencida = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 100,
        fechaVencimiento: DateTime.now().subtract(const Duration(days: 3)),
      );

      final proximos = await cuentasPorPagar.obtenerProximosVencimientos(dias: 7);
      final ids = proximos.map((c) => c['id_compra']).toSet();
      expect(ids, contains(idCompraProxima));
      expect(ids, isNot(contains(idCompraVencida)));
    });
  });

  group('reportes', () {
    test('deudaTotal y deudaPorProveedor reflejan solo el saldo pendiente', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor1 = await crearProveedor('Proveedor Uno');
      final idProveedor2 = await crearProveedor('Proveedor Dos');
      final idProducto = await crearProducto();

      final idCompra1 = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor1,
        idProducto: idProducto,
        total: 1000,
      );
      await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor2,
        idProducto: idProducto,
        total: 500,
      );

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra1,
        monto: 1000,
        pagos: [
          {'metodo_pago': 'Transferencia', 'monto': 1000}
        ],
      );

      final deudaTotal = await cuentasPorPagar.deudaTotal();
      expect(deudaTotal, 500.0, reason: 'la compra 1 ya se liquidó, solo queda la del proveedor 2');

      final porProveedor = await cuentasPorPagar.deudaPorProveedor();
      expect(porProveedor, hasLength(1));
      expect(porProveedor.first['proveedor'], 'Proveedor Dos');
      expect((porProveedor.first['saldo'] as num).toDouble(), 500.0);
    });

    test('ReporteController.obtenerReporteCuentasPorPagar arma el resumen completo', () async {
      final idUsuario = await crearUsuario('Admin');
      final idProveedor = await crearProveedor('Proveedor Reporte');
      final idProducto = await crearProducto();

      final idCompra = await crearCompraACredito(
        idUsuario: idUsuario,
        idProveedor: idProveedor,
        idProducto: idProducto,
        total: 400,
      );
      final idCaja = await caja.abrirCaja(fondoInicial: 500);

      await cuentasPorPagar.registrarAbono(
        idCompra: idCompra,
        monto: 150,
        pagos: [
          {'metodo_pago': 'Efectivo', 'monto': 150}
        ],
      );

      final resumen = await reportes.obtenerReporteCuentasPorPagar(
        desde: DateTime.now().subtract(const Duration(days: 1)),
        hasta: DateTime.now().add(const Duration(days: 1)),
      );

      expect(resumen.deudaTotal, 250.0);
      expect(resumen.salidasCajaEfectivo, 150.0);
      expect(resumen.pagosRealizados, hasLength(1));
      expect(resumen.comprasPendientes, hasLength(1));

      // El fondo de caja recuerda que sí se abrió (evita "unused" warning y
      // documenta que el flujo de efectivo pasó por una caja real).
      expect(await caja.obtenerCajaAbierta(idUsuario), isNotNull);
      expect(idCaja, isNotNull);
    });
  });
}
