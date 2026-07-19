// Pruebas de DevolucionesController: cancelación total, devolución
// parcial, devoluciones sucesivas sobre la misma venta, límites de
// cantidad, reversión de stock y atomicidad (nada se aplica a medias si
// una parte de la operación es inválida).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late DevolucionesController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_devoluciones_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = DevolucionesController();

    // El controlador exige caja abierta para procesar devoluciones; sin
    // SessionManager.setUser(...) cae en id_usuario=1 (ver `?? 1` en
    // DevolucionesController), así que se siembra ese usuario (requerido
    // por la FK de Cajas.id_usuario) y su caja abierta.
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Crea una venta ya "vendida" (con su stock ya descontado, como lo deja
  /// VentasController.insertarVentaCompleta en producción) para poder
  /// probar la reversión de inventario al devolver.
  Future<Map<String, dynamic>> crearVentaDePrueba({
    required List<Map<String, dynamic>> productos,
    String metodoPago = 'efectivo',
    String? fecha,
  }) async {
    double total = 0;
    final idsProductos = <int>[];

    for (final p in productos) {
      final idProducto = await db.insert('Producto', {
        'nombre': p['nombre'],
        'descripcion': '',
        'precio': p['precio'],
        'stock_minimo': 0,
        'estado': 'Activo',
      });
      await db.insert('Inventario', {
        'id_producto': idProducto,
        'cantidad': p['stockInicial'],
      });
      idsProductos.add(idProducto);
      total += (p['precio'] as num) * (p['cantidadVendida'] as int);
    }

    final idVenta = await db.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': fecha ?? DateTime.now().toIso8601String(),
      'total': total,
      'metodo_pago': metodoPago,
      'estado': 'Activa',
    });

    for (var i = 0; i < productos.length; i++) {
      await db.insert('Detalle_Venta', {
        'id_venta': idVenta,
        'id_producto': idsProductos[i],
        'cantidad': productos[i]['cantidadVendida'],
        'precio': productos[i]['precio'],
      });

      await db.rawUpdate(
        'UPDATE Inventario SET cantidad = cantidad - ? WHERE id_producto = ?',
        [productos[i]['cantidadVendida'], idsProductos[i]],
      );
    }

    return {'idVenta': idVenta, 'idsProductos': idsProductos, 'total': total};
  }

  Future<int> stockDe(int idProducto) async {
    final res = await db.query(
      'Inventario',
      columns: ['cantidad'],
      where: 'id_producto = ?',
      whereArgs: [idProducto],
    );
    return res.first['cantidad'] as int;
  }

  Future<String> estadoDe(int idVenta) async {
    final res = await db.query(
      'Ventas',
      columns: ['estado'],
      where: 'id_venta = ?',
      whereArgs: [idVenta],
    );
    return res.first['estado'] as String;
  }

  test('cancelación total: devuelve todo, reintegra stock y marca Cancelada', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 5},
    ]);
    final idVenta = venta['idVenta'] as int;
    final idProducto = (venta['idsProductos'] as List<int>).first;

    expect(await stockDe(idProducto), 15); // 20 - 5 vendidos

    final idDevolucion = await controller.cancelarVenta(
      idVenta: idVenta,
      motivo: 'Cliente se arrepintió',
    );

    expect(idDevolucion, greaterThan(0));
    expect(await estadoDe(idVenta), 'Cancelada');
    expect(await stockDe(idProducto), 20); // reintegrado por completo

    final comprobante = await controller.obtenerComprobante(idDevolucion);
    expect(comprobante.tipo, 'Cancelacion');
    expect(comprobante.importe, 50.0);
    expect(comprobante.items, hasLength(1));
  });

  test('devolución parcial: reintegra solo lo devuelto y marca Parcialmente devuelta', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 5},
    ]);
    final idVenta = venta['idVenta'] as int;
    final idProducto = (venta['idsProductos'] as List<int>).first;

    await controller.devolverParcial(
      idVenta: idVenta,
      motivo: 'Producto dañado',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
      ],
    );

    expect(await estadoDe(idVenta), 'Parcialmente devuelta');
    expect(await stockDe(idProducto), 17); // 15 + 2 reintegrados
  });

  test('segunda devolución sobre la misma venta acumula correctamente hasta cancelar', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 5},
    ]);
    final idVenta = venta['idVenta'] as int;
    final idProducto = (venta['idsProductos'] as List<int>).first;

    await controller.devolverParcial(
      idVenta: idVenta,
      motivo: 'Primera devolución',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
      ],
    );
    expect(await estadoDe(idVenta), 'Parcialmente devuelta');
    expect(await stockDe(idProducto), 17);

    // Segunda devolución: quedaban 3 pendientes, devuelve 2 más.
    await controller.devolverParcial(
      idVenta: idVenta,
      motivo: 'Segunda devolución',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
      ],
    );
    expect(await estadoDe(idVenta), 'Parcialmente devuelta');
    expect(await stockDe(idProducto), 19);

    // Tercera devolución: el último pendiente (1) agota todo lo vendido.
    await controller.devolverParcial(
      idVenta: idVenta,
      motivo: 'Tercera devolución',
      items: [
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );
    expect(await estadoDe(idVenta), 'Cancelada');
    expect(await stockDe(idProducto), 20);

    final detalle = await controller.obtenerDetalleVenta(idVenta);
    expect(detalle.devoluciones, hasLength(3));
    expect(detalle.items.first['cantidad_pendiente'], 0);
  });

  test('rechaza devolver más de lo pendiente, sin tocar stock ni estado', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 3},
    ]);
    final idVenta = venta['idVenta'] as int;
    final idProducto = (venta['idsProductos'] as List<int>).first;

    expect(
      () => controller.devolverParcial(
        idVenta: idVenta,
        motivo: 'Intento inválido',
        items: [
          {'id_producto': idProducto, 'cantidad': 5},
        ],
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'mensaje',
          contains('pendiente'),
        ),
      ),
    );

    // No debe haber alterado nada.
    expect(await stockDe(idProducto), 17); // 20 - 3, sin cambios
    expect(await estadoDe(idVenta), 'Activa');
  });

  test('rechaza devolver sobre una venta ya cancelada', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 3},
    ]);
    final idVenta = venta['idVenta'] as int;

    await controller.cancelarVenta(idVenta: idVenta, motivo: 'Cancelación inicial');

    expect(
      () => controller.devolverParcial(
        idVenta: idVenta,
        motivo: 'Segundo intento',
        items: [
          {'id_producto': (venta['idsProductos'] as List<int>).first, 'cantidad': 1},
        ],
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'mensaje',
          contains('ya está cancelada'),
        ),
      ),
    );
  });

  test('rechaza motivo vacío', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 3},
    ]);

    expect(
      () => controller.cancelarVenta(idVenta: venta['idVenta'] as int, motivo: '   '),
      throwsA(isA<Exception>()),
    );
  });

  test('rollback completo: si un producto de la operación es inválido, no se aplica nada', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Producto A', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 3},
      {'nombre': 'Producto B', 'precio': 5.0, 'stockInicial': 20, 'cantidadVendida': 2},
    ]);
    final idVenta = venta['idVenta'] as int;
    final ids = venta['idsProductos'] as List<int>;
    final idA = ids[0];
    final idB = ids[1];

    final stockAntesA = await stockDe(idA);
    final stockAntesB = await stockDe(idB);

    // A es válido (2 de 3 disponibles), B excede lo vendido (99 de 2).
    await expectLater(
      controller.devolverParcial(
        idVenta: idVenta,
        motivo: 'Debe fallar por completo',
        items: [
          {'id_producto': idA, 'cantidad': 2},
          {'id_producto': idB, 'cantidad': 99},
        ],
      ),
      throwsA(isA<Exception>()),
    );

    // Ni A ni B deben haber cambiado: la transacción completa se revirtió.
    expect(await stockDe(idA), stockAntesA);
    expect(await stockDe(idB), stockAntesB);
    expect(await estadoDe(idVenta), 'Activa');

    final devoluciones = await db.query('Devoluciones', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(devoluciones, isEmpty);
  });

  test('la cantidad devuelta combina líneas repetidas del mismo producto en una sola llamada', () async {
    final venta = await crearVentaDePrueba(productos: [
      {'nombre': 'Refresco', 'precio': 10.0, 'stockInicial': 20, 'cantidadVendida': 5},
    ]);
    final idVenta = venta['idVenta'] as int;
    final idProducto = (venta['idsProductos'] as List<int>).first;

    await controller.devolverParcial(
      idVenta: idVenta,
      motivo: 'Combinado',
      items: [
        {'id_producto': idProducto, 'cantidad': 2},
        {'id_producto': idProducto, 'cantidad': 1},
      ],
    );

    expect(await stockDe(idProducto), 18); // 15 + 3 combinados
  });
}
