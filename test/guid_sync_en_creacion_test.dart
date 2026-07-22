// Verifica que crear una fila nueva en cada tabla sincronizable, a través
// de su controlador real, la deja con un guid_sync asignado de inmediato
// (vía DatabaseHelper.insertarConGuidSync) en vez de esperar al backfill de
// la próxima apertura de la app. Complementa test/guid_sync_migration_test.dart
// (que cubre el backfill de filas HISTÓRICAS) probando el camino de
// creación NUEVA de cada controlador afectado.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/categoria_controller.dart';
import 'package:pvapp/controllers/cliente_controller.dart';
import 'package:pvapp/controllers/producto_controller.dart';
import 'package:pvapp/controllers/promociones_controller.dart';
import 'package:pvapp/controllers/proveedor_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/models/categoria_model.dart';
import 'package:pvapp/models/cliente_model.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/producto_model.dart';
import 'package:pvapp/models/promocion_model.dart';
import 'package:pvapp/models/proveedores_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_guid_sync_creacion_test');
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

  Future<String?> guidDe(String tabla, String columnaId, int id) async {
    final filas = await db.query(tabla, where: '$columnaId = ?', whereArgs: [id]);
    return filas.first['guid_sync'] as String?;
  }

  test('CategoriaController.insertar asigna guid_sync de inmediato', () async {
    final id = await CategoriaController().insertar(Categoria(nombre: 'Bebidas'));
    expect(await guidDe('Categorias', 'id_categoria', id), isNotNull);
  });

  test('ClienteController.insertar asigna guid_sync de inmediato', () async {
    final id = await ClienteController().insertar(Cliente(
      idCliente: null,
      nombre: 'Cliente Uno',
      direccion: null,
      telefono: null,
      correo: null,
      fechaRegistro: DateTime.now().toIso8601String(),
    ));
    expect(await guidDe('Clientes', 'id_cliente', id), isNotNull);
  });

  test('ProveedorController.insertar asigna guid_sync de inmediato', () async {
    final id = await ProveedorController().insertar(Proveedores(
      idProveedor: null,
      nombre: 'Proveedor Uno',
      rfc: 'XXX010101AAA',
      direccion: 'Calle 1',
      direccionFiscal: 'Calle 1',
      telefono: '5512345678',
    ));
    expect(await guidDe('Proveedores', 'id_proveedor', id), isNotNull);
  });

  test('ProductoController.insertar asigna guid_sync a Producto e Inventario', () async {
    final id = await ProductoController().insertar(
      const Producto(
        nombre: 'Refresco',
        descripcion: '',
        precio: 20.0,
        stockMinimo: 5,
      ),
      40,
    );

    expect(await guidDe('Producto', 'id_producto', id), isNotNull);

    final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [id]);
    expect(inventario.first['guid_sync'], isNotNull);
  });

  test('CajaController.abrirCaja asigna guid_sync de inmediato', () async {
    final idCaja = await CajaController().abrirCaja(fondoInicial: 500);
    expect(await guidDe('Cajas', 'id_caja', idCaja), isNotNull);
  });

  test('PromocionesController.crear asigna guid_sync de inmediato', () async {
    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto de prueba',
      'descripcion': '',
      'precio': 10.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });

    final id = await PromocionesController().crear(Promocion(
      nombre: '10% en producto',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto],
    ));

    expect(await guidDe('Promociones', 'id_promocion', id), isNotNull);
  });

  test(
      'VentasController.insertarVentaCompleta asigna guid_sync a Ventas, '
      'Detalle_Venta, Venta_Pagos y Venta_Promociones', () async {
    await CajaController().abrirCaja(fondoInicial: 500);

    final idProducto = await db.insert('Producto', {
      'nombre': 'Producto de prueba',
      'descripcion': '',
      'precio': 10.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 100});

    await PromocionesController().crear(Promocion(
      nombre: '10% en producto',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto],
    ));

    final idVenta = await VentasController().insertarVentaCompleta(
      carrito: [
        {'id_producto': idProducto, 'nombre': 'Producto de prueba', 'precio': 10.0, 'cantidad': 2},
      ],
      pagos: const [
        {'metodo_pago': 'Efectivo', 'monto': 18.0},
      ],
    );

    expect(await guidDe('Ventas', 'id_venta', idVenta), isNotNull);

    final detalle = await db.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(detalle, hasLength(1));
    expect(detalle.first['guid_sync'], isNotNull);

    final pagosGuardados = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(pagosGuardados, hasLength(1));
    expect(pagosGuardados.first['guid_sync'], isNotNull);

    final promoAplicada = await db.query('Venta_Promociones', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(promoAplicada, hasLength(1));
    expect(promoAplicada.first['guid_sync'], isNotNull);
  });

  test('dos filas creadas en la misma sesión no comparten guid_sync', () async {
    final idA = await CategoriaController().insertar(Categoria(nombre: 'A'));
    final idB = await CategoriaController().insertar(Categoria(nombre: 'B'));

    final guidA = await guidDe('Categorias', 'id_categoria', idA);
    final guidB = await guidDe('Categorias', 'id_categoria', idB);

    expect(guidA, isNotNull);
    expect(guidB, isNotNull);
    expect(guidA, isNot(guidB));
  });
}
