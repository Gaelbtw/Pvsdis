// Pruebas de CajaController: apertura (con auditoría), caja duplicada,
// dos usuarios con cajas independientes, resumen en vivo (pagos mixtos +
// cambio + devolución), cierre (congela el mismo resumen, calcula
// diferencia), cierre doble rechazado, e historial.
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
  late CajaController caja;
  late VentasController ventas;
  late DevolucionesController devoluciones;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_caja_controller_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    caja = CajaController();
    ventas = VentasController();
    devoluciones = DevolucionesController();

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

  group('abrirCaja', () {
    test('crea la caja Abierta con el fondo inicial y registra auditoría', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500, observaciones: 'Turno matutino');

      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect(rows.first['estado'], 'Abierta');
      expect((rows.first['fondo_inicial'] as num).toDouble(), 500.0);
      expect(rows.first['observaciones_apertura'], 'Turno matutino');
      expect(rows.first['fecha_cierre'], isNull);

      final auditorias = await db.query(
        'Auditorias',
        where: "tabla = 'Cajas' AND accion = 'APERTURA_CAJA' AND id_registro = ?",
        whereArgs: [idCaja],
      );
      expect(auditorias, hasLength(1));
    });

    test('rechaza fondo inicial negativo', () async {
      await expectLater(
        caja.abrirCaja(fondoInicial: -10),
        throwsA(isA<Exception>()),
      );
      expect(await db.query('Cajas'), isEmpty);
    });

    test('un usuario no puede abrir dos cajas', () async {
      await caja.abrirCaja(fondoInicial: 500);

      await expectLater(
        caja.abrirCaja(fondoInicial: 300),
        throwsA(isA<Exception>()),
      );

      final cajas = await db.query('Cajas');
      expect(cajas, hasLength(1));
      expect((cajas.first['fondo_inicial'] as num).toDouble(), 500.0); // la primera no se alteró
    });

    test('dos usuarios distintos sí pueden tener cada uno su propia caja abierta', () async {
      final idCajero1 = await crearUsuario('Cajero', nombre: 'Cajero1');
      final idCajero2 = await crearUsuario('Cajero', nombre: 'Cajero2');

      SessionManager.setUser(id: idCajero1, nombre: 'Cajero1', rol: 'Cajero');
      final idCaja1 = await caja.abrirCaja(fondoInicial: 200);

      SessionManager.setUser(id: idCajero2, nombre: 'Cajero2', rol: 'Cajero');
      final idCaja2 = await caja.abrirCaja(fondoInicial: 300);

      expect(idCaja1, isNot(idCaja2));
      expect(await caja.obtenerCajaAbierta(idCajero1), isNotNull);
      expect(await caja.obtenerCajaAbierta(idCajero2), isNotNull);
    });
  });

  group('obtenerCajaAbierta', () {
    test('devuelve null si el usuario no tiene ninguna caja abierta', () async {
      expect(await caja.obtenerCajaAbierta(1), isNull);
    });

    test('devuelve la caja abierta correcta', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);
      final abierta = await caja.obtenerCajaAbierta(1);
      expect(abierta?.idCaja, idCaja);
      expect(abierta?.estaAbierta, isTrue);
    });
  });

  group('calcularResumenCaja', () {
    test('rechaza una caja inexistente', () async {
      await expectLater(caja.calcularResumenCaja(999), throwsA(isA<Exception>()));
    });

    test('agrega pagos mixtos, cambio y devoluciones correctamente', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);

      // Venta 1: $850, pagada con $1000 en efectivo -> $150 de cambio.
      final idProducto1 = await crearProducto(precio: 850);
      await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto1, 'nombre': 'Producto', 'precio': 850.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 1000.0},
        ],
      );

      // Venta 2: $500, pagada exacto con tarjeta + transferencia.
      final idProducto2 = await crearProducto(precio: 500);
      final idVenta2 = await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto2, 'nombre': 'Producto', 'precio': 500.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Tarjeta', 'monto': 300.0},
          {'metodo_pago': 'Transferencia', 'monto': 200.0},
        ],
      );

      // Devuelve la venta 2 completa: $500 reembolsados en efectivo.
      await devoluciones.cancelarVenta(idVenta: idVenta2, motivo: 'Cliente canceló');

      final resumen = await caja.calcularResumenCaja(idCaja);

      expect(resumen.fondoInicial, 500.0);
      expect(resumen.ventasEfectivo, 1000.0);
      expect(resumen.ventasTarjeta, 300.0);
      expect(resumen.ventasTransferencia, 200.0);
      expect(resumen.cambioEntregado, 150.0);
      expect(resumen.devoluciones, 500.0);
      // 500 (fondo) + 1000 (efectivo) - 150 (cambio) - 500 (devuelto) = 850
      expect(resumen.efectivoEsperado, 850.0);
      expect(resumen.totalVentas, 1500.0); // 1000 + 300 + 200
    });
  });

  group('cerrarCaja', () {
    test('congela el resumen, calcula diferencia y marca Cerrada', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);

      final idProducto = await crearProducto(precio: 100);
      await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 100.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 100.0},
        ],
      );

      final resumenPrevio = await caja.calcularResumenCaja(idCaja);

      await caja.cerrarCaja(idCaja: idCaja, efectivoContado: 610); // 10 de sobrante

      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      final cerrada = rows.first;
      expect(cerrada['estado'], 'Cerrada');
      expect(cerrada['fecha_cierre'], isNotNull);
      expect((cerrada['ventas_efectivo'] as num).toDouble(), resumenPrevio.ventasEfectivo);
      expect((cerrada['efectivo_esperado'] as num).toDouble(), resumenPrevio.efectivoEsperado);
      expect((cerrada['efectivo_contado'] as num).toDouble(), 610.0);
      expect((cerrada['diferencia'] as num).toDouble(), 10.0);

      final auditorias = await db.query(
        'Auditorias',
        where: "tabla = 'Cajas' AND accion = 'CIERRE_CAJA' AND id_registro = ?",
        whereArgs: [idCaja],
      );
      expect(auditorias, hasLength(1));
    });

    test('calcula faltante cuando lo contado es menor a lo esperado', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);
      await caja.cerrarCaja(idCaja: idCaja, efectivoContado: 480);

      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect((rows.first['diferencia'] as num).toDouble(), -20.0);
    });

    test('diferencia cero cuando lo contado coincide exactamente', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);
      await caja.cerrarCaja(idCaja: idCaja, efectivoContado: 500);

      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect((rows.first['diferencia'] as num).toDouble(), 0.0);
    });

    test('rechaza cerrar una caja ya cerrada', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);
      await caja.cerrarCaja(idCaja: idCaja, efectivoContado: 500);

      await expectLater(
        caja.cerrarCaja(idCaja: idCaja, efectivoContado: 999),
        throwsA(isA<Exception>()),
      );

      // Los valores congelados en el primer cierre no se alteraron.
      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect((rows.first['efectivo_contado'] as num).toDouble(), 500.0);
    });

    test('rechaza cerrar una caja inexistente', () async {
      await expectLater(
        caja.cerrarCaja(idCaja: 999, efectivoContado: 100),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza efectivo contado negativo', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);

      await expectLater(
        caja.cerrarCaja(idCaja: idCaja, efectivoContado: -1),
        throwsA(isA<Exception>()),
      );

      final rows = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect(rows.first['estado'], 'Abierta'); // no se cerró
    });

    test('después de cerrar, el usuario puede abrir una caja nueva', () async {
      final idCaja1 = await caja.abrirCaja(fondoInicial: 500);
      await caja.cerrarCaja(idCaja: idCaja1, efectivoContado: 500);

      final idCaja2 = await caja.abrirCaja(fondoInicial: 300);
      expect(idCaja2, isNot(idCaja1));
      expect((await caja.obtenerCajaAbierta(1))?.idCaja, idCaja2);
    });
  });

  group('obtenerHistorial', () {
    test('devuelve todas las cajas ordenadas por apertura descendente, con y sin filtro', () async {
      final idCajero = await crearUsuario('Cajero', nombre: 'Cajero1');

      final idCajaAdmin = await caja.abrirCaja(fondoInicial: 500);
      await caja.cerrarCaja(idCaja: idCajaAdmin, efectivoContado: 500);

      SessionManager.setUser(id: idCajero, nombre: 'Cajero1', rol: 'Cajero');
      final idCajaCajero = await caja.abrirCaja(fondoInicial: 200);

      final todas = await caja.obtenerHistorial();
      expect(todas, hasLength(2));
      expect(todas.first.idCaja, idCajaCajero); // más reciente primero

      final soloCajero = await caja.obtenerHistorial(idUsuario: idCajero);
      expect(soloCajero, hasLength(1));
      expect(soloCajero.first.idCaja, idCajaCajero);
      expect(soloCajero.first.estaAbierta, isTrue);
    });
  });
}
