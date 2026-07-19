// Integración Apartados + Reportes: obtenerPagosVenta/obtenerPromocionesVenta
// deben seguir el enlace `Ventas.id_apartado` cuando la venta vino de
// liquidar un apartado (sin filas propias en Venta_Pagos/Venta_Promociones),
// obtenerTotalesPorMetodoPago debe incluir los anticipos, y
// obtenerReporteApartados debe reflejar el estado/saldo actual.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/apartados_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
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
  late ReporteController reporteController;
  late int idCliente;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_apartados_reporte_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    apartadosController = ApartadosController();
    reporteController = ReporteController();

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

  test('obtenerPagosVenta de una venta liquidada desde un apartado reconstruye el historial completo', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    final idApartado = await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      montoAnticipo: 40,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 40.0},
      ],
    );

    await apartadosController.registrarAbono(
      idApartado: idApartado,
      montoAbono: 60,
      pagos: const [
        {'metodo_pago': 'Tarjeta', 'monto': 60.0},
      ],
    );

    final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
    final idVenta = apartado['id_venta'] as int;

    final pagos = await reporteController.obtenerPagosVenta(idVenta);
    expect(pagos, hasLength(2));
    final totalPagado = pagos.fold<double>(0, (s, p) => s + (p['monto'] as num).toDouble());
    expect(totalPagado, 100.0);
  });

  test('obtenerPromocionesVenta sigue el enlace id_apartado cuando la venta vino de liquidar', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    final idPromocion = await db.insert('Promociones', {
      'nombre': '10% promo',
      'tipo': 'PORCENTAJE_PRODUCTO',
      'activo': 1,
      'prioridad': 0,
      'combinable': 0,
      'valor': 10.0,
      'fecha_creacion': DateTime.now().toIso8601String(),
    });
    await db.insert('Promocion_Productos', {
      'id_promocion': idPromocion,
      'id_producto': idProducto,
    });

    final idApartado = await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      montoAnticipo: 90,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 90.0},
      ],
    );

    final apartado = (await db.query('Apartados', where: 'id_apartado = ?', whereArgs: [idApartado])).first;
    expect(apartado['estado'], 'Liquidado'); // 90 de 90 (100 - 10% promo) liquida de inmediato
    final idVenta = apartado['id_venta'] as int;

    final promos = await reporteController.obtenerPromocionesVenta(idVenta);
    expect(promos, hasLength(1));
    expect(promos.first['nombre_snapshot'], '10% promo');
    expect(promos.first['ahorro_total'], 10.0);

    // Sin filas propias en Venta_Promociones (vive en Apartado_Promociones).
    final ventaPromosDirectas = await db.query('Venta_Promociones', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaPromosDirectas, isEmpty);
  });

  test('obtenerTotalesPorMetodoPago incluye los anticipos de apartados', () async {
    final idProducto = await crearProducto(precio: 200, stock: 10);

    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 200.0, 'cantidad': 1},
      ],
      montoAnticipo: 50,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
      ],
    );

    final desde = DateTime.now().subtract(const Duration(days: 1));
    final hasta = DateTime.now().add(const Duration(days: 1));

    final totales = await reporteController.obtenerTotalesPorMetodoPago(
      desde: desde,
      hasta: hasta,
      filtrarPorUsuario: false,
    );

    expect(totales['Efectivo'], 50.0);
  });

  test('obtenerReporteApartados refleja conteos por estado y saldo pendiente actual', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    // Uno pendiente sin anticipo.
    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
    );

    // Uno que se liquida de inmediato.
    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      montoAnticipo: 100,
      pagosAnticipo: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
    );

    final desde = DateTime.now().subtract(const Duration(days: 1));
    final hasta = DateTime.now().add(const Duration(days: 1));

    final reporte = await reporteController.obtenerReporteApartados(desde: desde, hasta: hasta);

    expect(reporte.totalApartados, 2);
    expect(reporte.pendientes, 1);
    expect(reporte.liquidados, 1);
    expect(reporte.montoReservado, 100.0); // solo el pendiente sigue "reservando" dinero
    expect(reporte.saldoPendienteTotal, 100.0);
  });
}
