// Prueba de integración cruzada: una devolución parcial sobre una venta
// que tuvo descuento (de línea y global) debe calcular el importe a
// devolver sobre lo realmente pagado (precio_neto), no sobre el precio de
// lista original.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/models/configuracion_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late VentasController ventasController;
  late DevolucionesController devolucionesController;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_devolucion_descuento_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventasController = VentasController();
    devolucionesController = DevolucionesController();

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

  test('la devolución parcial de una venta con descuento de línea usa el precio pagado', () async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto A',
      'descripcion': '',
      'precio': 10.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 20});

    // 5 unidades a $10 con 10% de descuento de línea -> precio_neto = $9 c/u.
    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto A',
          'precio': 10.0,
          'cantidad': 5,
          'descuento_tipo': TipoDescuento.porcentaje,
          'descuento_valor': 10.0,
        },
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 45.0},
      ],
    );

    final stockTrasVenta = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stockTrasVenta.first['cantidad'], 15); // 20 - 5

    // Devuelve 2 de las 5 unidades.
    final idDevolucion = await devolucionesController.devolverParcial(
      idVenta: idVenta,
      motivo: 'Producto sobrante',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
      ],
    );

    // Debe reembolsar 2 x $9 = $18 (precio pagado), NO 2 x $10 = $20 (precio de lista).
    final comprobante = await devolucionesController.obtenerComprobante(idDevolucion);
    expect(comprobante.importe, 18.0);
    expect(comprobante.items.first['precio'], 9.0);

    final stockTrasDevolucion = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stockTrasDevolucion.first['cantidad'], 17); // 15 + 2 reintegrados
  });

  test('la devolución de una venta con descuento global reparte proporcionalmente el precio neto', () async {
    final idA = await db.insert('Producto', {
      'nombre': 'Producto A',
      'descripcion': '',
      'precio': 20.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idA, 'cantidad': 10});

    final idB = await db.insert('Producto', {
      'nombre': 'Producto B',
      'descripcion': '',
      'precio': 10.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idB, 'cantidad': 10});

    // Subtotal 20+10=30; descuento global fijo de 3 -> reparto proporcional:
    // A (20/30) -> 2, B (10/30) -> 1. precio_neto: A = 18, B = 9.
    final idVenta = await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idA, 'nombre': 'Producto A', 'precio': 20.0, 'cantidad': 1},
        {'id_producto': idB, 'nombre': 'Producto B', 'precio': 10.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 27.0},
      ],
      descuentoGlobalTipo: TipoDescuento.fijo,
      descuentoGlobalValor: 3,
    );

    final idDevolucion = await devolucionesController.cancelarVenta(
      idVenta: idVenta,
      motivo: 'Cliente canceló',
    );

    final comprobante = await devolucionesController.obtenerComprobante(idDevolucion);
    expect(comprobante.importe, 27.0); // 18 + 9, exactamente el total cobrado

    final detalle = await devolucionesController.obtenerDetalleVenta(idVenta);
    expect(detalle.estado, 'Cancelada');
  });
}
