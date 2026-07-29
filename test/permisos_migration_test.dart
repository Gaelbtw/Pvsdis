// Prueba de migración v19 -> v20 (roles + matriz de permisos + PIN).
//
// Construye a mano un esquema anterior (Usuarios con CHECK viejo
// `IN ('Cajero','Admin')` y sin columna `pin`, sin tabla `Rol_Permisos`),
// lo abre con la versión real de la app para disparar `_onUpgrade`, y
// verifica que:
//   - `Usuarios` se reconstruye admitiendo el rol 'Supervisor' y con `pin`,
//   - los usuarios existentes se conservan (id, nombre, contra, rol),
//   - las tablas hijas (Cajas, Ventas) conservan sus filas y su FOREIGN KEY
//     a `Usuarios` sigue íntegra (no quedó apuntando a la tabla temporal),
//   - existe la tabla `Rol_Permisos`,
//   - reabrir la base no vuelve a reconstruir ni pierde datos.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';

const _databaseVersionPrevio = 17;

/// Esquema anterior (rol con CHECK 'Cajero'/'Admin', sin `pin` ni
/// `Rol_Permisos`) con las tablas hijas que referencian `Usuarios`, para
/// probar que la reconstrucción no rompe sus FOREIGN KEY.
Future<void> _crearEsquemaPrevio(Database db, int version) async {
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

Future<Set<String?>> _columnas(Database db, String tabla) async {
  final info = await db.rawQuery('PRAGMA table_info($tabla)');
  return info.map((c) => c['name']?.toString()).toSet();
}

Future<bool> _tablaExiste(Database db, String nombre) async {
  final filas = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [nombre],
  );
  return filas.isNotEmpty;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pvapp_permisos_migration');
    path = join(tempDir.path, 'previo.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('migra agregando Supervisor + pin + Rol_Permisos sin perder datos ni romper FKs', () async {
    // 1. Sembrar una base como una instalación real anterior, con usuarios y
    //    filas hijas que referencian a Usuarios.
    final dbPrevio = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _databaseVersionPrevio,
        onCreate: _crearEsquemaPrevio,
      ),
    );

    final idAdmin = await dbPrevio.insert('Usuarios', {
      'nombre': 'Jefa',
      'contra': r'$2b$10$abcdefghijklmnopqrstuv',
      'rol': 'Admin',
    });
    final idCajero = await dbPrevio.insert('Usuarios', {
      'nombre': 'Cajero Uno',
      'contra': r'$2b$10$zyxwvutsrqponmlkjihgfe',
      'rol': 'Cajero',
    });
    final idCaja = await dbPrevio.insert('Cajas', {
      'id_usuario': idCajero,
      'fecha_apertura': '2026-01-01T08:00:00.000',
      'fondo_inicial': 500.0,
    });
    final idVenta = await dbPrevio.insert('Ventas', {
      'id_usuario': idCajero,
      'id_caja': idCaja,
      'fecha': '2026-01-01',
      'total': 99.5,
    });
    await dbPrevio.close();

    // 2. Abrir con la versión real de la app: dispara _onUpgrade.
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(path);

    expect(await db.getVersion(), greaterThanOrEqualTo(20));

    // 3. Usuarios ahora tiene la columna pin.
    expect(await _columnas(db, 'Usuarios'), contains('pin'));

    // 4. Los usuarios existentes se conservan intactos.
    final admin = await db.query('Usuarios', where: 'id_usuario = ?', whereArgs: [idAdmin]);
    expect(admin, hasLength(1));
    expect(admin.first['nombre'], 'Jefa');
    expect(admin.first['rol'], 'Admin');
    expect(admin.first['contra'], r'$2b$10$abcdefghijklmnopqrstuv');
    expect(admin.first['pin'], isNull);

    // 5. Las filas hijas siguen ahí y apuntan al mismo usuario.
    final caja = await db.query('Cajas', where: 'id_caja = ?', whereArgs: [idCaja]);
    expect(caja, hasLength(1));
    expect(caja.first['id_usuario'], idCajero);
    final venta = await db.query('Ventas', where: 'id_venta = ?', whereArgs: [idVenta]);
    expect(venta, hasLength(1));
    expect(venta.first['id_usuario'], idCajero);

    // 6. Ahora se puede crear un Supervisor (el CHECK viejo lo impedía).
    final idSsuper = await db.insert('Usuarios', {
      'nombre': 'Supervisora',
      'contra': r'$2b$10$supervisorsupervisorxx',
      'rol': 'Supervisor',
      'pin': '4321',
    });
    expect(idSsuper, greaterThan(0));

    // 7. La FOREIGN KEY a Usuarios sigue viva tras la reconstrucción: una venta
    //    con un id_usuario inexistente debe rechazarse (prueba que las hijas se
    //    religaron a la nueva tabla, no a la temporal ya eliminada).
    expect(
      () => db.insert('Ventas', {
        'id_usuario': 999999,
        'fecha': '2026-01-02',
        'total': 1.0,
      }),
      throwsA(isA<DatabaseException>()),
    );

    // 8. La tabla de la matriz de permisos existe.
    expect(await _tablaExiste(db, 'Rol_Permisos'), isTrue);

    await db.close();

    // 9. Reabrir no reconstruye de nuevo ni pierde datos (idempotente): el
    //    Supervisor y su pin siguen ahí.
    final db2 = await helper.abrirEnRuta(path);
    final superReabierto = await db2.query('Usuarios', where: 'id_usuario = ?', whereArgs: [idSsuper]);
    expect(superReabierto, hasLength(1));
    expect(superReabierto.first['rol'], 'Supervisor');
    expect(superReabierto.first['pin'], '4321');
    await db2.close();
  });

  test('una base nueva (onCreate) ya trae pin, Rol_Permisos y admite Supervisor', () async {
    final helper = DatabaseHelper();
    final db = await helper.abrirEnRuta(join(tempDir.path, 'nueva.db'));

    expect(await _columnas(db, 'Usuarios'), contains('pin'));
    expect(await _tablaExiste(db, 'Rol_Permisos'), isTrue);

    final id = await db.insert('Usuarios', {
      'nombre': 'Supervisora',
      'contra': r'$2b$10$supervisorsupervisorxx',
      'rol': 'Supervisor',
      'pin': '1234',
    });
    expect(id, greaterThan(0));

    await db.close();
  });
}
