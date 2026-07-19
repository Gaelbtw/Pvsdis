// Prueba de migración v11 -> v12 (pagos mixtos).
//
// Construye a mano el esquema tal como quedó en la versión 11 (con columnas
// de descuento pero sin `Venta_Pagos` ni `Ventas.cambio`), lo abre con la
// versión real de la app (12) para disparar `_onUpgrade`, y verifica que la
// tabla nueva se cree, que las ventas históricas se "backfilleen" con una
// sola fila de pago (asumiendo que cubrieron el total exacto, ya que el
// cambio histórico nunca se persistió), y que reabrir la base no duplique
// ese backfill.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV11 = 11;

Future<void> _crearEsquemaV11(Database db, int version) async {
  await db.execute('''
    CREATE TABLE Proveedores (
      id_proveedor INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      rfc TEXT,
      direccion TEXT,
      direccion_fiscal TEXT,
      telefono TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE Usuarios (
      id_usuario INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      contra TEXT NOT NULL,
      rol TEXT CHECK(rol IN ('Cajero','Admin')) NOT NULL
    );
  ''');

  await db.execute('''
    CREATE TABLE Compras (
      id_compra INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha DATE,
      total REAL,
      id_proveedor INTEGER,
      id_usuario INTEGER,
      FOREIGN KEY (id_proveedor) REFERENCES Proveedores(id_proveedor) ON DELETE RESTRICT,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Categorias (
      id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL
    );
  ''');

  await db.execute('''
    CREATE TABLE Detalle_Compra (
      id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
      id_compra INTEGER,
      id_producto INTEGER,
      cantidad INTEGER DEFAULT 1,
      precio REAL,
      FOREIGN KEY (id_compra) REFERENCES Compras(id_compra) ON DELETE CASCADE,
      FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Clientes (
      id_cliente INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      direccion TEXT,
      telefono INTEGER,
      correo TEXT,
      fecha_registro DATE
    );
  ''');

  await db.execute('''
    CREATE TABLE Pedidos (
      id_pedido INTEGER PRIMARY KEY AUTOINCREMENT,
      id_cliente INTEGER,
      fecha DATE,
      estado TEXT,
      total REAL DEFAULT 0,
      fecha_entrega TEXT,
      tipo_entrega TEXT,
      direccion TEXT,
      FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Detalle_Pedido (
      id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
      id_pedido INTEGER,
      id_producto INTEGER,
      cantidad INTEGER,
      precio REAL,
      FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido) ON DELETE CASCADE,
      FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
    );
  ''');

  // Ventas tal como estaba ANTES de pagos mixtos: con columnas de descuento
  // pero sin `cambio`.
  await db.execute('''
    CREATE TABLE Ventas (
      id_venta INTEGER PRIMARY KEY AUTOINCREMENT,
      id_cliente INTEGER,
      id_usuario INTEGER,
      id_pedido INTEGER,
      fecha DATE,
      total REAL,
      metodo_pago TEXT DEFAULT 'efectivo',
      estado TEXT DEFAULT 'Activa',
      subtotal REAL DEFAULT 0,
      descuento_total REAL DEFAULT 0,
      descuento_global_tipo TEXT,
      descuento_global_valor REAL DEFAULT 0,
      descuento_motivo TEXT,
      descuento_autorizado_por INTEGER,
      FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente) ON DELETE RESTRICT,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT,
      FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido) ON DELETE SET NULL
    );
  ''');

  await db.execute('''
    CREATE TABLE Detalle_Venta (
      id_detalleV INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER,
      id_producto INTEGER,
      cantidad INTEGER,
      precio REAL,
      descuento_tipo TEXT,
      descuento_valor REAL DEFAULT 0,
      descuento_monto REAL DEFAULT 0,
      precio_neto REAL,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE,
      FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Devoluciones (
      id_devolucion INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER NOT NULL,
      id_usuario INTEGER,
      fecha_hora TEXT NOT NULL,
      tipo TEXT CHECK(tipo IN ('Cancelacion','Parcial')) NOT NULL,
      motivo TEXT NOT NULL,
      importe REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE RESTRICT,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Detalle_Devolucion (
      id_detalle_devolucion INTEGER PRIMARY KEY AUTOINCREMENT,
      id_devolucion INTEGER NOT NULL,
      id_producto INTEGER NOT NULL,
      cantidad INTEGER NOT NULL,
      precio REAL NOT NULL,
      FOREIGN KEY (id_devolucion) REFERENCES Devoluciones(id_devolucion) ON DELETE CASCADE,
      FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Producto (
      id_producto INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      descripcion TEXT,
      precio REAL NOT NULL,
      precio_compra REAL,
      categoria TEXT,
      stock_minimo INTEGER DEFAULT 0,
      estado TEXT CHECK(estado IN ('Activo','Inactivo')) DEFAULT 'Activo',
      id_categoria INTEGER,
      codigo_barras TEXT,
      FOREIGN KEY (id_categoria) REFERENCES Categorias(id_categoria) ON DELETE SET NULL
    );
  ''');

  await db.execute('''
    CREATE TABLE Inventario (
      id_inventario INTEGER PRIMARY KEY AUTOINCREMENT,
      id_producto INTEGER UNIQUE,
      cantidad INTEGER,
      FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE CASCADE
    );
  ''');

  await db.execute('''
    CREATE TABLE Reporte (
      id_reporte INTEGER PRIMARY KEY AUTOINCREMENT,
      tipo TEXT,
      descripcion TEXT,
      fecha DATE,
      id_usuario INTEGER,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario)
    );
  ''');

  await db.execute('''
    CREATE TABLE configuracion (
      id INT PRIMARY KEY,
      hora_inicio_matutino VARCHAR(10),
      hora_fin_matutino VARCHAR(10),
      hora_inicio_vespertino VARCHAR(10),
      hora_fin_vespertino VARCHAR(10),
      fondo_caja REAL,
      stock_minimo INT,
      nombre_negocio TEXT,
      logo_path TEXT,
      direccion TEXT,
      telefono TEXT,
      correo TEXT,
      rfc TEXT,
      simbolo_moneda TEXT,
      tasa_impuesto REAL,
      mensaje_ticket TEXT,
      color_primario INTEGER,
      descuento_maximo_porcentaje REAL DEFAULT 20,
      descuento_cajero_puede_aplicar INTEGER DEFAULT 1,
      descuento_cajero_requiere_autorizacion INTEGER DEFAULT 1
    );
  ''');

  await db.execute('''
    CREATE TABLE Auditorias (
      id_auditoria INTEGER PRIMARY KEY AUTOINCREMENT,
      fecha_hora TEXT NOT NULL,
      usuario TEXT NOT NULL,
      tabla TEXT NOT NULL,
      accion TEXT NOT NULL,
      id_registro INTEGER,
      descripcion TEXT
    );
  ''');

  await db.execute('CREATE UNIQUE INDEX idx_producto_codigo_barras ON Producto(codigo_barras);');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_venta_pagos_migration_test');
    path = join(tempDir.path, 'v11.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v11 a v12 creando Venta_Pagos y backfilleando ventas históricas', () async {
    final dbV11 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV11,
        onCreate: _crearEsquemaV11,
      ),
    );

    final idProducto = await dbV11.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 37.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV11.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idVentaEfectivo = await dbV11.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': '2026-02-01T10:00:00',
      'total': 37.0,
      'subtotal': 37.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });
    final idVentaTarjeta = await dbV11.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': '2026-02-02T11:00:00',
      'total': 74.0,
      'subtotal': 74.0,
      'metodo_pago': 'tarjeta',
      'estado': 'Activa',
    });

    await dbV11.close();

    final helper = DatabaseHelper();
    var db = await helper.abrirEnRuta(path);

    // No se compara contra un número fijo (ver mismo criterio en las demás
    // pruebas de migración).
    expect(await db.getVersion(), greaterThanOrEqualTo(12));

    // La tabla nueva existe y tiene el índice esperado.
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Venta_Pagos'",
    );
    expect(tablas, hasLength(1));

    final indices = await db.rawQuery('PRAGMA index_list(Venta_Pagos)');
    expect(indices.map((i) => i['name']), contains('idx_venta_pagos_id_venta'));

    // Ventas.cambio existe, y en filas históricas queda en su DEFAULT 0
    // (el cambio real de esas ventas nunca se persistió).
    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('cambio'));

    final ventaEfectivoMigrada = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVentaEfectivo]);
    expect((ventaEfectivoMigrada.first['cambio'] as num).toDouble(), 0);

    // Backfill: cada venta histórica queda con una sola fila de pago, por el
    // método y el total ya guardados.
    final pagosEfectivo = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVentaEfectivo]);
    expect(pagosEfectivo, hasLength(1));
    expect(pagosEfectivo.first['metodo_pago'], 'efectivo');
    expect((pagosEfectivo.first['monto'] as num).toDouble(), 37.0);

    final pagosTarjeta = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVentaTarjeta]);
    expect(pagosTarjeta, hasLength(1));
    expect(pagosTarjeta.first['metodo_pago'], 'tarjeta');
    expect((pagosTarjeta.first['monto'] as num).toDouble(), 74.0);

    // Lo migrado en versiones anteriores sigue intacto.
    final columnasDetalle = await db.rawQuery('PRAGMA table_info(Detalle_Venta)');
    expect(columnasDetalle.map((c) => c['name']), contains('precio_neto'));

    await db.close();

    // Reabrir (dispara _onOpen otra vez) no debe duplicar el backfill.
    db = await helper.abrirEnRuta(path);
    final pagosTrasReapertura =
        await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVentaEfectivo]);
    expect(pagosTrasReapertura, hasLength(1));

    await db.close();
  });

  test('una base nueva (onCreate) ya incluye Venta_Pagos y Ventas.cambio', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Venta_Pagos'",
    );
    expect(tablas, hasLength(1));

    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('cambio'));

    await db.close();
  });
}
