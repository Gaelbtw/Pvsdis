// Sub-fase 3e del motor de sincronización: verifica que cada punto de
// escritura ya identificado (Producto/Ventas/Compras/Devoluciones/Caja)
// deja la fila esperada en las bitácoras nuevas de la Fase 3
// (Movimiento_Inventario, Movimiento_Caja, Corte_Caja). Mismo patrón que
// guid_sync_en_creacion_test.dart: DB real en memoria vía
// DatabaseHelper.setTestDatabase, ejercitando los controladores reales.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/compras_controller.dart';
import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/producto_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_bitacoras_controladores_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();

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

  group('ProductoController', () {
    test('insertar deja un Movimiento_Inventario AjustePositivo de 0 -> stockInicial', () async {
      final id = await ProductoController().insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 20.0),
        40,
      );

      final movimientos = await db.query('Movimiento_Inventario', where: 'id_producto = ?', whereArgs: [id]);
      expect(movimientos, hasLength(1));
      expect(movimientos.first['tipo_movimiento'], 'AjustePositivo');
      expect(movimientos.first['cantidad_anterior'], 0);
      expect(movimientos.first['cantidad_nueva'], 40);
      expect(movimientos.first['guid_sync'], isNotNull);
    });

    test('actualizarStock deja AjusteNegativo cuando el stock baja', () async {
      final id = await ProductoController().insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 20.0),
        40,
      );

      await ProductoController().actualizarStock(id, 25);

      final movimientos = await db.query(
        'Movimiento_Inventario',
        where: 'id_producto = ? AND tipo_movimiento = ?',
        whereArgs: [id, 'AjusteNegativo'],
      );
      expect(movimientos, hasLength(1));
      expect(movimientos.first['cantidad_anterior'], 40);
      expect(movimientos.first['cantidad_nueva'], 25);
      expect(movimientos.first['cantidad'], 15);
    });

    test('actualizarStock no deja movimiento si la cantidad no cambia', () async {
      final id = await ProductoController().insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 20.0),
        40,
      );

      await ProductoController().actualizarStock(id, 40);

      final movimientos = await db.query(
        'Movimiento_Inventario',
        where: 'id_producto = ? AND tipo_movimiento = ?',
        whereArgs: [id, 'AjusteNegativo'],
      );
      expect(movimientos, isEmpty);
    });

    test('agregarStock deja un AjustePositivo con el delta correcto', () async {
      final id = await ProductoController().insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 20.0),
        10,
      );

      await ProductoController().agregarStock(id, 5);

      final movimientos = await db.query(
        'Movimiento_Inventario',
        where: 'id_producto = ? AND tipo_movimiento = ? AND cantidad_anterior = ?',
        whereArgs: [id, 'AjustePositivo', 10],
      );
      expect(movimientos, hasLength(1));
      expect(movimientos.first['cantidad'], 5);
      expect(movimientos.first['cantidad_nueva'], 15);
    });
  });

  group('VentasController', () {
    test('insertarVentaCompleta deja SalidaVenta por producto y un Movimiento_Caja por pago', () async {
      final idCaja = await CajaController().abrirCaja(fondoInicial: 500);

      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        100,
      );

      final idVenta = await VentasController().insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      );

      final movimientosInventario = await db.query(
        'Movimiento_Inventario',
        where: 'referencia_tipo = ? AND referencia_id = ?',
        whereArgs: ['Venta', idVenta],
      );
      expect(movimientosInventario, hasLength(1));
      expect(movimientosInventario.first['tipo_movimiento'], 'SalidaVenta');
      expect(movimientosInventario.first['cantidad'], 2);
      expect(movimientosInventario.first['cantidad_anterior'], 100);
      expect(movimientosInventario.first['cantidad_nueva'], 98);

      final movimientosCaja = await db.query(
        'Movimiento_Caja',
        where: 'id_caja = ? AND id_venta_referencia = ?',
        whereArgs: [idCaja, idVenta],
      );
      expect(movimientosCaja, hasLength(1));
      expect(movimientosCaja.first['tipo_movimiento'], 'VentaEfectivo');
      expect(movimientosCaja.first['monto'], 20.0);
    });

    test('pagos mixtos dejan un Movimiento_Caja por cada método', () async {
      await CajaController().abrirCaja(fondoInicial: 500);
      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        100,
      );

      final idVenta = await VentasController().insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 3},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 10.0},
          {'metodo_pago': 'Tarjeta', 'monto': 20.0},
        ],
      );

      final movimientosCaja = await db.query('Movimiento_Caja', where: 'id_venta_referencia = ?', whereArgs: [idVenta]);
      expect(movimientosCaja, hasLength(2));
      expect(movimientosCaja.map((m) => m['tipo_movimiento']), containsAll(['VentaEfectivo', 'VentaTarjeta']));
    });
  });

  group('ComprasController', () {
    test('insertarCompraCompleta deja un Movimiento_Inventario EntradaCompra', () async {
      final idProveedor = await db.insert('Proveedores', {'nombre': 'Proveedor Uno'});
      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        5,
      );

      final idCompra = await ComprasController().insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 20, 'precio_compra': 6.0},
        ],
        120.0,
        idProveedor,
      );

      final movimientos = await db.query(
        'Movimiento_Inventario',
        where: 'referencia_tipo = ? AND id_producto = ?',
        whereArgs: ['Compra', idProducto],
      );
      expect(movimientos, hasLength(1));
      expect(movimientos.first['tipo_movimiento'], 'EntradaCompra');
      expect(movimientos.first['cantidad'], 20);
      expect(movimientos.first['cantidad_anterior'], 5);
      expect(movimientos.first['cantidad_nueva'], 25);
      expect(movimientos.first['motivo'], contains('$idCompra'));
    });

    test('eliminarCompra deja un Movimiento_Inventario AjusteNegativo revirtiendo la entrada', () async {
      final idProveedor = await db.insert('Proveedores', {'nombre': 'Proveedor Uno'});
      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        0,
      );

      final idCompra = await ComprasController().insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 20, 'precio_compra': 6.0},
        ],
        120.0,
        idProveedor,
      );

      await ComprasController().eliminarCompra(idCompra);

      final movimientos = await db.query(
        'Movimiento_Inventario',
        where: 'referencia_tipo = ? AND id_producto = ? AND tipo_movimiento = ?',
        whereArgs: ['Compra', idProducto, 'AjusteNegativo'],
      );
      expect(movimientos, hasLength(1));
      expect(movimientos.first['cantidad'], 20);
      expect(movimientos.first['cantidad_anterior'], 20);
      expect(movimientos.first['cantidad_nueva'], 0);
    });
  });

  group('DevolucionesController', () {
    test('cancelación total deja DevolucionVenta y un Movimiento_Caja negativo', () async {
      final idCaja = await CajaController().abrirCaja(fondoInicial: 500);
      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        100,
      );

      final idVenta = await VentasController().insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 20.0},
        ],
      );

      final idDevolucion = await DevolucionesController().cancelarVenta(idVenta: idVenta, motivo: 'Cliente arrepentido');

      final movimientosInventario = await db.query(
        'Movimiento_Inventario',
        where: 'referencia_tipo = ? AND referencia_id = ? AND tipo_movimiento = ?',
        whereArgs: ['Venta', idVenta, 'DevolucionVenta'],
      );
      expect(movimientosInventario, hasLength(1));
      expect(movimientosInventario.first['cantidad'], 2);

      final movimientosCaja = await db.query(
        'Movimiento_Caja',
        where: 'id_caja = ? AND tipo_movimiento = ?',
        whereArgs: [idCaja, 'DevolucionEfectivo'],
      );
      expect(movimientosCaja, hasLength(1));
      expect(movimientosCaja.first['monto'], -20.0); // negativo: salida de efectivo
      expect(movimientosCaja.first['id_venta_referencia'], idVenta);

      expect(idDevolucion, isNotNull);
    });
  });

  group('CajaController', () {
    test('cerrarCaja deja un Corte_Caja con los totales congelados', () async {
      final idCaja = await CajaController().abrirCaja(fondoInicial: 500);
      final idProducto = await ProductoController().insertar(
        const Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
        100,
      );
      await VentasController().insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 10.0},
        ],
      );

      await CajaController().cerrarCaja(idCaja: idCaja, efectivoContado: 510.0);

      final cortes = await db.query('Corte_Caja', where: 'id_caja = ?', whereArgs: [idCaja]);
      expect(cortes, hasLength(1));
      expect(cortes.first['total_efectivo_sistema'], 510.0); // fondoInicial 500 + venta 10
      expect(cortes.first['total_efectivo_contado'], 510.0);
      expect(cortes.first['diferencia'], 0.0);
      expect(cortes.first['guid_sync'], isNotNull);
    });
  });
}
