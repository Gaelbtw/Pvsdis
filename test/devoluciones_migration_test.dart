// Prueba de migración v9 -> v10 (devoluciones/cancelaciones).
//
// Construye a mano el esquema tal como quedó en la versión 9 (con
// codigo_barras pero sin `estado` en Ventas ni las tablas de
// devoluciones), lo abre con la versión real de la app (10) para disparar
// `_onUpgrade`, y verifica que todo lo nuevo se agregue sin perder datos
// existentes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV9 = 9;

Future<void> _crearEsquemaV9(Database db, int version) async {
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

  // Ventas tal como estaba ANTES de esta funcionalidad: sin `estado`.
  await db.execute('''
    CREATE TABLE Ventas (
      id_venta INTEGER PRIMARY KEY AUTOINCREMENT,
      id_cliente INTEGER,
      id_usuario INTEGER,
      id_pedido INTEGER,
      fecha DATE,
      total REAL,
      metodo_pago TEXT DEFAULT 'efectivo',
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
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE,
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
      color_primario INTEGER
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_devoluciones_migration_test');
    path = join(tempDir.path, 'v9.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v9 a v10 agregando estado y las tablas de devoluciones', () async {
    final dbV9 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV9,
        onCreate: _crearEsquemaV9,
      ),
    );

    final idProducto = await dbV9.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 18.5,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV9.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idVenta = await dbV9.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': '2026-01-10T10:00:00',
      'total': 37.0,
      'metodo_pago': 'efectivo',
    });
    await dbV9.insert('Detalle_Venta', {
      'id_venta': idVenta,
      'id_producto': idProducto,
      'cantidad': 2,
      'precio': 18.5,
    });

    await dbV9.close();

    final helper = DatabaseHelper();
    final dbV10 = await helper.abrirEnRuta(path);

    // No se compara contra un número fijo: la versión real sigue subiendo
    // con cada nueva funcionalidad (ver descuento_migration_test.dart). Lo
    // que importa es que la migración v9 -> v10+ sí se haya aplicado.
    expect(await dbV10.getVersion(), greaterThanOrEqualTo(10));

    // La columna nueva existe y la venta existente quedó 'Activa'.
    final columnasVentas = await dbV10.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('estado'));

    final ventaMigrada = await dbV10.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaMigrada, hasLength(1));
    expect(ventaMigrada.first['estado'], 'Activa');
    expect(ventaMigrada.first['total'], 37.0); // el total original no se tocó

    // El detalle original de la venta se conserva intacto.
    final detalle = await dbV10.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(detalle, hasLength(1));
    expect(detalle.first['cantidad'], 2);

    // Las tablas nuevas existen y son utilizables.
    final tablas = await dbV10.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Devoluciones','Detalle_Devolucion')",
    );
    expect(tablas, hasLength(2));

    final idDevolucion = await dbV10.insert('Devoluciones', {
      'id_venta': idVenta,
      'id_usuario': null,
      'fecha_hora': DateTime.now().toIso8601String(),
      'tipo': 'Parcial',
      'motivo': 'Prueba post-migración',
      'importe': 18.5,
    });
    await dbV10.insert('Detalle_Devolucion', {
      'id_devolucion': idDevolucion,
      'id_producto': idProducto,
      'cantidad': 1,
      'precio': 18.5,
    });

    final detalleDevolucion = await dbV10.query(
      'Detalle_Devolucion',
      where: 'id_devolucion = ?',
      whereArgs: [idDevolucion],
    );
    expect(detalleDevolucion, hasLength(1));

    // El CHECK de tipo sigue vigente para datos nuevos.
    expect(
      () => dbV10.insert('Devoluciones', {
        'id_venta': idVenta,
        'fecha_hora': DateTime.now().toIso8601String(),
        'tipo': 'TipoInvalido',
        'motivo': 'x',
        'importe': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );

    // El código de barras sigue funcionando (no se rompió al migrar).
    final indices = await dbV10.rawQuery('PRAGMA index_list(Producto)');
    expect(indices.map((i) => i['name']), contains('idx_producto_codigo_barras'));

    await dbV10.close();
  });

  test('una base nueva (onCreate) ya incluye estado y las tablas de devoluciones', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('estado'));

    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Devoluciones','Detalle_Devolucion')",
    );
    expect(tablas, hasLength(2));

    await db.close();
  });
}
