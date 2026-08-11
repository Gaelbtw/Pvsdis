// Pruebas de ReporteController.obtenerReporteUtilidad: el cálculo de
// ingreso - costo sobre el `costo_unitario` congelado en cada línea de venta
// (migración v22).
//
// Lo que de verdad se está protegiendo aquí no es la aritmética simple, sino
// las cuatro decisiones que hacen que el número sea honesto:
//
//   1. el costo es el del MOMENTO de la venta, no el actual del producto;
//   2. una devolución quita ingreso Y costo, no solo ingreso;
//   3. las ventas canceladas no cuentan;
//   4. las líneas sin costo (anteriores a la v22) se excluyen de los montos
//      pero se reportan, para que la UI pueda avisar de la cobertura parcial.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
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
  late VentasController ventasController;
  late ReporteController reporteController;

  final desde = DateTime.now().subtract(const Duration(days: 1));
  final hasta = DateTime.now().add(const Duration(days: 1));

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_reporte_utilidad_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    ventasController = VentasController();
    reporteController = ReporteController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    SessionManager.setUser(id: 1, nombre: 'Sistema', rol: 'Admin');

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

  Future<int> crearProducto({
    String nombre = 'Producto de prueba',
    double precio = 100,
    double? precioCompra = 60,
    int stock = 100,
  }) async {
    final id = await db.insert('Producto', {
      'nombre': nombre,
      'descripcion': '',
      'precio': precio,
      'precio_compra': precioCompra,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': stock});
    return id;
  }

  Future<int> vender(int idProducto, {required double precio, int cantidad = 1}) {
    return ventasController.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': precio,
          'cantidad': cantidad,
        },
      ],
      pagos: [
        {'metodo_pago': 'Efectivo', 'monto': precio * cantidad},
      ],
    );
  }

  Future<ReporteUtilidadResumen> utilidad() {
    return reporteController.obtenerReporteUtilidad(
      desde: desde,
      hasta: hasta,
      filtrarPorUsuario: false,
    );
  }

  test('calcula utilidad y margen a partir del costo congelado', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);
    await vender(idProducto, precio: 100, cantidad: 2);

    final r = await utilidad();

    expect(r.ingresos, 200);
    expect(r.costos, 120);
    expect(r.utilidad, 80);
    expect(r.margenPorcentaje, 40);
    expect(r.coberturaParcial, isFalse);
  });

  test('usa el costo del momento de la venta, no el costo actual del producto', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);
    await vender(idProducto, precio: 100);

    // El proveedor sube el precio: el costo del catálogo cambia DESPUÉS de
    // que la venta ya ocurrió. La utilidad histórica no debe moverse -- este
    // es exactamente el motivo por el que existe `costo_unitario`.
    await db.update('Producto', {'precio_compra': 95.0},
        where: 'id_producto = ?', whereArgs: [idProducto]);

    final r = await utilidad();

    expect(r.costos, 60, reason: 'debe usar el costo congelado (60), no el nuevo (95)');
    expect(r.utilidad, 40);
  });

  test('una devolución descuenta ingreso Y costo de las unidades devueltas', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);
    final idVenta = await vender(idProducto, precio: 100, cantidad: 3);

    await DevolucionesController().devolverParcial(
      idVenta: idVenta,
      motivo: 'Prueba',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    final r = await utilidad();

    // Quedan 2 unidades netas: 200 de ingreso, 120 de costo.
    expect(r.ingresos, 200);
    expect(r.costos, 120);
    expect(r.utilidad, 80);
    // Si solo se restara el ingreso, el costo seguiría en 180 y la utilidad
    // caería a 20: un margen inventado por un error de cálculo.
    expect(r.devoluciones, 100);
  });

  test('las ventas canceladas no entran en el cálculo', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);
    final idVenta = await vender(idProducto, precio: 100);
    await db.update('Ventas', {'estado': 'Cancelada'},
        where: 'id_venta = ?', whereArgs: [idVenta]);

    final r = await utilidad();

    expect(r.ingresos, 0);
    expect(r.costos, 0);
    expect(r.porProducto, isEmpty);
  });

  test('las líneas sin costo se excluyen de los montos pero se reportan', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);
    await vender(idProducto, precio: 100);
    final idVentaVieja = await vender(idProducto, precio: 100);

    // Simula una línea anterior a la v22: vendida, pero sin costo guardado.
    await db.update('Detalle_Venta', {'costo_unitario': null},
        where: 'id_venta = ?', whereArgs: [idVentaVieja]);

    final r = await utilidad();

    // Solo la línea con costo aporta dinero.
    expect(r.ingresos, 100);
    expect(r.costos, 60);

    // Pero la cobertura refleja que hay una línea fuera del cálculo, para
    // que la vista pueda advertirlo en vez de presentar un total incompleto
    // como si fuera definitivo.
    expect(r.lineasConCosto, 1);
    expect(r.lineasSinCosto, 1);
    expect(r.coberturaParcial, isTrue);
    expect(r.coberturaPorcentaje, 50);
  });

  test('un producto sin precio_compra deja la línea sin costo, no en cero', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: null);
    await vender(idProducto, precio: 100);

    final r = await utilidad();

    // Un costo NULL no debe leerse como "costo 0" (margen del 100%).
    expect(r.lineasSinCosto, 1);
    expect(r.ingresos, 0);
    expect(r.utilidad, 0);
  });

  test('el desglose por producto ordena de mayor a menor utilidad', () async {
    final flojo = await crearProducto(nombre: 'Flojo', precio: 100, precioCompra: 90);
    final bueno = await crearProducto(nombre: 'Bueno', precio: 100, precioCompra: 20);

    await vender(flojo, precio: 100);
    await vender(bueno, precio: 100);

    final r = await utilidad();

    expect(r.porProducto.first['nombre'], 'Bueno');
    expect(r.porProducto.first['utilidad'], 80); // 100 - 20
    expect(r.porProducto.last['nombre'], 'Flojo');
    expect(r.porProducto.last['utilidad'], 10); // 100 - 90
    expect(r.ingresos, 200);
    expect(r.costos, 110);
    expect(r.utilidad, 90);
  });

  test('el margen es 0 y no NaN cuando no hubo ingresos', () async {
    final r = await utilidad();

    expect(r.ingresos, 0);
    expect(r.margenPorcentaje, 0);
    expect(r.coberturaPorcentaje, 0);
    expect(r.coberturaParcial, isFalse);
  });

  test('descuentos: el ingreso usa el precio neto, no el de lista', () async {
    final idProducto = await crearProducto(precio: 100, precioCompra: 60);

    await ventasController.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': 100.0,
          'cantidad': 1,
          // El enum, no su nombre: `calcularVenta` hace
          // `item['descuento_tipo'] as TipoDescuento?`.
          'descuento_tipo': TipoDescuento.porcentaje,
          'descuento_valor': 10.0,
        },
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 90.0},
      ],
    );

    final r = await utilidad();

    // 90 de ingreso (no 100) contra 60 de costo. Tomar el precio de lista
    // haría parecer el margen mejor de lo que fue.
    expect(r.ingresos, 90);
    expect(r.costos, 60);
    expect(r.utilidad, 30);
  });

  // Guarda contra regresiones del propio controlador: el encabezado se suma
  // a partir del desglose, así que nunca deberían discrepar.
  test('los totales coinciden con la suma del desglose por producto', () async {
    final a = await crearProducto(nombre: 'A', precio: 50, precioCompra: 30);
    final b = await crearProducto(nombre: 'B', precio: 80, precioCompra: 25);

    await vender(a, precio: 50, cantidad: 2);
    await vender(b, precio: 80, cantidad: 3);

    final r = await utilidad();

    final sumaIngresos = r.porProducto.fold<double>(
        0, (s, f) => s + ((f['ingresos'] as num?)?.toDouble() ?? 0));
    final sumaCostos = r.porProducto.fold<double>(
        0, (s, f) => s + ((f['costos'] as num?)?.toDouble() ?? 0));

    expect(r.ingresos, sumaIngresos);
    expect(r.costos, sumaCostos);
  });
}
