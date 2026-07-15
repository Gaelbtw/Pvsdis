// Prueba de migración v8 -> v9 (código de barras).
//
// Construye a mano el esquema tal como quedó en la versión 8 (sin
// `codigo_barras`), lo abre con la versión real de la app (9) para
// disparar `_onUpgrade`, y verifica que la columna y el índice único se
// agreguen sin perder datos existentes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV8 = 8;

Future<void> _crearEsquemaV8(Database db, int version) async {
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

  // Esquema de Producto tal como estaba ANTES de esta funcionalidad: sin
  // `codigo_barras`. Es justo lo que la migración v8 -> v9 debe corregir.
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
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_migration_test');
    path = join(tempDir.path, 'v8.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v8 a v9 agregando codigo_barras sin perder datos', () async {
    // 1. Sembrar una base como si fuera una instalación real en v8.
    final dbV8 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV8,
        onCreate: _crearEsquemaV8,
      ),
    );

    final idProducto = await dbV8.insert('Producto', {
      'nombre': 'Refresco 600ml',
      'descripcion': 'Bebida',
      'precio': 18.5,
      'precio_compra': 12.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV8.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});
    await dbV8.close();

    // 2. Abrir con la versión real de la app: debe disparar _onUpgrade.
    final helper = DatabaseHelper();
    final dbV9 = await helper.abrirEnRuta(path);

    // No se compara contra un número fijo: la versión real sigue subiendo
    // con cada nueva funcionalidad (ver devoluciones_migration_test.dart).
    // Lo que importa aquí es que la migración v8 -> v9+ sí se haya aplicado.
    expect(await dbV9.getVersion(), greaterThanOrEqualTo(9));

    // 3. La columna nueva debe existir.
    final columnas = await dbV9.rawQuery('PRAGMA table_info(Producto)');
    final nombresColumnas = columnas.map((c) => c['name']).toSet();
    expect(nombresColumnas, contains('codigo_barras'));

    // 4. El producto existente se conserva, con codigo_barras en NULL.
    final filas = await dbV9.query(
      'Producto',
      where: 'id_producto = ?',
      whereArgs: [idProducto],
    );
    expect(filas, hasLength(1));
    expect(filas.first['nombre'], 'Refresco 600ml');
    expect(filas.first['codigo_barras'], isNull);

    // 5. El índice único debe existir y permitir múltiples NULL...
    await dbV9.insert('Producto', {
      'nombre': 'Producto sin código A',
      'descripcion': '',
      'precio': 1,
      'stock_minimo': 0,
      'estado': 'Activo',
      'codigo_barras': null,
    });
    await dbV9.insert('Producto', {
      'nombre': 'Producto sin código B',
      'descripcion': '',
      'precio': 1,
      'stock_minimo': 0,
      'estado': 'Activo',
      'codigo_barras': null,
    });

    // ...pero rechazar un código de barras duplicado.
    await dbV9.insert('Producto', {
      'nombre': 'Con código',
      'descripcion': '',
      'precio': 1,
      'stock_minimo': 0,
      'estado': 'Activo',
      'codigo_barras': '7501234567890',
    });

    expect(
      () => dbV9.insert('Producto', {
        'nombre': 'Otro con el mismo código',
        'descripcion': '',
        'precio': 1,
        'stock_minimo': 0,
        'estado': 'Activo',
        'codigo_barras': '7501234567890',
      }),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.isUniqueConstraintError(),
          'isUniqueConstraintError',
          true,
        ),
      ),
    );

    await dbV9.close();
  });

  test('una base nueva (onCreate) ya incluye codigo_barras y el índice único', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final columnas = await db.rawQuery('PRAGMA table_info(Producto)');
    expect(columnas.map((c) => c['name']), contains('codigo_barras'));

    await db.insert('Producto', {
      'nombre': 'A',
      'descripcion': '',
      'precio': 1,
      'stock_minimo': 0,
      'estado': 'Activo',
      'codigo_barras': 'ABC123',
    });

    expect(
      () => db.insert('Producto', {
        'nombre': 'B',
        'descripcion': '',
        'precio': 1,
        'stock_minimo': 0,
        'estado': 'Activo',
        'codigo_barras': 'ABC123',
      }),
      throwsA(isA<DatabaseException>()),
    );

    await db.close();
  });
}
