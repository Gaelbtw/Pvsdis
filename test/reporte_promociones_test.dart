// Pruebas de ReporteController para promociones: reconstruir el desglose de
// una venta para reimprimir su ticket (sin volver a ejecutar el motor) y el
// resumen agregado de ahorro por promoción en un rango de fechas.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/promociones_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
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
  late ReporteController reporteController;
  late PromocionesController promoController;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reporte_promociones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventasController = VentasController();
    reporteController = ReporteController();
    promoController = PromocionesController();

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

  test('obtenerPromocionesVenta reconstruye el snapshot para reimprimir el ticket', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);
    await promoController.crear(Promocion(
      nombre: '15% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 15,
      productosIds: [idProducto],
    ));

    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 85.0},
      ],
    );

    final promociones = await reporteController.obtenerPromocionesVenta(idVenta);
    expect(promociones, hasLength(1));
    expect(promociones.first['nombre_snapshot'], '15% promo');
    expect(promociones.first['ahorro_total'], 15.0);
  });

  test('ingresos totales del reporte de ventas ya vienen netos de promoción', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);
    await promoController.crear(Promocion(
      nombre: '10% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto],
    ));

    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 90.0},
      ],
    );

    final desde = DateTime.now().subtract(const Duration(days: 1));
    final hasta = DateTime.now().add(const Duration(days: 1));

    final resumen = await reporteController.obtenerReporteVentas(
      desde: desde,
      hasta: hasta,
      filtrarPorUsuario: false,
    );

    expect(resumen.totalVentas, 1);
    expect(resumen.ingresosTotales, 90.0);
  });

  test('obtenerReportePromocionesResumen agrega el ahorro por promoción', () async {
    final idA = await crearProducto(precio: 100, stock: 10);
    final idB = await crearProducto(precio: 50, stock: 10);

    await promoController.crear(Promocion(
      nombre: 'Promo A',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idA],
    ));
    await promoController.crear(Promocion(
      nombre: 'Promo B',
      tipo: TipoPromocion.montoFijoProducto,
      valor: 5,
      productosIds: [idB],
    ));

    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idA, 'nombre': 'A', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 90.0},
      ],
    );
    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idB, 'nombre': 'B', 'precio': 50.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 90.0},
      ],
    );

    final desde = DateTime.now().subtract(const Duration(days: 1));
    final hasta = DateTime.now().add(const Duration(days: 1));

    final resumen = await reporteController.obtenerReportePromocionesResumen(desde: desde, hasta: hasta);

    // Promo A: 10% de 100 = 10. Promo B: 5 x 2 = 10. Total 20.
    expect(resumen.ahorroTotal, 20.0);
    expect(resumen.porPromocion, hasLength(2));

    final nombres = resumen.porPromocion.map((p) => p['nombre']).toSet();
    expect(nombres, {'Promo A', 'Promo B'});
  });
}
