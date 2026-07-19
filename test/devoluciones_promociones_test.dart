// Pruebas de integración Ventas + Devoluciones cuando la venta original tuvo
// promociones automáticas aplicadas: la devolución debe usar el
// `precio_neto` histórico (ya con la promoción incluida) sin volver a
// ejecutar el motor, y modificar/eliminar la promoción después no debe
// alterar el importe devuelto ni el total ya guardado de la venta.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
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
  late DevolucionesController devolucionesController;
  late PromocionesController promoController;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_devoluciones_promociones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventasController = VentasController();
    devolucionesController = DevolucionesController();
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

  test('la devolución usa el precio neto (ya con promoción) sin re-evaluar el motor', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    await promoController.crear(Promocion(
      nombre: '20% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 20,
      productosIds: [idProducto],
    ));

    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 160.0},
      ],
    );

    // precio_neto por unidad = 80 (100 - 20% de promoción).
    final idDevolucion = await devolucionesController.devolverParcial(
      idVenta: idVenta,
      motivo: 'Cliente cambió de opinión',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    final devolucion = (await db.query('Devoluciones', where: 'id_devolucion = ?', whereArgs: [idDevolucion])).first;
    expect(devolucion['importe'], 80.0);

    final detalleDevolucion = await db.query('Detalle_Devolucion', where: 'id_devolucion = ?', whereArgs: [idDevolucion]);
    expect(detalleDevolucion.first['precio'], 80.0);
  });

  test('desactivar la promoción después de la venta no altera el importe de la devolución', () async {
    final idProducto = await crearProducto(precio: 100, stock: 20);
    final idPromo = await promoController.crear(Promocion(
      nombre: '30% promo',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 30,
      productosIds: [idProducto],
    ));

    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 100.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 70.0},
      ],
    );

    // Se desactiva y luego se elimina la promoción tras la venta.
    await promoController.desactivar(idPromo);
    await promoController.eliminar(idPromo);

    final idDevolucion = await devolucionesController.cancelarVenta(idVenta: idVenta, motivo: 'Cancelación total');
    final devolucion = (await db.query('Devoluciones', where: 'id_devolucion = ?', whereArgs: [idDevolucion])).first;

    // El importe sigue siendo 70 (el precio neto histórico), no 100 (precio de lista).
    expect(devolucion['importe'], 70.0);

    // El total original de la venta tampoco cambió.
    final venta = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta])).first;
    expect(venta['total'], 70.0);

    // El snapshot de la promoción en la venta sigue mostrando su nombre aunque la promoción ya no exista.
    final snapshot = await db.query('Venta_Promociones', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(snapshot.first['nombre_snapshot'], '30% promo');
    expect(snapshot.first['id_promocion'], isNull); // ON DELETE SET NULL
  });

  test('cancelar la venta restaura el stock igual que sin promociones', () async {
    final idProducto = await crearProducto(precio: 50, stock: 10);
    await promoController.crear(Promocion(
      nombre: 'Promo',
      tipo: TipoPromocion.montoFijoProducto,
      valor: 5,
      productosIds: [idProducto],
    ));

    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 50.0, 'cantidad': 3},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 135.0},
      ],
    );

    final stockTrasVenta = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stockTrasVenta.first['cantidad'], 7);

    await devolucionesController.cancelarVenta(idVenta: idVenta, motivo: 'Cancelación total');

    final stockTrasCancelacion = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stockTrasCancelacion.first['cantidad'], 10);
  });
}
