// Integración Apartados + Caja: los anticipos/abonos deben sumar al
// efectivo esperado del turno en que se cobraron (no de la venta que la
// liquidación termine generando), y liquidar en un turno distinto al de los
// abonos no debe volver a contar ese dinero en ningún turno.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/apartados_controller.dart';
import 'package:pvapp/controllers/caja_controller.dart';
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
  late ApartadosController apartadosController;
  late CajaController cajaController;
  late int idCliente;
  late int idCaja1;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_apartados_caja_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    apartadosController = ApartadosController();
    cajaController = CajaController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();

    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
    });
    idCaja1 = await db.insert('Cajas', {
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

  test('el anticipo en efectivo suma a anticiposEfectivo y a efectivoEsperado, no a ventasEfectivo', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      montoAnticipo: 40,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 40.0},
      ],
    );

    final resumen = await cajaController.calcularResumenCaja(idCaja1);
    expect(resumen.ventasEfectivo, 0.0);
    expect(resumen.anticiposEfectivo, 40.0);
    expect(resumen.totalAnticipos, 40.0);
    expect(resumen.efectivoEsperado, 540.0); // 500 fondo + 40 anticipo
  });

  test('liquidar en un turno distinto no duplica el dinero del anticipo original', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    final idApartado = await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      montoAnticipo: 30,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 30.0},
      ],
    );

    // Se cierra la primera caja (fin de turno) con el anticipo ya cobrado.
    await cajaController.cerrarCaja(idCaja: idCaja1, efectivoContado: 530.0);

    // Un turno distinto abre una nueva caja y liquida el resto días después.
    SessionManager.setUser(id: 1, nombre: 'Sistema', rol: 'Admin');
    final idCaja2 = await cajaController.abrirCaja(fondoInicial: 200);

    await apartadosController.liquidar(
      idApartado: idApartado,
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 70.0},
      ],
    );

    // La caja 1 (ya cerrada) sigue mostrando solo su propio anticipo: 30.
    final resumenCaja1 = await cajaController.calcularResumenCaja(idCaja1);
    expect(resumenCaja1.anticiposEfectivo, 30.0);
    expect(resumenCaja1.ventasEfectivo, 0.0);

    // La caja 2 muestra el abono de liquidación (70) como anticipo, y CERO
    // en ventasEfectivo (la Venta de liquidación no tiene Venta_Pagos propios).
    final resumenCaja2 = await cajaController.calcularResumenCaja(idCaja2);
    expect(resumenCaja2.anticiposEfectivo, 70.0);
    expect(resumenCaja2.ventasEfectivo, 0.0);
    expect(resumenCaja2.efectivoEsperado, 270.0); // 200 fondo + 70

    // Nada se contó dos veces: 30 (caja1) + 70 (caja2) = 100 = total del apartado.
    expect(resumenCaja1.anticiposEfectivo + resumenCaja2.anticiposEfectivo, 100.0);
  });
}
