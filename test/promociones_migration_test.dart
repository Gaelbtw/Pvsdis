// Prueba de migración v13 -> v14 (promociones automáticas).
//
// Construye a mano el esquema tal como quedó en la versión 13 (sin ninguna
// tabla de promociones), lo abre con la versión real de la app (14) para
// disparar `_onUpgrade`, y verifica que las tablas nuevas se agreguen sin
// perder datos existentes. También verifica que una base nueva (onCreate)
// ya las incluye, y que la migración es idempotente (abrir dos veces no
// falla ni duplica nada).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV13 = 13;

Future<void> _crearEsquemaV13(Database db, int version) async {
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

  await db.execute('''
    CREATE TABLE Cajas (
      id_caja INTEGER PRIMARY KEY AUTOINCREMENT,
      id_usuario INTEGER NOT NULL,
      fecha_apertura TEXT NOT NULL,
      fecha_cierre TEXT,
      fondo_inicial REAL NOT NULL DEFAULT 0,
      observaciones_apertura TEXT,
      ventas_efectivo REAL,
      ventas_tarjeta REAL,
      ventas_transferencia REAL,
      cambio_entregado REAL,
      devoluciones REAL,
      efectivo_esperado REAL,
      efectivo_contado REAL,
      diferencia REAL,
      observaciones_cierre TEXT,
      estado TEXT CHECK(estado IN ('Abierta','Cerrada')) NOT NULL DEFAULT 'Abierta',
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
    );
  ''');

  await db.execute('''
    CREATE TABLE Ventas (
      id_venta INTEGER PRIMARY KEY AUTOINCREMENT,
      id_cliente INTEGER,
      id_usuario INTEGER,
      id_pedido INTEGER,
      id_caja INTEGER,
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
      cambio REAL DEFAULT 0,
      FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente) ON DELETE RESTRICT,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT,
      FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido) ON DELETE SET NULL,
      FOREIGN KEY (id_caja) REFERENCES Cajas(id_caja) ON DELETE SET NULL
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
    CREATE TABLE Venta_Pagos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER NOT NULL,
      metodo_pago TEXT NOT NULL,
      monto REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE
    );
  ''');

  await db.execute('''
    CREATE TABLE Devoluciones (
      id_devolucion INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER NOT NULL,
      id_usuario INTEGER,
      id_caja INTEGER,
      fecha_hora TEXT NOT NULL,
      tipo TEXT CHECK(tipo IN ('Cancelacion','Parcial')) NOT NULL,
      motivo TEXT NOT NULL,
      importe REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE RESTRICT,
      FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT,
      FOREIGN KEY (id_caja) REFERENCES Cajas(id_caja) ON DELETE SET NULL
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_promociones_migration_test');
    path = join(tempDir.path, 'v13.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const tablasPromociones = [
    'Promociones',
    'Promocion_Productos',
    'Promocion_Categorias',
    'Promocion_Combo_Items',
    'Venta_Promociones',
    'Venta_Promociones_Detalle',
  ];

  test('migra una base v13 a v14 agregando las tablas de promociones sin perder datos', () async {
    final dbV13 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV13,
        onCreate: _crearEsquemaV13,
      ),
    );

    final idProducto = await dbV13.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 20.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV13.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idUsuario = await dbV13.insert('Usuarios', {
      'nombre': 'Admin',
      'contra': 'hash',
      'rol': 'Admin',
    });

    final idVenta = await dbV13.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': idUsuario,
      'fecha': '2026-02-01T10:00:00',
      'total': 40.0,
      'subtotal': 40.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });
    final idDetalle = await dbV13.insert('Detalle_Venta', {
      'id_venta': idVenta,
      'id_producto': idProducto,
      'cantidad': 2,
      'precio': 20.0,
      'precio_neto': 20.0,
    });

    await dbV13.insert('configuracion', {'id': 1, 'nombre_negocio': 'Mi Negocio'});

    await dbV13.close();

    final helper = DatabaseHelper();
    final dbV14 = await helper.abrirEnRuta(path);

    expect(await dbV14.getVersion(), greaterThanOrEqualTo(14));

    final tablas = await dbV14.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN (${tablasPromociones.map((_) => '?').join(',')})",
      tablasPromociones,
    );
    expect(tablas.map((t) => t['name']).toSet(), tablasPromociones.toSet());

    // Los índices nuevos también deben quedar creados.
    final indicesPromociones = await dbV14.rawQuery('PRAGMA index_list(Promociones)');
    expect(indicesPromociones, isNotEmpty);
    final indicesDetalle = await dbV14.rawQuery('PRAGMA index_list(Venta_Promociones_Detalle)');
    expect(indicesDetalle, isNotEmpty);

    // Los datos previos a la migración siguen intactos.
    final ventaMigrada = await dbV14.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaMigrada.first['total'], 40.0);

    final detalleMigrado =
        await dbV14.query('Detalle_Venta', where: 'id_detalleV = ?', whereArgs: [idDetalle]);
    expect(detalleMigrado.first['precio_neto'], 20.0);

    // Se puede insertar una promoción y su snapshot de venta sin violar FKs.
    final idPromocion = await dbV14.insert('Promociones', {
      'nombre': '10% en refrescos',
      'tipo': 'PORCENTAJE_PRODUCTO',
      'activo': 1,
      'prioridad': 0,
      'combinable': 0,
      'valor': 10.0,
      'fecha_creacion': DateTime.now().toIso8601String(),
    });
    await dbV14.insert('Promocion_Productos', {'id_promocion': idPromocion, 'id_producto': idProducto});

    final idVentaPromocion = await dbV14.insert('Venta_Promociones', {
      'id_venta': idVenta,
      'id_promocion': idPromocion,
      'nombre_snapshot': '10% en refrescos',
      'tipo_snapshot': 'PORCENTAJE_PRODUCTO',
      'ahorro_total': 4.0,
    });
    await dbV14.insert('Venta_Promociones_Detalle', {
      'id_venta_promocion': idVentaPromocion,
      'id_detalleV': idDetalle,
      'cantidad_afectada': 2,
      'ahorro': 4.0,
    });

    // Borrar la promoción no debe borrar el snapshot de la venta (ON DELETE SET NULL).
    await dbV14.delete('Promociones', where: 'id_promocion = ?', whereArgs: [idPromocion]);
    final snapshotTrasBorrar =
        await dbV14.query('Venta_Promociones', where: 'id_venta_promocion = ?', whereArgs: [idVentaPromocion]);
    expect(snapshotTrasBorrar, hasLength(1));
    expect(snapshotTrasBorrar.first['id_promocion'], isNull);
    expect(snapshotTrasBorrar.first['nombre_snapshot'], '10% en refrescos');

    await dbV14.close();
  });

  test('una base nueva (onCreate) ya incluye las tablas de promociones', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN (${tablasPromociones.map((_) => '?').join(',')})",
      tablasPromociones,
    );
    expect(tablas.map((t) => t['name']).toSet(), tablasPromociones.toSet());

    await db.close();
  });

  test('la migración es idempotente: abrir la base dos veces no falla ni duplica tablas', () async {
    final dbV13 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV13, onCreate: _crearEsquemaV13),
    );
    await dbV13.close();

    final helper = DatabaseHelper();
    final primeraApertura = await helper.abrirEnRuta(path);
    await primeraApertura.close();

    // Reabrir (mismo archivo, ya en v14) no debe fallar ni duplicar nada.
    final segundaApertura = await helper.abrirEnRuta(path);

    final tablas = await segundaApertura.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Promociones'",
    );
    expect(tablas, hasLength(1));

    await segundaApertura.close();
  });
}
