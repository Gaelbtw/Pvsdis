import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static Database? _database;
  static const _databaseName = 'pos.db';
  static bool _desktopFactoryInitialized = false;

  // Singleton una sola instancia, significa que solo habra una conexion a la base de datos para todo.

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  // En Windows, sqflite no tiene implementacion propia; se usa el backend FFI
  // (sqlite3 nativo) con la misma API de Database/openDatabase que Android.
  void _ensureDesktopFactory() {
    if (!Platform.isWindows || _desktopFactoryInitialized) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _desktopFactoryInitialized = true;
  }

  // Android usa el directorio privado de la app via sqflite.getDatabasesPath().
  // Windows no tiene ese concepto, asi que se usa el directorio de datos del
  // usuario que expone path_provider.
  Future<String> _getBaseDirectoryPath() async {
    if (Platform.isWindows) {
      final supportDir = await getApplicationSupportDirectory();
      return supportDir.path;
    }
    return getDatabasesPath();
  }

  Future<String> getDatabasePath() async {
    return join(await _getBaseDirectoryPath(), _databaseName);
  }

  Future<String> getBackupDirectoryPath() async {
    return join(await _getBaseDirectoryPath(), 'backups');
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // Inicializar la base de datos

  Future<Database> _initDB() async {
    _ensureDesktopFactory();
    final path = await getDatabasePath();

    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }


  // Crear todas las tablas

  Future<void> _onCreate(Database db, int version) async {
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
        FOREIGN KEY (id_proveedor) REFERENCES Proveedores(id_proveedor),
        FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario)
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
        FOREIGN KEY (id_compra) REFERENCES Compras(id_compra),
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto)
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
        FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente)
      );
    ''');

    await db.execute('''
      CREATE TABLE Detalle_Pedido (
        id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
        id_pedido INTEGER,
        id_producto INTEGER,
        cantidad INTEGER,
        precio REAL,
        
        FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido),
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto)
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
        FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente),
        FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario)
      );
    ''');

    await db.execute('''
      CREATE TABLE Detalle_Venta (
        id_detalleV INTEGER PRIMARY KEY AUTOINCREMENT,
        id_venta INTEGER,
        id_producto INTEGER,
        cantidad INTEGER,
        precio REAL,
        FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta),
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto)
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
        FOREIGN KEY (id_categoria) REFERENCES Categorias(id_categoria)
      );
    ''');

    await db.execute('''
      CREATE TABLE Inventario (
        id_inventario INTEGER PRIMARY KEY AUTOINCREMENT,
        id_producto INTEGER UNIQUE,
        cantidad INTEGER,
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto)
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
        stock_minimo INT
      );
    ''');



    await _ensureAuditoriasTable(db);

    // Insertar un usuario para probar 

    await db.execute('''
      INSERT INTO Usuarios (
        nombre,
        contra,
        rol
      ) VALUES ('Admin', '1234', 'Admin');
    ''');


    await _insertarAuditoriasDemo(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await _ensureAuditoriasTable(db);
      await _insertarAuditoriasDemo(db);
      await _ensureVentasMetodoPagoColumn(db);
    }
    await _ensureDetalleCompraCantidadColumn(db);
  }

  Future<void> _onOpen(Database db) async {
    await _ensureAuditoriasTable(db);
    await _ensureVentasMetodoPagoColumn(db);
    await _ensureDetalleCompraCantidadColumn(db);
    await _ensurePedidosDireccionColumn(db);
  }

  Future<void> _ensureVentasMetodoPagoColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toList();

    if (!columnNames.contains('metodo_pago')) {
      await db.execute("ALTER TABLE Ventas ADD COLUMN metodo_pago TEXT DEFAULT 'efectivo';");
    }
  }

  Future<void> _ensureDetalleCompraCantidadColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Detalle_Compra)');
    final columnNames = info.map((row) => row['name']?.toString()).toList();

    if (!columnNames.contains('cantidad')) {
      await db.execute(
        'ALTER TABLE Detalle_Compra ADD COLUMN cantidad INTEGER DEFAULT 1;',
      );
    }
  }

  Future<void> _ensurePedidosDireccionColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Pedidos)');
    final columnNames = info.map((row) => row['name']?.toString()).toList();

    if (!columnNames.contains('direccion')) {
      await db.execute('ALTER TABLE Pedidos ADD COLUMN direccion TEXT;');
    }
  }

  Future<void> _ensureAuditoriasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Auditorias (
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

  Future<void> _insertarAuditoriasDemo(Database db) async {
    final conteo = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM Auditorias'),
    ) ??
        0;

    if (conteo > 0) return;

    final auditoriasDemo = [
      {
        "fecha_hora": "2026-03-05T14:22:00",
        "usuario": "Gael",
        "tabla": "Productos",
        "accion": "EDIT",
        "id_registro": 1023,
        "descripcion": "Precio actualizado",
      },
      {
        "fecha_hora": "2026-03-05T13:10:00",
        "usuario": "Jesus",
        "tabla": "Ventas",
        "accion": "CREATE",
        "id_registro": 5562,
        "descripcion": "Nueva venta",
      },
      {
        "fecha_hora": "2026-03-05T12:45:00",
        "usuario": "Gael",
        "tabla": "Clientes",
        "accion": "DELETE",
        "id_registro": 221,
        "descripcion": "Cliente eliminado",
      },
    ];

    for (final auditoria in auditoriasDemo) {
      await db.insert('Auditorias', auditoria);
    }
  }
}
