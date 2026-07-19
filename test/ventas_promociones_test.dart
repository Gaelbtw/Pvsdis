// Pruebas de integración: VentasController.insertarVentaCompleta evaluando
// promociones automáticas server-side, guardando el snapshot
// (Venta_Promociones / Venta_Promociones_Detalle), interactuando con
// descuentos manuales y pagos mixtos, con auditoría y con rollback.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/promociones_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/promocion_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late VentasController controller;
  late PromocionesController promoController;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_ventas_promociones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = VentasController();
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

  Future<int> crearProducto({double precio = 10, int stock = 100, String nombre = 'Producto de prueba'}) async {
    final id = await db.insert('Producto', {
      'nombre': nombre,
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

  Future<List<Map<String, dynamic>>> detalleGuardado(int idVenta) async {
    return db.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
  }

  Future<List<Map<String, dynamic>>> promocionesGuardadas(int idVenta) async {
    return db.query('Venta_Promociones', where: 'id_venta = ?', whereArgs: [idVenta]);
  }

  test('aplica una promoción de porcentaje y guarda el snapshot completo', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    await promoController.crear(Promocion(
      nombre: '10% en producto',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto],
    ));

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 180.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    // 2 x 100 = 200; 10% = 20 de ahorro por promoción -> total 180
    expect(venta['subtotal'], 200.0);
    expect(venta['total'], 180.0);

    final detalle = (await detalleGuardado(idVenta)).first;
    expect(detalle['precio'], 100.0); // precio original intacto
    expect(detalle['precio_neto'], 90.0); // (200-20)/2

    final promos = await promocionesGuardadas(idVenta);
    expect(promos, hasLength(1));
    expect(promos.first['nombre_snapshot'], '10% en producto');
    expect(promos.first['tipo_snapshot'], 'PORCENTAJE_PRODUCTO');
    expect(promos.first['ahorro_total'], 20.0);

    final detallePromo = await db.query(
      'Venta_Promociones_Detalle',
      where: 'id_venta_promocion = ?',
      whereArgs: [promos.first['id_venta_promocion']],
    );
    expect(detallePromo, hasLength(1));
    expect(detallePromo.first['id_detalleV'], detalle['id_detalleV']);
    expect(detallePromo.first['cantidad_afectada'], 2);
    expect(detallePromo.first['ahorro'], 20.0);

    final auditoriaPromocion = await db.query('Auditorias', where: "tabla = 'Ventas' AND accion = 'PROMOCION'");
    expect(auditoriaPromocion, hasLength(1));
  });

  test('la promoción reduce la base antes del descuento manual de línea', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    await promoController.crear(Promocion(
      nombre: '20% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 20,
      productosIds: [idProducto],
    ));

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': 100.0,
          'cantidad': 1,
          'descuento_tipo': TipoDescuento.porcentaje,
          'descuento_valor': 10.0,
        },
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 72.0},
      ],
    );

    // Promo 20% de 100 = 20 -> base 80; descuento manual 10% de 80 = 8 -> total 72.
    final venta = await ventaGuardada(idVenta);
    expect(venta['total'], 72.0);
    expect(venta['descuento_total'], 8.0); // solo el manual: la promo no cuenta aquí

    final detalle = (await detalleGuardado(idVenta)).first;
    expect(detalle['descuento_monto'], 8.0);
    expect(detalle['precio_neto'], 72.0);
  });

  test('funciona con pagos mixtos', () async {
    final idProducto = await crearProducto(precio: 50, stock: 20);
    await promoController.crear(Promocion(
      nombre: 'Fijo promo',
      tipo: TipoPromocion.montoFijoProducto,
      valor: 5,
      productosIds: [idProducto],
    ));

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 50.0},
        {'metodo_pago': 'Tarjeta', 'monto': 40.0},
      ],
    );

    // subtotal 100, promo 5x2=10 -> total 90; pagado 90 en dos métodos.
    final venta = await ventaGuardada(idVenta);
    expect(venta['total'], 90.0);
    expect(venta['metodo_pago'], 'Mixto');

    final pagos = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(pagos, hasLength(2));
  });

  test('una promoción inactiva no se aplica', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    final id = await promoController.crear(Promocion(
      nombre: 'Inactiva',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 50,
      productosIds: [idProducto],
    ));
    await promoController.desactivar(id);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['total'], 100.0);
    expect(await promocionesGuardadas(idVenta), isEmpty);
  });

  test('una promoción fuera de vigencia no se aplica', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    await promoController.crear(Promocion(
      nombre: 'Vencida',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 50,
      productosIds: [idProducto],
      fechaInicio: DateTime.now().subtract(const Duration(days: 30)),
      fechaFin: DateTime.now().subtract(const Duration(days: 1)),
    ));

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 100.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['total'], 100.0);
  });

  test('rollback: sin stock suficiente no persiste nada, ni siquiera el snapshot de promoción', () async {
    final idProducto1 = await crearProducto(precio: 10, stock: 100, nombre: 'A');
    final idProducto2 = await crearProducto(precio: 10, stock: 1, nombre: 'B');

    await promoController.crear(Promocion(
      nombre: 'Promo A',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto1],
    ));

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto1, 'nombre': 'A', 'precio': 10.0, 'cantidad': 2},
          {'id_producto': idProducto2, 'nombre': 'B', 'precio': 10.0, 'cantidad': 5}, // stock insuficiente
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 68.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await db.query('Ventas'), isEmpty);
    expect(await db.query('Detalle_Venta'), isEmpty);
    expect(await db.query('Venta_Promociones'), isEmpty);
    expect(await db.query('Venta_Promociones_Detalle'), isEmpty);

    final stock1 = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto1]);
    expect(stock1.first['cantidad'], 100); // no se descontó nada
  });

  test('combo se aplica y guarda el prorrateo del ahorro entre las líneas', () async {
    final idBurger = await crearProducto(precio: 60, stock: 20, nombre: 'Burger');
    final idPapas = await crearProducto(precio: 30, stock: 20, nombre: 'Papas');

    await promoController.crear(Promocion(
      nombre: 'Combo',
      tipo: TipoPromocion.combo,
      precioCombo: 80,
      comboItems: [
        ComboItem(idProducto: idBurger, cantidad: 1),
        ComboItem(idProducto: idPapas, cantidad: 1),
      ],
    ));

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idBurger, 'nombre': 'Burger', 'precio': 60.0, 'cantidad': 1},
        {'id_producto': idPapas, 'nombre': 'Papas', 'precio': 30.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 80.0},
      ],
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['total'], 80.0);

    final promos = await promocionesGuardadas(idVenta);
    expect(promos.first['ahorro_total'], 10.0);

    final detalleLineas = await detalleGuardado(idVenta);
    final detallePromo = await db.query(
      'Venta_Promociones_Detalle',
      where: 'id_venta_promocion = ?',
      whereArgs: [promos.first['id_venta_promocion']],
    );
    expect(detallePromo, hasLength(2));
    expect(detalleLineas, hasLength(2));
  });
}
