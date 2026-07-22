// Prueba de migración v17 -> v18 (guid_sync + Sync_Outbox, fundación para
// sincronizar con EsqPOS).
//
// Construye a mano el esquema tal como quedó en la versión 17 (sin
// `guid_sync` en ninguna tabla, sin `Sync_Outbox`), lo abre con la versión
// real de la app (18) para disparar `_onUpgrade`, y verifica que: la
// columna se agregue a cada tabla sincronizable, las filas existentes
// queden con un GUID único (backfill), el índice único se cree, la tabla
// de outbox exista, y que reabrir la base no reasigne los GUIDs ya puestos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV17 = 17;

/// Copia exacta del bloque inicial de `_onCreate` en la versión 17 (antes de
/// agregar `guid_sync`/`Sync_Outbox`). Las tablas de Auditorías, Promociones,
/// Apartados y Abonos NO se crean aquí a propósito: en una v17 real ya
/// existirían (se crean también por `_onCreate`), pero para esta prueba no
/// hace falta reconstruirlas a mano porque la cadena de migración real las
/// vuelve a crear de forma idempotente (`CREATE TABLE IF NOT EXISTS`) antes
/// de llegar a `_ensureGuidSyncColumns` -- exactamente lo mismo que pasaría
/// al abrir una v17 real que sí las tuviera.
Future<void> _crearEsquemaV17(Database db, int version) async {
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
      forma_pago TEXT NOT NULL DEFAULT 'Contado',
      fecha_vencimiento TEXT,
      folio_factura TEXT,
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
      anticipos_efectivo REAL,
      anticipos_tarjeta REAL,
      anticipos_transferencia REAL,
      pagos_proveedores_efectivo REAL,
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
      id_apartado INTEGER,
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
      cantidad_reservada INTEGER NOT NULL DEFAULT 0,
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

  await db.execute('CREATE UNIQUE INDEX idx_producto_codigo_barras ON Producto(codigo_barras);');

  // `Auditorias` sí hace falta en la base, a diferencia de Devoluciones/
  // Promociones/Apartados/Abonos: a partir de la v5, `_ensureAuditoriasTable`
  // solo se llama sin condición en _onCreate/_onOpen, NO en _onUpgrade para
  // oldVersion >= 5 (queda gateada a `if (oldVersion < 5)`) -- y
  // `_ensureAuditoriasContextColumns` (que sí es incondicional en
  // _onUpgrade) hace ALTER TABLE sobre ella, así que necesita existir desde
  // el arranque de esta prueba o la migración real fallaría al abrir.
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_guid_sync_migration_test');
    path = join(tempDir.path, 'v17.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v17 a v18 agregando guid_sync y backfilleando filas existentes', () async {
    final dbV17 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV17, onCreate: _crearEsquemaV17),
    );

    final idCategoria = await dbV17.insert('Categorias', {'nombre': 'Bebidas'});
    final idProducto = await dbV17.insert('Producto', {
      'nombre': 'Refresco',
      'precio': 20.0,
      'id_categoria': idCategoria,
    });
    await dbV17.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});
    final idCliente = await dbV17.insert('Clientes', {'nombre': 'Cliente Uno'});
    final idUsuario = await dbV17.insert('Usuarios', {
      'nombre': 'Cajero',
      'contra': 'hash-lo-que-sea',
      'rol': 'Cajero',
    });
    final idCaja = await dbV17.insert('Cajas', {
      'id_usuario': idUsuario,
      'fecha_apertura': '2026-01-01T08:00:00',
      'fondo_inicial': 500.0,
    });
    final idVenta1 = await dbV17.insert('Ventas', {
      'id_cliente': idCliente,
      'id_usuario': idUsuario,
      'id_caja': idCaja,
      'fecha': '2026-01-01T10:00:00',
      'total': 20.0,
      'subtotal': 20.0,
    });
    final idVenta2 = await dbV17.insert('Ventas', {
      'id_cliente': null,
      'id_usuario': idUsuario,
      'id_caja': idCaja,
      'fecha': '2026-01-02T11:00:00',
      'total': 40.0,
      'subtotal': 40.0,
    });
    await dbV17.insert('Detalle_Venta', {
      'id_venta': idVenta1,
      'id_producto': idProducto,
      'cantidad': 1,
      'precio': 20.0,
      'precio_neto': 20.0,
    });
    await dbV17.insert('Venta_Pagos', {'id_venta': idVenta1, 'metodo_pago': 'efectivo', 'monto': 20.0});

    await dbV17.close();

    final helper = DatabaseHelper();
    var db = await helper.abrirEnRuta(path);

    expect(await db.getVersion(), greaterThanOrEqualTo(18));

    // guid_sync existe en cada tabla sincronizable...
    for (final tabla in [
      'Categorias',
      'Producto',
      'Clientes',
      'Proveedores',
      'Inventario',
      'Ventas',
      'Detalle_Venta',
      'Venta_Pagos',
      'Cajas',
      'Promociones',
      'Venta_Promociones',
    ]) {
      final columnas = await db.rawQuery('PRAGMA table_info($tabla)');
      expect(columnas.map((c) => c['name']), contains('guid_sync'), reason: 'falta guid_sync en $tabla');
    }

    // ...y las filas que ya existían quedaron backfilleadas con un valor
    // presente y distinto entre sí (nunca el mismo GUID para dos filas).
    final categoriaMigrada = await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idCategoria]);
    final productoMigrado = await db.query('Producto', where: 'id_producto = ?', whereArgs: [idProducto]);
    final clienteMigrado = await db.query('Clientes', where: 'id_cliente = ?', whereArgs: [idCliente]);
    final venta1Migrada = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta1]);
    final venta2Migrada = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta2]);

    final guids = <String?>{
      categoriaMigrada.first['guid_sync'] as String?,
      productoMigrado.first['guid_sync'] as String?,
      clienteMigrado.first['guid_sync'] as String?,
      venta1Migrada.first['guid_sync'] as String?,
      venta2Migrada.first['guid_sync'] as String?,
    };

    expect(guids, everyElement(isNotNull));
    expect(guids, hasLength(5)); // sin duplicados

    // El índice único por tabla existe.
    final indicesProducto = await db.rawQuery('PRAGMA index_list(Producto)');
    expect(indicesProducto.map((i) => i['name']), contains('idx_producto_guid_sync'));
    final indicesVentas = await db.rawQuery('PRAGMA index_list(Ventas)');
    expect(indicesVentas.map((i) => i['name']), contains('idx_ventas_guid_sync'));

    // Sync_Outbox existe con sus columnas.
    final tablasOutbox = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Sync_Outbox'",
    );
    expect(tablasOutbox, hasLength(1));
    final columnasOutbox = await db.rawQuery('PRAGMA table_info(Sync_Outbox)');
    expect(
      columnasOutbox.map((c) => c['name']),
      containsAll(['entidad', 'guid_registro', 'operacion', 'datos_json', 'fecha_creacion', 'intentos']),
    );

    await db.close();

    // Reabrir (dispara _onOpen otra vez) no debe reasignar los GUIDs ya puestos.
    db = await helper.abrirEnRuta(path);
    final venta1TrasReapertura = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta1]);
    expect(venta1TrasReapertura.first['guid_sync'], venta1Migrada.first['guid_sync']);

    await db.close();
  });

  test('una base nueva (onCreate) ya incluye guid_sync y Sync_Outbox', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final columnasProducto = await db.rawQuery('PRAGMA table_info(Producto)');
    expect(columnasProducto.map((c) => c['name']), contains('guid_sync'));

    final tablasOutbox = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Sync_Outbox'",
    );
    expect(tablasOutbox, hasLength(1));

    await db.close();
  });

  test('dos filas nuevas creadas en la misma sesión no reciben el mismo guid_sync tras backfillear', () async {
    final dbV17 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV17, onCreate: _crearEsquemaV17),
    );
    final idA = await dbV17.insert('Categorias', {'nombre': 'A'});
    final idB = await dbV17.insert('Categorias', {'nombre': 'B'});
    await dbV17.close();

    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final categoriaA = await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idA]);
    final categoriaB = await db.query('Categorias', where: 'id_categoria = ?', whereArgs: [idB]);

    expect(categoriaA.first['guid_sync'], isNotNull);
    expect(categoriaB.first['guid_sync'], isNotNull);
    expect(categoriaA.first['guid_sync'], isNot(categoriaB.first['guid_sync']));

    await db.close();
  });
}
