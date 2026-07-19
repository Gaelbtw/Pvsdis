// Pruebas de ApartadosController: crear (sin/con anticipo, anticipo total),
// abonos parciales, liquidar, cancelar y vencimiento automático.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/apartados_controller.dart';
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
  late ApartadosController controller;
  late int idCliente;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_apartados_controller_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = ApartadosController();

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
    idCliente = await db.insert('Clientes', {'nombre': 'Cliente de prueba'});
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

  Future<Map<String, dynamic>> inventarioDe(int idProducto) async {
    final rows = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    return rows.first;
  }

  group('crear', () {
    test('sin anticipo: queda Pendiente y reserva stock sin tocar la existencia física', () async {
      final idProducto = await crearProducto(precio: 50, stock: 20);

      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 3},
        ],
      );

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Pendiente');
      expect(apartado['total'], 150.0);

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad'], 20); // física intacta
      expect(inventario['cantidad_reservada'], 3);

      expect(await controller.obtenerSaldoPendiente(idApartado), 150.0);

      final auditoria = await db.query('Auditorias', where: "tabla = 'Apartados' AND accion = 'CREATE'");
      expect(auditoria, hasLength(1));
    });

    test('con anticipo parcial: registra el primer abono y reduce el saldo', () async {
      final idProducto = await crearProducto(precio: 50, stock: 20);

      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
        ],
        montoAnticipo: 40,
        pagosAnticipo: const [
          {'metodo_pago': 'Efectivo', 'monto': 40.0},
        ],
      );

      expect(await controller.obtenerSaldoPendiente(idApartado), 60.0);

      final abonos = await db.query('Apartado_Abonos', where: 'id_apartado = ?', whereArgs: [idApartado]);
      expect(abonos, hasLength(1));
      expect(abonos.first['tipo'], 'Anticipo');
      expect(abonos.first['monto'], 40.0);
      expect(abonos.first['id_caja'], 1);

      final pagos = await db.query('Apartado_Abono_Pagos', where: 'id_abono = ?', whereArgs: [abonos.first['id_abono']]);
      expect(pagos, hasLength(1));
      expect(pagos.first['metodo_pago'], 'Efectivo');
    });

    test('con anticipo que cubre el total: liquida de inmediato en la misma operación', () async {
      final idProducto = await crearProducto(precio: 50, stock: 20);

      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
        ],
        montoAnticipo: 100,
        pagosAnticipo: const [
          {'metodo_pago': 'Efectivo', 'monto': 100.0},
        ],
      );

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Liquidado');
      expect(apartado['id_venta'], isNotNull);

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad'], 18); // física ya consumida
      expect(inventario['cantidad_reservada'], 0); // reserva liberada al confirmarse

      final venta = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [apartado['id_venta']])).first;
      expect(venta['total'], 100.0);
      expect(venta['id_apartado'], idApartado);

      // La venta de liquidación no duplica pagos/promociones propios.
      final ventaPagos = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [apartado['id_venta']]);
      expect(ventaPagos, isEmpty);
    });

    test('rechaza anticipo mayor al total', () async {
      final idProducto = await crearProducto(precio: 50, stock: 20);

      expect(
        () => controller.crear(
          idCliente: idCliente,
          carrito: [
            {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 1},
          ],
          montoAnticipo: 100,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rollback: stock insuficiente no persiste nada ni reserva nada', () async {
      final idProducto = await crearProducto(precio: 50, stock: 2);

      await expectLater(
        controller.crear(
          idCliente: idCliente,
          carrito: [
            {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 5},
          ],
        ),
        throwsA(isA<Exception>()),
      );

      expect(await db.query('Apartados'), isEmpty);
      expect(await db.query('Detalle_Apartado'), isEmpty);

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad_reservada'], 0);
    });
  });

  group('registrarAbono / liquidar', () {
    test('varios abonos parciales hasta liquidar automáticamente en el último', () async {
      final idProducto = await crearProducto(precio: 100, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
        ],
      );

      await controller.registrarAbono(
        idApartado: idApartado,
        montoAbono: 30,
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 30.0},
        ],
      );
      expect(await controller.obtenerSaldoPendiente(idApartado), 70.0);

      await controller.registrarAbono(
        idApartado: idApartado,
        montoAbono: 70,
        pagos: const [
          {'metodo_pago': 'Tarjeta', 'monto': 70.0},
        ],
      );

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Liquidado');

      final abonos = await db.query('Apartado_Abonos', where: 'id_apartado = ?', whereArgs: [idApartado], orderBy: 'id_abono');
      expect(abonos, hasLength(2));
      expect(abonos.last['tipo'], 'Liquidacion');

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad'], 9);
      expect(inventario['cantidad_reservada'], 0);
    });

    test('rechaza un abono mayor al saldo pendiente', () async {
      final idProducto = await crearProducto(precio: 100, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
        ],
      );

      expect(
        () => controller.registrarAbono(
          idApartado: idApartado,
          montoAbono: 150,
          pagos: const [
            {'metodo_pago': 'Efectivo', 'monto': 150.0},
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('liquidar paga exactamente el saldo pendiente sin necesidad de calcularlo manualmente', () async {
      final idProducto = await crearProducto(precio: 100, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
        ],
        montoAnticipo: 20,
        pagosAnticipo: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      );

      await controller.liquidar(
        idApartado: idApartado,
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 80.0},
        ],
      );

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Liquidado');
      expect(await controller.obtenerSaldoPendiente(idApartado), 0.0);
    });
  });

  group('cancelar', () {
    test('libera la reserva de stock sin generar ningún movimiento de caja', () async {
      final idProducto = await crearProducto(precio: 50, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 3},
        ],
        montoAnticipo: 30,
        pagosAnticipo: const [
          {'metodo_pago': 'Efectivo', 'monto': 30.0},
        ],
      );

      final devolucionesAntes = await db.query('Devoluciones');

      await controller.cancelar(idApartado: idApartado, motivo: 'El cliente ya no lo quiere');

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Cancelado');

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad'], 10); // física intacta
      expect(inventario['cantidad_reservada'], 0); // reserva liberada

      // Sin movimiento de caja/devolución automático (decisión confirmada).
      final devolucionesDespues = await db.query('Devoluciones');
      expect(devolucionesDespues.length, devolucionesAntes.length);

      final auditoria = await db.query('Auditorias', where: "tabla = 'Apartados' AND accion = 'CANCEL'");
      expect(auditoria, hasLength(1));
    });

    test('no permite cancelar un apartado ya liquidado', () async {
      final idProducto = await crearProducto(precio: 50, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 1},
        ],
        montoAnticipo: 50,
        pagosAnticipo: const [
          {'metodo_pago': 'Efectivo', 'monto': 50.0},
        ],
      );

      expect(
        () => controller.cancelar(idApartado: idApartado, motivo: 'Intento tardío'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('vencido', () {
    test('libera la reserva automáticamente al pasar la fecha límite y bloquea nuevos abonos', () async {
      final idProducto = await crearProducto(precio: 50, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
        ],
        fechaLimite: DateTime.now().subtract(const Duration(days: 1)),
      );

      // obtenerTodos corre la liberación perezosa antes de listar.
      final lista = await controller.obtenerTodos();
      final apartado = lista.firstWhere((a) => a['id_apartado'] == idApartado);
      expect(apartado['estado'], 'Vencido');

      final inventario = await inventarioDe(idProducto);
      expect(inventario['cantidad_reservada'], 0);

      expect(
        () => controller.registrarAbono(
          idApartado: idApartado,
          montoAbono: 50,
          pagos: const [
            {'metodo_pago': 'Efectivo', 'monto': 50.0},
          ],
        ),
        throwsA(isA<Exception>()),
      );

      final auditoria = await db.query('Auditorias', where: "tabla = 'Apartados' AND accion = 'VENCIDO'");
      expect(auditoria, hasLength(1));
    });

    test('un apartado vencido sí se puede cancelar', () async {
      final idProducto = await crearProducto(precio: 50, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 1},
        ],
        fechaLimite: DateTime.now().subtract(const Duration(days: 1)),
      );

      await controller.cancelar(idApartado: idApartado, motivo: 'Vencido, se cancela formalmente');

      final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
      expect(apartado['estado'], 'Cancelado');
    });

    test('un apartado sin fecha límite nunca vence', () async {
      final idProducto = await crearProducto(precio: 50, stock: 10);
      final idApartado = await controller.crear(
        idCliente: idCliente,
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 1},
        ],
      );

      final lista = await controller.obtenerTodos();
      final apartado = lista.firstWhere((a) => a['id_apartado'] == idApartado);
      expect(apartado['estado'], 'Pendiente');
    });
  });
}
