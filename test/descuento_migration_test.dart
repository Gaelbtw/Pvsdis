// Prueba de migración v10 -> v11 (descuentos).
//
// Construye a mano el esquema tal como quedó en la versión 10 (con
// `estado`/Devoluciones pero sin ninguna columna de descuento), lo abre con
// la versión real de la app (11) para disparar `_onUpgrade`, y verifica que
// todo lo nuevo se agregue sin perder datos existentes ni romper lo ya
// migrado (código de barras, devoluciones).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV10 = 10;

Future<void> _crearEsquemaV10(Database db, int version) async {
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

  // Ventas tal como estaba ANTES de esta funcionalidad: con `estado` pero
  // sin ninguna columna de descuento.
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

  // configuracion tal como estaba antes: sin columnas de descuento.
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_descuento_migration_test');
    path = join(tempDir.path, 'v10.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v10 a v11 agregando columnas de descuento sin perder datos', () async {
    final dbV10 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV10,
        onCreate: _crearEsquemaV10,
      ),
    );

    final idProducto = await dbV10.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 20.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV10.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idVenta = await dbV10.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': null,
      'fecha': '2026-02-01T10:00:00',
      'total': 40.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });
    await dbV10.insert('Detalle_Venta', {
      'id_venta': idVenta,
      'id_producto': idProducto,
      'cantidad': 2,
      'precio': 20.0,
    });

    await dbV10.insert('configuracion', {'id': 1, 'nombre_negocio': 'Mi Negocio'});

    await dbV10.close();

    final helper = DatabaseHelper();
    final dbV11 = await helper.abrirEnRuta(path);

    // No se compara contra un número fijo: una funcionalidad futura puede
    // volver a subir la versión (ver el mismo ajuste ya aplicado en
    // devoluciones_migration_test.dart y database_migration_test.dart).
    expect(await dbV11.getVersion(), greaterThanOrEqualTo(11));

    // Ventas: columnas nuevas presentes, subtotal respaldado desde total.
    final columnasVentas = await dbV11.rawQuery('PRAGMA table_info(Ventas)');
    final nombresVentas = columnasVentas.map((c) => c['name']).toSet();
    expect(
      nombresVentas.containsAll([
        'subtotal',
        'descuento_total',
        'descuento_global_tipo',
        'descuento_global_valor',
        'descuento_motivo',
        'descuento_autorizado_por',
      ]),
      isTrue,
    );

    final ventaMigrada = await dbV11.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaMigrada.first['total'], 40.0); // total original intacto
    expect(ventaMigrada.first['subtotal'], 40.0); // respaldado = total (sin descuento previo)
    expect(ventaMigrada.first['descuento_total'], 0);

    // Detalle_Venta: precio_neto respaldado desde precio; precio original intacto.
    final columnasDetalle = await dbV11.rawQuery('PRAGMA table_info(Detalle_Venta)');
    final nombresDetalle = columnasDetalle.map((c) => c['name']).toSet();
    expect(
      nombresDetalle.containsAll(['descuento_tipo', 'descuento_valor', 'descuento_monto', 'precio_neto']),
      isTrue,
    );

    final detalleMigrado = await dbV11.query('Detalle_Venta', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(detalleMigrado.first['precio'], 20.0);
    expect(detalleMigrado.first['precio_neto'], 20.0);

    // configuracion: columnas nuevas con sus valores por defecto.
    final configMigrada = await dbV11.query('configuracion', where: 'id = 1');
    expect(configMigrada.first['descuento_maximo_porcentaje'], 20);
    expect(configMigrada.first['descuento_cajero_puede_aplicar'], 1);
    expect(configMigrada.first['descuento_cajero_requiere_autorizacion'], 1);

    // Lo migrado en versiones anteriores sigue intacto.
    final indices = await dbV11.rawQuery('PRAGMA index_list(Producto)');
    expect(indices.map((i) => i['name']), contains('idx_producto_codigo_barras'));

    final tablasDevoluciones = await dbV11.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Devoluciones','Detalle_Devolucion')",
    );
    expect(tablasDevoluciones, hasLength(2));

    await dbV11.close();
  });

  test('una base nueva (onCreate) ya incluye las columnas de descuento', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('subtotal'));

    final columnasDetalle = await db.rawQuery('PRAGMA table_info(Detalle_Venta)');
    expect(columnasDetalle.map((c) => c['name']), contains('precio_neto'));

    final columnasConfig = await db.rawQuery('PRAGMA table_info(configuracion)');
    expect(columnasConfig.map((c) => c['name']), contains('descuento_maximo_porcentaje'));

    await db.close();
  });
}
