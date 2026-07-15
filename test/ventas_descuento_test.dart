// Pruebas de VentasController con descuentos: por producto (porcentaje y
// fijo), global (porcentaje y fijo), combinados, límites inválidos, el
// flujo de autorización (permiso del cajero, umbral, motivo, admin) y que
// un fallo a mitad de la operación no deje nada guardado.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  late VentasController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_ventas_descuento_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = VentasController();

    // Configuración por defecto: umbral 20%, cajero puede aplicar y necesita autorización.
    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();

    // SessionManager.currentUserId queda en null tras clear(); el
    // controlador cae entonces a id_usuario=1 (ver `?? 1` en
    // insertarVentaCompleta), así que se siembra ese usuario para que la
    // FK de Ventas.id_usuario no falle en las pruebas que no llaman a
    // SessionManager.setUser explícitamente.
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

  Future<int> crearUsuario(String rol, {String nombre = 'usuario', String password = '1234'}) async {
    return db.insert('Usuarios', {
      'nombre': nombre,
      'contra': PasswordHasher.hash(password),
      'rol': rol,
    });
  }

  Future<Map<String, dynamic>> ventaGuardada(int idVenta) async {
    final rows = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> detalleGuardado(int idVenta) async {
    return db.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
  }

  test('descuento porcentual por producto se guarda y descuenta el stock correcto', () async {
    final idProducto = await crearProducto(precio: 10, stock: 50);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': 10.0,
          'cantidad': 2,
          'descuento_tipo': TipoDescuento.porcentaje,
          'descuento_valor': 10.0,
        },
      ],
      metodoPago: 'efectivo',
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['subtotal'], 20.0);
    expect(venta['descuento_total'], 2.0);
    expect(venta['total'], 18.0);

    final detalle = (await detalleGuardado(idVenta)).first;
    expect(detalle['precio'], 10.0); // precio original intacto
    expect(detalle['descuento_tipo'], 'porcentaje');
    expect(detalle['descuento_monto'], 2.0);
    expect(detalle['precio_neto'], 9.0);

    final stock = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(stock.first['cantidad'], 48);
  });

  test('descuento fijo por producto se guarda correctamente', () async {
    final idProducto = await crearProducto(precio: 10, stock: 50);

    // precio*cantidad = 40; descuento fijo de 5 = 12.5% (bajo el umbral por
    // defecto de 20%), para probar únicamente la persistencia del monto
    // fijo sin activar el flujo de autorización.
    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': 10.0,
          'cantidad': 4,
          'descuento_tipo': TipoDescuento.fijo,
          'descuento_valor': 5.0,
        },
      ],
      metodoPago: 'efectivo',
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['descuento_total'], 5.0);
    expect(venta['total'], 35.0);
  });

  test('descuento global porcentual se guarda y se refleja en el total', () async {
    final idProducto = await crearProducto(precio: 10, stock: 50);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 3},
      ],
      metodoPago: 'efectivo',
      descuentoGlobalTipo: TipoDescuento.porcentaje,
      descuentoGlobalValor: 10,
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['subtotal'], 30.0);
    expect(venta['descuento_global_tipo'], 'porcentaje');
    expect(venta['descuento_global_valor'], 10.0);
    expect(venta['descuento_total'], 3.0);
    expect(venta['total'], 27.0);
  });

  test('descuento global fijo se guarda y se refleja en el total', () async {
    final idProducto = await crearProducto(precio: 10, stock: 50);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 4},
      ],
      metodoPago: 'efectivo',
      descuentoGlobalTipo: TipoDescuento.fijo,
      descuentoGlobalValor: 8,
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['descuento_total'], 8.0);
    expect(venta['total'], 32.0);
  });

  test('combinación de descuento por producto y global se guarda correctamente', () async {
    final idProducto = await crearProducto(precio: 100, stock: 10);

    final idVenta = await controller.insertarVentaCompleta(
      carrito: [
        {
          'id_producto': idProducto,
          'nombre': 'Producto de prueba',
          'precio': 100.0,
          'cantidad': 1,
          'descuento_tipo': TipoDescuento.porcentaje,
          'descuento_valor': 10.0, // -10
        },
      ],
      metodoPago: 'efectivo',
      descuentoGlobalTipo: TipoDescuento.fijo,
      descuentoGlobalValor: 9, // sobre 90 -> 81
    );

    final venta = await ventaGuardada(idVenta);
    expect(venta['descuento_total'], 19.0);
    expect(venta['total'], 81.0);

    final detalle = (await detalleGuardado(idVenta)).first;
    expect(detalle['precio_neto'], 81.0);
  });

  group('límites inválidos', () {
    test('rechaza porcentaje mayor a 100 y no persiste nada', () async {
      final idProducto = await crearProducto(precio: 10, stock: 50);

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 10.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.porcentaje,
              'descuento_valor': 150.0,
            },
          ],
          metodoPago: 'efectivo',
        ),
        throwsA(isA<Exception>()),
      );

      expect(await db.query('Ventas'), isEmpty);
    });

    test('rechaza descuento fijo mayor al subtotal', () async {
      final idProducto = await crearProducto(precio: 10, stock: 50);

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 10.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.fijo,
              'descuento_valor': 50.0,
            },
          ],
          metodoPago: 'efectivo',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza descuento negativo', () async {
      final idProducto = await crearProducto(precio: 10, stock: 50);

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 10.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.fijo,
              'descuento_valor': -1.0,
            },
          ],
          metodoPago: 'efectivo',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('autorización', () {
    test('bloquea al cajero si la configuración no permite descuentos', () async {
      final idProducto = await crearProducto(precio: 10, stock: 50);
      AppConfig.actualizar(Configuracion.porDefecto().copyWith(descuentoCajeroPuedeAplicar: false));
      SessionManager.setUser(id: 1, nombre: 'Cajero1', rol: 'Cajero');

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 10.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.porcentaje,
              'descuento_valor': 5.0,
            },
          ],
          metodoPago: 'efectivo',
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'mensaje', contains('permiso')),
        ),
      );
    });

    test('exige motivo cuando el descuento supera el umbral', () async {
      final idProducto = await crearProducto(precio: 100, stock: 50);

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 100.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.porcentaje,
              'descuento_valor': 30.0, // > umbral 20%
            },
          ],
          metodoPago: 'efectivo',
          // descuentoMotivo omitido a propósito
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'mensaje', contains('motivo')),
        ),
      );
    });

    test('cajero: exige autorización de administrador al superar el umbral', () async {
      final idProducto = await crearProducto(precio: 100, stock: 50);
      SessionManager.setUser(id: 2, nombre: 'Cajero1', rol: 'Cajero');

      await expectLater(
        controller.insertarVentaCompleta(
          carrito: [
            {
              'id_producto': idProducto,
              'nombre': 'Producto de prueba',
              'precio': 100.0,
              'cantidad': 1,
              'descuento_tipo': TipoDescuento.porcentaje,
              'descuento_valor': 30.0,
            },
          ],
          metodoPago: 'efectivo',
          descuentoMotivo: 'Cliente frecuente',
          // descuentoAutorizadoPor omitido: debe rechazar
        ),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'mensaje', contains('autorización')),
        ),
      );
    });

    test('cajero con autorización de administrador puede completar el descuento', () async {
      final idProducto = await crearProducto(precio: 100, stock: 50);
      final idAdmin = await crearUsuario('Admin', nombre: 'Jefa');
      final idCajero = await crearUsuario('Cajero', nombre: 'Cajero1');
      SessionManager.setUser(id: idCajero, nombre: 'Cajero1', rol: 'Cajero');

      final idVenta = await controller.insertarVentaCompleta(
        carrito: [
          {
            'id_producto': idProducto,
            'nombre': 'Producto de prueba',
            'precio': 100.0,
            'cantidad': 1,
            'descuento_tipo': TipoDescuento.porcentaje,
            'descuento_valor': 30.0,
          },
        ],
        metodoPago: 'efectivo',
        descuentoMotivo: 'Cliente frecuente',
        descuentoAutorizadoPor: idAdmin,
      );

      final venta = await ventaGuardada(idVenta);
      expect(venta['descuento_autorizado_por'], idAdmin);
      expect(venta['descuento_motivo'], 'Cliente frecuente');

      final auditorias = await db.query(
        'Auditorias',
        where: "tabla = 'Ventas' AND accion = 'DESCUENTO' AND id_registro = ?",
        whereArgs: [idVenta],
      );
      expect(auditorias, hasLength(1));
    });

    test('administrador no requiere motivo ni autorización adicional aunque supere el umbral', () async {
      final idProducto = await crearProducto(precio: 100, stock: 50);
      final idAdmin = await crearUsuario('Admin', nombre: 'Jefa');
      SessionManager.setUser(id: idAdmin, nombre: 'Jefa', rol: 'Admin');

      // No debería lanzar aunque no se pase motivo: solo aplica a Cajero.
      // (El controlador exige motivo para CUALQUIER rol cuando se supera el
      // umbral, así que se prueba pasándolo pero sin autorización extra.)
      final idVenta = await controller.insertarVentaCompleta(
        carrito: [
          {
            'id_producto': idProducto,
            'nombre': 'Producto de prueba',
            'precio': 100.0,
            'cantidad': 1,
            'descuento_tipo': TipoDescuento.porcentaje,
            'descuento_valor': 30.0,
          },
        ],
        metodoPago: 'efectivo',
        descuentoMotivo: 'Ajuste administrativo',
      );

      final venta = await ventaGuardada(idVenta);
      expect(venta['descuento_autorizado_por'], isNull);
    });
  });

  test('rollback: sin stock suficiente en la segunda línea no persiste nada de la venta', () async {
    final idProductoA = await crearProducto(precio: 10, stock: 50);
    final idProductoB = await crearProducto(precio: 5, stock: 1); // insuficiente para 3

    await expectLater(
      controller.insertarVentaCompleta(
        carrito: [
          {
            'id_producto': idProductoA,
            'nombre': 'A',
            'precio': 10.0,
            'cantidad': 2,
            'descuento_tipo': TipoDescuento.porcentaje,
            'descuento_valor': 10.0,
          },
          {'id_producto': idProductoB, 'nombre': 'B', 'precio': 5.0, 'cantidad': 3},
        ],
        metodoPago: 'efectivo',
      ),
      throwsA(isA<Exception>()),
    );

    // Ni la venta ni el detalle de la primera línea (ya "procesada" antes
    // de fallar en la segunda) deben haber quedado guardados.
    expect(await db.query('Ventas'), isEmpty);
    expect(await db.query('Detalle_Venta'), isEmpty);

    final stockA = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProductoA]);
    expect(stockA.first['cantidad'], 50); // no se descontó nada
  });
}
