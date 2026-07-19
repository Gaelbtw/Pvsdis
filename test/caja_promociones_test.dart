// Confirma que el resumen de caja (efectivo esperado, ventas por método)
// sigue siendo correcto cuando las ventas de esa caja incluyen promociones
// automáticas: no hay lógica nueva en CajaController, el total ya viene neto
// de promoción desde Ventas/Venta_Pagos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/promociones_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/promocion_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late VentasController ventasController;
  late CajaController cajaController;
  late PromocionesController promoController;
  late int idCaja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_caja_promociones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventasController = VentasController();
    cajaController = CajaController();
    promoController = PromocionesController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();

    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
    });
    idCaja = await db.insert('Cajas', {
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

  test('el efectivo esperado refleja el total ya neto de promoción', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);
    await promoController.crear(Promocion(
      nombre: '25% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 25,
      productosIds: [idProducto],
    ));

    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 75.0},
      ],
    );

    final resumen = await cajaController.calcularResumenCaja(idCaja);
    // fondo 500 + ventas efectivo 75 (ya con 25% de promoción aplicado) = 575
    expect(resumen.ventasEfectivo, 75.0);
    expect(resumen.efectivoEsperado, 575.0);
    expect(resumen.totalVentas, 75.0);
  });

  test('cerrar la caja congela el resumen correcto con promociones aplicadas', () async {
    final idProducto = await crearProducto(precio: 50, stock: 10);
    await promoController.crear(Promocion(
      nombre: 'Fijo promo',
      tipo: TipoPromocion.montoFijoProducto,
      valor: 10,
      productosIds: [idProducto],
    ));

    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 80.0},
      ],
    );

    await cajaController.cerrarCaja(idCaja: idCaja, efectivoContado: 580.0);

    final cerrada = (await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja])).first;
    expect(cerrada['ventas_efectivo'], 80.0);
    expect(cerrada['efectivo_esperado'], 580.0);
    expect(cerrada['diferencia'], 0.0);
  });
}
