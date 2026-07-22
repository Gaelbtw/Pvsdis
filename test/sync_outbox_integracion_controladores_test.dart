// Sub-fase 3f: verifica que el barrido de reemplazo de
// DatabaseHelper.insertarConGuidSync por SyncOutboxWriter en los
// controladores reales (categoria_controller.dart, cliente_controller.dart,
// proveedor_controller.dart, producto_controller.dart, caja_controller.dart,
// promociones_controller.dart, ventas_controller.dart) efectivamente encola
// cada entidad con el nombre correcto (sin typos) y un payload parseable,
// cuando SÍ hay una sesión de sincronización activa.
//
// AuthService.setSesionDePrueba (puerta trasera solo para tests, ver
// auth_service.dart) fuerza la sesión en memoria de AuthService.instancia
// sin pasar por TokenStorage (que depende de path_provider, no mockeado en
// flutter test) -- es lo que permite ejercitar los controladores reales
// (que usan AuthService.instancia internamente, sin inyección) como si
// hubiera sesión activa.
import 'dart:convert';
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
import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/models/categoria_model.dart';
import 'package:pvapp/models/cliente_model.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/producto_model.dart';
import 'package:pvapp/models/promocion_model.dart';
import 'package:pvapp/models/proveedores_model.dart';

SesionSync _sesionDePrueba() => SesionSync(
      usuarioId: '22222222-2222-2222-2222-222222222222',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Admin'],
      sucursalId: null,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: '11111111-1111-1111-1111-111111111111',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_outbox_integracion_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    AuthService.setSesionDePrueba(_sesionDePrueba());

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
    AuthService.setSesionDePrueba(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Map<String, dynamic>?> outboxDe(String entidad, String guid) async {
    final filas = await db.query('Sync_Outbox', where: 'entidad = ? AND guid_registro = ?', whereArgs: [entidad, guid]);
    return filas.isEmpty ? null : filas.first;
  }

  test('CategoriaController.insertar y .actualizar encolan CREAR y ACTUALIZAR', () async {
    final id = await CategoriaController().insertar(Categoria(nombre: 'Bebidas'));
    final guid = (await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [id])).first['guid_sync'] as String;

    final crear = await outboxDe('CategoriaProducto', guid);
    expect(crear, isNotNull);
    expect(crear!['operacion'], 'CREAR');
    expect((jsonDecode(crear['datos_json'] as String) as Map)['nombre'], 'Bebidas');

    await CategoriaController().actualizar(Categoria(idCategoria: id, nombre: 'Bebidas frías'));
    final outboxTrasUpdate = await db.query('Sync_Outbox', where: 'entidad = ? AND guid_registro = ?', whereArgs: ['CategoriaProducto', guid]);
    expect(outboxTrasUpdate, hasLength(2));
    expect(outboxTrasUpdate.last['operacion'], 'ACTUALIZAR');
    expect((jsonDecode(outboxTrasUpdate.last['datos_json'] as String) as Map)['nombre'], 'Bebidas frías');
  });

  test('ClienteController.insertar encola Cliente con el payload correcto', () async {
    final id = await ClienteController().insertar(Cliente(
      idCliente: null,
      nombre: 'Cliente Uno',
      direccion: 'Calle 1',
      telefono: 5551234567,
      correo: 'uno@test.com',
      fechaRegistro: DateTime.now().toIso8601String(),
    ));
    final guid = (await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [id])).first['guid_sync'] as String;

    final outbox = await outboxDe('Cliente', guid);
    expect(outbox, isNotNull);
    final payload = jsonDecode(outbox!['datos_json'] as String) as Map;
    expect(payload['nombre'], 'Cliente Uno');
    expect(payload['telefono'], '5551234567');
  });

  test('ProveedorController.insertar encola Proveedor con razonSocial mapeado', () async {
    final id = await ProveedorController().insertar(Proveedores(
      idProveedor: null,
      nombre: 'Proveedor Uno',
      rfc: 'XXX010101AAA',
      direccion: 'Calle 1',
      direccionFiscal: 'Calle 1',
      telefono: '5512345678',
    ));
    final guid = (await db.query('Proveedores', where: 'id_proveedor = ?', whereArgs: [id])).first['guid_sync'] as String;

    final outbox = await outboxDe('Proveedor', guid);
    expect(outbox, isNotNull);
    expect((jsonDecode(outbox!['datos_json'] as String) as Map)['razonSocial'], 'Proveedor Uno');
  });

  test('ProductoController.insertar con categoría encola Producto (Inventario NO se encola)', () async {
    final idCategoria = await CategoriaController().insertar(Categoria(nombre: 'Bebidas'));

    final idProducto = await ProductoController().insertar(
      Producto(nombre: 'Refresco', descripcion: '', precio: 20.0, categoriaId: idCategoria),
      40,
    );
    final guidProducto =
        (await db.query('Producto', where: 'id_producto = ?', whereArgs: [idProducto])).first['guid_sync'] as String;

    final outboxProducto = await outboxDe('Producto', guidProducto);
    expect(outboxProducto, isNotNull);

    // Inventario nunca se encola (Stock es pull-only) -- solo Producto y
    // CategoriaProducto (esta última del insertar de la categoría arriba).
    final outboxCompleto = await db.query('Sync_Outbox');
    expect(outboxCompleto.map((f) => f['entidad']), isNot(contains('Stock')));
  });

  test('CajaController.abrirCaja y .cerrarCaja encolan CajaSesion CREAR y ACTUALIZAR', () async {
    final idCaja = await CajaController().abrirCaja(fondoInicial: 500);
    final guid = (await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja])).first['guid_sync'] as String;

    final crear = await outboxDe('CajaSesion', guid);
    expect(crear, isNotNull);
    expect(crear!['operacion'], 'CREAR');

    await CajaController().cerrarCaja(idCaja: idCaja, efectivoContado: 500);
    final filas = await db.query('Sync_Outbox', where: 'entidad = ? AND guid_registro = ?', whereArgs: ['CajaSesion', guid]);
    expect(filas, hasLength(2));
    expect(filas.last['operacion'], 'ACTUALIZAR');
  });

  test('PromocionesController.crear encola Promocion con el tipo traducido', () async {
    final idProducto = await ProductoController().insertar(
      Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
      10,
    );

    final id = await PromocionesController().crear(Promocion(
      nombre: '10% en producto',
      tipo: TipoPromocion.porcentajeProducto,
      valor: 10,
      productosIds: [idProducto],
    ));
    final guid = (await db.query('Promociones', where: 'id_promocion = ?', whereArgs: [id])).first['guid_sync'] as String;

    final outbox = await outboxDe('Promocion', guid);
    expect(outbox, isNotNull);
    expect((jsonDecode(outbox!['datos_json'] as String) as Map)['tipo'], 'PorcentajeProducto');
  });

  test('VentasController.insertarVentaCompleta encola Venta, VentaDetalle, VentaPago y sus movimientos de bitácora', () async {
    // VentaMapper/CajaSesionMapper/MovimientoInventarioMapper exigen la
    // sucursal del dispositivo resuelta (ver SucursalResolver, Fase 3d) --
    // sin esto, el payload no se puede armar y SyncOutboxWriter encola el
    // sentinela de "esperando prerrequisito" (datos_json vacío) en vez del
    // payload real.
    await db.insert('Sync_Config', {'id': 1, 'sucursal_id': 'sucursal-test', 'sucursal_nombre': 'Principal'});

    await CajaController().abrirCaja(fondoInicial: 500);
    final idProducto = await ProductoController().insertar(
      Producto(nombre: 'Producto de prueba', descripcion: '', precio: 10.0),
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
    final guidVenta = (await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta])).first['guid_sync'] as String;

    final outboxVenta = await outboxDe('Venta', guidVenta);
    expect(outboxVenta, isNotNull);
    final payloadVenta = jsonDecode(outboxVenta!['datos_json'] as String) as Map;
    expect(payloadVenta['usuarioId'], '22222222-2222-2222-2222-222222222222');
    expect(payloadVenta['estado'], 'Completada');

    final entidades = (await db.query('Sync_Outbox')).map((f) => f['entidad']).toSet();
    expect(entidades, containsAll(['CajaSesion', 'Producto', 'Venta', 'VentaDetalle', 'VentaPago', 'MovimientoInventario', 'MovimientoCaja']));

    // Orden FIFO: Venta antes que VentaDetalle/VentaPago (mismo criterio
    // que exige el backend, ver comentario en sync_dtos.dart).
    final filasOrdenadas = await db.query('Sync_Outbox', orderBy: 'id ASC');
    final idxVenta = filasOrdenadas.indexWhere((f) => f['entidad'] == 'Venta' && f['guid_registro'] == guidVenta);
    final idxDetalle = filasOrdenadas.indexWhere((f) => f['entidad'] == 'VentaDetalle');
    expect(idxVenta, lessThan(idxDetalle));
  });

  test('sin sesión de sync activa, ningún controlador encola nada (pero sí escribe local)', () async {
    AuthService.setSesionDePrueba(null);

    final id = await CategoriaController().insertar(Categoria(nombre: 'Bebidas'));
    expect(await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [id]), hasLength(1));
    expect(await db.query('Sync_Outbox'), isEmpty);
  });
}
