// Prueba de migración (hasta) v19 (Fase 3: bitácoras de sincronización).
//
// Agrega 3 tablas nuevas sin datos legacy que migrar (`Movimiento_Inventario`,
// `Movimiento_Caja`, `Corte_Caja` -- ver `_ensureBitacoraSyncTables` en
// `database_helper.dart`) más 2 tablas de estado propio del motor de sync
// (`Sync_Config`, `Sync_Pull_Estado` -- ver `_ensureSyncConfigYPullEstadoTables`).
//
// La base que se construye a mano parte del mismo esquema v17 que usa
// `guid_sync_migration_test.dart` (copiado tal cual, mismo criterio
// documentado ahí: Auditorías/Promociones/Apartados/Abonos no hace falta
// crearlas a mano porque la cadena real de migración las recrea de forma
// idempotente antes de llegar a los métodos que esta prueba ejercita). No es
// una réplica perfecta de una v18 real (le faltan `guid_sync`/`Sync_Outbox`,
// que en una v18 real ya existirían), pero como todos los `_ensure*` de
// `_onUpgrade` son idempotentes, migrar desde v17 hasta v19 en una sola
// pasada ejercita exactamente los mismos métodos (incluidos los nuevos de
// esta fase) que migrar desde una v18 real -- el mismo escenario que vive un
// dispositivo que se saltó una actualización intermedia.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV17 = 17;

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
    tempDir = Directory.systemTemp.createTempSync('pvapp_sync_bitacoras_migration_test');
    path = join(tempDir.path, 'v17.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra una base v17 a v19 agregando las bitácoras de sync y Sync_Config/Sync_Pull_Estado', () async {
    final dbV18 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV17, onCreate: _crearEsquemaV17),
    );

    final idUsuario = await dbV18.insert('Usuarios', {
      'nombre': 'Cajero',
      'contra': 'hash-lo-que-sea',
      'rol': 'Cajero',
    });
    final idProducto = await dbV18.insert('Producto', {'nombre': 'Refresco', 'precio': 20.0});
    final idCaja = await dbV18.insert('Cajas', {
      'id_usuario': idUsuario,
      'fecha_apertura': '2026-01-01T08:00:00',
      'fondo_inicial': 500.0,
    });

    await dbV18.close();

    final helper = DatabaseHelper();
    var db = await helper.abrirEnRuta(path);

    expect(await db.getVersion(), greaterThanOrEqualTo(19));

    // Las 3 bitácoras existen con guid_sync y sus columnas propias.
    final columnasMovInv = await db.rawQuery('PRAGMA table_info(Movimiento_Inventario)');
    expect(
      columnasMovInv.map((c) => c['name']),
      containsAll([
        'guid_sync', 'id_producto', 'tipo_movimiento', 'cantidad',
        'cantidad_anterior', 'cantidad_nueva', 'motivo', 'referencia_tipo',
        'referencia_id', 'id_usuario', 'fecha',
      ]),
    );

    final columnasMovCaja = await db.rawQuery('PRAGMA table_info(Movimiento_Caja)');
    expect(
      columnasMovCaja.map((c) => c['name']),
      containsAll([
        'guid_sync', 'id_caja', 'tipo_movimiento', 'monto', 'concepto',
        'fecha', 'id_venta_referencia', 'id_usuario',
      ]),
    );

    final columnasCorte = await db.rawQuery('PRAGMA table_info(Corte_Caja)');
    expect(
      columnasCorte.map((c) => c['name']),
      containsAll([
        'guid_sync', 'id_caja', 'total_efectivo_sistema', 'total_tarjeta_sistema',
        'total_transferencia_sistema', 'total_efectivo_contado', 'diferencia',
        'fecha_corte', 'id_usuario',
      ]),
    );

    // Índice único de guid_sync en cada bitácora.
    for (final tabla in ['Movimiento_Inventario', 'Movimiento_Caja', 'Corte_Caja']) {
      final indices = await db.rawQuery('PRAGMA index_list($tabla)');
      expect(
        indices.map((i) => i['name']),
        contains('idx_${tabla.toLowerCase()}_guid_sync'),
        reason: 'falta el índice único de guid_sync en $tabla',
      );
    }

    // Sync_Config y Sync_Pull_Estado existen con sus columnas.
    final tablasNuevas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Sync_Config','Sync_Pull_Estado')",
    );
    expect(tablasNuevas.map((t) => t['name']), containsAll(['Sync_Config', 'Sync_Pull_Estado']));

    final columnasSyncConfig = await db.rawQuery('PRAGMA table_info(Sync_Config)');
    expect(
      columnasSyncConfig.map((c) => c['name']),
      containsAll(['id', 'sucursal_id', 'sucursal_nombre', 'actualizado_en']),
    );

    final columnasPullEstado = await db.rawQuery('PRAGMA table_info(Sync_Pull_Estado)');
    expect(columnasPullEstado.map((c) => c['name']), containsAll(['entidad', 'ultima_fecha_modificacion']));

    // DatabaseHelper.tablasSincronizables refleja las 3 bitácoras nuevas.
    expect(DatabaseHelper.tablasSincronizables['Movimiento_Inventario'], 'id_movimiento');
    expect(DatabaseHelper.tablasSincronizables['Movimiento_Caja'], 'id_movimiento_caja');
    expect(DatabaseHelper.tablasSincronizables['Corte_Caja'], 'id_corte');

    // insertarConGuidSync funciona igual que en las tablas preexistentes.
    final idMovimiento = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Inventario', {
      'id_producto': idProducto,
      'tipo_movimiento': 'AjustePositivo',
      'cantidad': 10,
      'cantidad_anterior': 0,
      'cantidad_nueva': 10,
      'fecha': '2026-01-01T10:00:00',
    });
    final movimiento = await db.query('Movimiento_Inventario', where: 'id_movimiento = ?', whereArgs: [idMovimiento]);
    expect(movimiento.first['guid_sync'], isNotNull);

    // No se pierde nada de las tablas preexistentes que sí traían datos.
    final cajaMigrada = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
    expect(cajaMigrada.first['guid_sync'], isNotNull);

    await db.close();

    // Reabrir no debe reasignar los guid_sync ya puestos ni fallar por
    // CREATE TABLE IF NOT EXISTS repetido.
    db = await helper.abrirEnRuta(path);
    final movimientoTrasReapertura =
        await db.query('Movimiento_Inventario', where: 'id_movimiento = ?', whereArgs: [idMovimiento]);
    expect(movimientoTrasReapertura.first['guid_sync'], movimiento.first['guid_sync']);

    await db.close();
  });

  test('una base nueva (onCreate) ya incluye las bitácoras de sync y Sync_Config/Sync_Pull_Estado', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    for (final tabla in ['Movimiento_Inventario', 'Movimiento_Caja', 'Corte_Caja', 'Sync_Config', 'Sync_Pull_Estado']) {
      final tablas = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name = '$tabla'");
      expect(tablas, hasLength(1), reason: 'falta la tabla $tabla en una instalación nueva');
    }

    await db.close();
  });

  test('dos movimientos de inventario creados en la misma sesión no reciben el mismo guid_sync', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final idProducto = await db.insert('Producto', {'nombre': 'Agua', 'precio': 15.0});

    final idA = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Inventario', {
      'id_producto': idProducto,
      'tipo_movimiento': 'AjustePositivo',
      'cantidad': 5,
      'cantidad_anterior': 0,
      'cantidad_nueva': 5,
      'fecha': '2026-01-01T10:00:00',
    });
    final idB = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Inventario', {
      'id_producto': idProducto,
      'tipo_movimiento': 'AjustePositivo',
      'cantidad': 3,
      'cantidad_anterior': 5,
      'cantidad_nueva': 8,
      'fecha': '2026-01-01T11:00:00',
    });

    final movA = await db.query('Movimiento_Inventario', where: 'id_movimiento = ?', whereArgs: [idA]);
    final movB = await db.query('Movimiento_Inventario', where: 'id_movimiento = ?', whereArgs: [idB]);

    expect(movA.first['guid_sync'], isNotNull);
    expect(movB.first['guid_sync'], isNotNull);
    expect(movA.first['guid_sync'], isNot(movB.first['guid_sync']));

    await db.close();
  });
}
