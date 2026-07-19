// Integración Apartados + Ventas: el stock reservado por un apartado no debe
// poder venderse por la vía normal, y liberar/confirmar la reserva debe
// mantener disponible = física - reservada consistente en todo momento.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/apartados_controller.dart';
import 'package:pvapp/controllers/producto_controller.dart';
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
  late ApartadosController apartadosController;
  late VentasController ventasController;
  late ProductoController productoController;
  late int idCliente;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_apartados_inventario_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    apartadosController = ApartadosController();
    ventasController = VentasController();
    productoController = ProductoController();

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

  test('obtenerConStock/obtenerDisponibleMap reflejan física - reservada', () async {
    final idProducto = await crearProducto(precio: 20, stock: 10);

    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 4},
      ],
    );

    final conStock = await productoController.obtenerConStock();
    final fila = conStock.firstWhere((p) => p['id_producto'] == idProducto);
    expect(fila['cantidad'], 10);
    expect(fila['cantidad_reservada'], 4);
    expect(fila['disponible'], 6);

    final disponibleMap = await productoController.obtenerDisponibleMap();
    expect(disponibleMap[idProducto], 6);
  });

  test('una venta normal no puede vender unidades ya apartadas', () async {
    final idProducto = await crearProducto(precio: 20, stock: 5);

    // Aparta 4 de las 5 unidades; solo queda 1 disponible.
    await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 4},
      ],
    );

    // Intentar vender 2 (más de la 1 disponible) debe fallar.
    await expectLater(
      ventasController.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 2},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 40.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    // Vender exactamente la unidad disponible sí debe funcionar.
    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 1},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 20.0},
      ],
    );

    final inventario = (await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto])).first;
    expect(inventario['cantidad'], 4); // 5 físicas - 1 vendida
    expect(inventario['cantidad_reservada'], 4); // la reserva del apartado sigue intacta
  });

  test('al cancelar el apartado, el stock vuelve a estar disponible para la venta', () async {
    final idProducto = await crearProducto(precio: 20, stock: 3);

    final idApartado = await apartadosController.crear(
      idCliente: idCliente,
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 3},
      ],
    );

    // Con las 3 unidades apartadas, no se puede vender ninguna.
    await expectLater(
      ventasController.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    await apartadosController.cancelar(idApartado: idApartado, motivo: 'Cliente canceló');

    // Ahora sí se puede vender.
    await ventasController.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 20.0, 'cantidad': 3},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 60.0},
      ],
    );

    final inventario = (await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto])).first;
    expect(inventario['cantidad'], 0);
    expect(inventario['cantidad_reservada'], 0);
  });
}
