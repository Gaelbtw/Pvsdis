// Prueba de migración v12 -> v13 (caja persistente).
//
// Construye a mano el esquema tal como quedó en la versión 12 (con
// Venta_Pagos y Ventas.cambio, pero sin Cajas ni id_caja), lo abre con la
// versión real de la app (13) para disparar `_onUpgrade`, y verifica que la
// tabla `Cajas` se cree, que `Ventas.id_caja`/`Devoluciones.id_caja` existan
// y queden `NULL` en filas históricas (no se inventa una caja retroactiva),
// y que reabrir la base no falle ni duplique nada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV12 = 12;

Future<void> _crearEsquemaV12(Database db, int version) async {
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

  // Ventas tal como estaba ANTES de caja persistente: con `cambio` pero sin
  // `id_caja`.
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
      cambio REAL DEFAULT 0,
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
    CREATE TABLE Venta_Pagos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER NOT NULL,
      metodo_pago TEXT NOT NULL,
      monto REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE
    );
  ''');

  // Devoluciones tal como estaba ANTES de caja persistente: sin `id_caja`.
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_caja_migration_test');
    path = join(tempDir.path, 'v12.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v12 a v13 creando Cajas y agregando id_caja sin tocar el historial', () async {
    final dbV12 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionV12,
        onCreate: _crearEsquemaV12,
      ),
    );

    final idUsuario = await dbV12.insert('Usuarios', {
      'nombre': 'Cajero histórico',
      'contra': 'hash',
      'rol': 'Cajero',
    });

    final idProducto = await dbV12.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 20.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV12.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idVenta = await dbV12.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': idUsuario,
      'fecha': '2026-02-01T10:00:00',
      'total': 40.0,
      'subtotal': 40.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
      'cambio': 0,
    });
    await dbV12.insert('Venta_Pagos', {'id_venta': idVenta, 'metodo_pago': 'efectivo', 'monto': 40.0});

    final idDevolucion = await dbV12.insert('Devoluciones', {
      'id_venta': idVenta,
      'id_usuario': idUsuario,
      'fecha_hora': '2026-02-02T10:00:00',
      'tipo': 'Parcial',
      'motivo': 'Histórica',
      'importe': 20.0,
    });

    await dbV12.close();

    final helper = DatabaseHelper();
    var db = await helper.abrirEnRuta(path);

    // No se compara contra un número fijo (mismo criterio que las demás
    // pruebas de migración).
    expect(await db.getVersion(), greaterThanOrEqualTo(13));

    // Tabla Cajas existe, con su índice de "¿usuario ya tiene caja abierta?".
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Cajas'",
    );
    expect(tablas, hasLength(1));

    final indices = await db.rawQuery('PRAGMA index_list(Cajas)');
    expect(indices.map((i) => i['name']), contains('idx_cajas_id_usuario_estado'));

    // Ventas.id_caja y Devoluciones.id_caja existen...
    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('id_caja'));

    final columnasDevoluciones = await db.rawQuery('PRAGMA table_info(Devoluciones)');
    expect(columnasDevoluciones.map((c) => c['name']), contains('id_caja'));

    // ...y en las filas históricas quedan NULL: no se inventa una caja
    // retroactiva para ventas/devoluciones que ya existían.
    final ventaMigrada = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaMigrada.first['id_caja'], isNull);

    final devolucionMigrada =
        await db.query('Devoluciones', where: 'id_devolucion = ?', whereArgs: [idDevolucion]);
    expect(devolucionMigrada.first['id_caja'], isNull);

    // No se perdió nada de lo ya migrado en v12.
    final pagos = await db.query('Venta_Pagos', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(pagos, hasLength(1));

    await db.close();

    // Reabrir (dispara _onOpen otra vez) no debe fallar ni duplicar nada.
    db = await helper.abrirEnRuta(path);
    final cajasTrasReapertura = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Cajas'",
    );
    expect(cajasTrasReapertura, hasLength(1));

    await db.close();
  });

  test('una base nueva (onCreate) ya incluye Cajas, Ventas.id_caja y Devoluciones.id_caja', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Cajas'",
    );
    expect(tablas, hasLength(1));

    final columnasVentas = await db.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('id_caja'));

    final columnasDevoluciones = await db.rawQuery('PRAGMA table_info(Devoluciones)');
    expect(columnasDevoluciones.map((c) => c['name']), contains('id_caja'));

    await db.close();
  });
}
