// Prueba de migración v14 -> v15 (Apartados).
//
// Construye a mano el esquema tal como quedó en la versión 14 (con
// Promociones pero sin nada de Apartados ni `cantidad_reservada`), lo abre
// con la versión real de la app (15) para disparar `_onUpgrade`, y verifica
// que las tablas/columnas nuevas se agreguen sin perder datos existentes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionV14 = 14;

Future<void> _crearEsquemaV14(Database db, int version) async {
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

  await db.execute('''
    CREATE TABLE Promociones (
      id_promocion INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      tipo TEXT CHECK(tipo IN ('PORCENTAJE_PRODUCTO','MONTO_FIJO_PRODUCTO','NXY','DESCUENTO_CANTIDAD','COMBO')) NOT NULL,
      activo INTEGER NOT NULL DEFAULT 1,
      fecha_inicio TEXT,
      fecha_fin TEXT,
      prioridad INTEGER NOT NULL DEFAULT 0,
      combinable INTEGER NOT NULL DEFAULT 0,
      valor REAL,
      tipo_valor TEXT,
      cantidad_minima INTEGER,
      nx_lleva INTEGER,
      nx_paga INTEGER,
      precio_combo REAL,
      fecha_creacion TEXT NOT NULL,
      creado_por TEXT
    );
  ''');

  await db.execute('''
    CREATE TABLE Venta_Promociones (
      id_venta_promocion INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta INTEGER NOT NULL,
      id_promocion INTEGER,
      nombre_snapshot TEXT NOT NULL,
      tipo_snapshot TEXT NOT NULL,
      ahorro_total REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE,
      FOREIGN KEY (id_promocion) REFERENCES Promociones(id_promocion) ON DELETE SET NULL
    );
  ''');

  await db.execute('''
    CREATE TABLE Venta_Promociones_Detalle (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_venta_promocion INTEGER NOT NULL,
      id_detalleV INTEGER NOT NULL,
      cantidad_afectada INTEGER NOT NULL,
      ahorro REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (id_venta_promocion) REFERENCES Venta_Promociones(id_venta_promocion) ON DELETE CASCADE,
      FOREIGN KEY (id_detalleV) REFERENCES Detalle_Venta(id_detalleV) ON DELETE CASCADE
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_apartados_migration_test');
    path = join(tempDir.path, 'v14.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const tablasApartados = [
    'Apartados',
    'Detalle_Apartado',
    'Apartado_Promociones',
    'Apartado_Promociones_Detalle',
    'Apartado_Abonos',
    'Apartado_Abono_Pagos',
  ];

  test('migra una base v14 a v15 agregando Apartados sin perder datos', () async {
    final dbV14 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV14, onCreate: _crearEsquemaV14),
    );

    final idCliente = await dbV14.insert('Clientes', {'nombre': 'Cliente de prueba'});
    final idProducto = await dbV14.insert('Producto', {
      'nombre': 'Refresco',
      'descripcion': '',
      'precio': 20.0,
      'stock_minimo': 5,
      'estado': 'Activo',
    });
    await dbV14.insert('Inventario', {'id_producto': idProducto, 'cantidad': 40});

    final idUsuario = await dbV14.insert('Usuarios', {'nombre': 'Admin', 'contra': 'hash', 'rol': 'Admin'});

    final idVenta = await dbV14.insert('Ventas', {
      'id_cliente': idCliente,
      'id_usuario': idUsuario,
      'fecha': '2026-02-01T10:00:00',
      'total': 40.0,
      'subtotal': 40.0,
      'metodo_pago': 'efectivo',
      'estado': 'Activa',
    });

    await dbV14.close();

    final helper = DatabaseHelper();
    final dbV15 = await helper.abrirEnRuta(path);

    expect(await dbV15.getVersion(), greaterThanOrEqualTo(15));

    // Tablas nuevas presentes.
    final tablas = await dbV15.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN (${tablasApartados.map((_) => '?').join(',')})",
      tablasApartados,
    );
    expect(tablas.map((t) => t['name']).toSet(), tablasApartados.toSet());

    // Columnas nuevas presentes.
    final columnasInventario = await dbV15.rawQuery('PRAGMA table_info(Inventario)');
    expect(columnasInventario.map((c) => c['name']), contains('cantidad_reservada'));

    final columnasVentas = await dbV15.rawQuery('PRAGMA table_info(Ventas)');
    expect(columnasVentas.map((c) => c['name']), contains('id_apartado'));

    final columnasCajas = await dbV15.rawQuery('PRAGMA table_info(Cajas)');
    expect(
      columnasCajas.map((c) => c['name']),
      containsAll(['anticipos_efectivo', 'anticipos_tarjeta', 'anticipos_transferencia']),
    );

    // Índices nuevos presentes.
    final indicesApartados = await dbV15.rawQuery('PRAGMA index_list(Apartados)');
    expect(indicesApartados, isNotEmpty);

    // Los datos previos a la migración siguen intactos, y cantidad_reservada
    // arranca en 0 para el inventario existente.
    final inventarioMigrado =
        await dbV15.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
    expect(inventarioMigrado.first['cantidad'], 40);
    expect(inventarioMigrado.first['cantidad_reservada'], 0);

    final ventaMigrada = await dbV15.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(ventaMigrada.first['total'], 40.0);
    expect(ventaMigrada.first['id_apartado'], isNull);

    // Se puede insertar un apartado completo sin violar ninguna FK nueva.
    final idApartado = await dbV15.insert('Apartados', {
      'id_cliente': idCliente,
      'id_usuario': idUsuario,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'estado': 'Pendiente',
      'subtotal': 20.0,
      'total': 20.0,
    });
    final idDetalleApartado = await dbV15.insert('Detalle_Apartado', {
      'id_apartado': idApartado,
      'id_producto': idProducto,
      'cantidad': 1,
      'precio': 20.0,
      'precio_neto': 20.0,
    });
    expect(idDetalleApartado, greaterThan(0));

    final idCaja = await dbV15.insert('Cajas', {
      'id_usuario': idUsuario,
      'fecha_apertura': DateTime.now().toIso8601String(),
      'fondo_inicial': 100.0,
      'estado': 'Abierta',
    });
    final idAbono = await dbV15.insert('Apartado_Abonos', {
      'id_apartado': idApartado,
      'id_caja': idCaja,
      'fecha': DateTime.now().toIso8601String(),
      'tipo': 'Anticipo',
      'monto': 10.0,
    });
    await dbV15.insert('Apartado_Abono_Pagos', {
      'id_abono': idAbono,
      'metodo_pago': 'Efectivo',
      'monto': 10.0,
    });

    final abonos = await dbV15.query('Apartado_Abonos', where: 'id_apartado = ?', whereArgs: [idApartado]);
    expect(abonos, hasLength(1));

    await dbV15.close();
  });

  test('una base nueva (onCreate) ya incluye las tablas de Apartados', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN (${tablasApartados.map((_) => '?').join(',')})",
      tablasApartados,
    );
    expect(tablas.map((t) => t['name']).toSet(), tablasApartados.toSet());

    final columnasInventario = await db.rawQuery('PRAGMA table_info(Inventario)');
    expect(columnasInventario.map((c) => c['name']), contains('cantidad_reservada'));

    await db.close();
  });

  test('la migración es idempotente: abrir la base dos veces no falla ni duplica tablas', () async {
    final dbV14 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: _databaseVersionV14, onCreate: _crearEsquemaV14),
    );
    await dbV14.close();

    final helper = DatabaseHelper();
    final primeraApertura = await helper.abrirEnRuta(path);
    await primeraApertura.close();

    final segundaApertura = await helper.abrirEnRuta(path);

    final tablas = await segundaApertura.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = 'Apartados'",
    );
    expect(tablas, hasLength(1));

    await segundaApertura.close();
  });
}
