import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/password_hasher.dart';
import '../utils/guid_generator.dart';
import '../utils/pagos_mixtos.dart';

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

  static const _databaseVersion = 18;

  Future<Database> _initDB() async {
    final path = await getDatabasePath();
    await _migrarDesdeCarpetaAnteriorSiAplica(path);
    return abrirConRespaldoEnRuta(path);
  }

  /// Respalda (si hace falta) y abre/crea/migra la base de datos en [path]
  /// usando el esquema real de la app. Extraído de [_initDB] para que las
  /// pruebas automatizadas puedan ejercer exactamente la misma secuencia
  /// contra un archivo temporal, sin depender de `path_provider` (que no
  /// funciona en `flutter test`).
  @visibleForTesting
  Future<Database> abrirConRespaldoEnRuta(String path) async {
    // Debe inicializarse antes que cualquier operación de base de datos en
    // esta ruta: _respaldarAntesDeMigrarSiNecesario ya abre la base (de
    // solo lectura) para leer su versión, y en Windows eso también
    // requiere el backend FFI.
    _ensureDesktopFactory();
    await _respaldarAntesDeMigrarSiNecesario(path);
    return abrirEnRuta(path);
  }

  /// Abre (o crea/migra) la base de datos en [path] usando el esquema real
  /// de la app, sin pasar por el respaldo previo (usado también desde
  /// [abrirConRespaldoEnRuta]).
  @visibleForTesting
  Future<Database> abrirEnRuta(String path) async {
    _ensureDesktopFactory();
    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// Permite a las pruebas automatizadas redirigir el singleton hacia una
  /// base de datos temporal (por ejemplo, la devuelta por [abrirEnRuta])
  /// para poder probar `ProductoController` y otros controladores tal como
  /// se usan en producción.
  @visibleForTesting
  static void setTestDatabase(Database? db) {
    _database = db;
  }

  /// En Windows, path_provider ubica la carpeta de datos según el
  /// "ProductName" compilado en el ejecutable, no según el nombre del
  /// paquete Dart. Si el ejecutable se renombra (como ocurrió al quitar el
  /// branding del negocio original del proyecto), una instalación que ya
  /// tenía datos guardados bajo el nombre anterior dejaría de encontrarlos
  /// y la app arrancaría como si fuera nueva. Este chequeo, de una sola
  /// vez, copia la base de datos existente a la carpeta nueva antes de
  /// abrirla. No aplica si la carpeta nueva ya tiene datos, y no borra
  /// nada de la carpeta anterior.
  Future<void> _migrarDesdeCarpetaAnteriorSiAplica(String path) async {
    if (!Platform.isWindows) return;
    if (await File(path).exists()) return;

    try {
      final baseDir = Directory(await _getBaseDirectoryPath());
      final directorioPadre = baseDir.parent;
      const nombresAnteriores = ['punto_de_venta_lomita'];

      for (final nombre in nombresAnteriores) {
        final anterior = File(join(directorioPadre.path, nombre, _databaseName));
        if (await anterior.exists()) {
          await Directory(path).parent.create(recursive: true);
          await anterior.copy(path);
          return;
        }
      }
    } catch (_) {
      // Best-effort: si la migración de compatibilidad falla, se procede
      // como instalación nueva en vez de bloquear la apertura de la app.
    }
  }

  /// Se ejecuta en cada apertura de conexión, antes de onCreate/onUpgrade y
  /// antes de que sqflite envuelva esa creación/migración en su propia
  /// transacción implícita. Aquí se deja DESACTIVADA a propósito: SQLite no
  /// permite cambiar PRAGMA foreign_keys dentro de una transacción activa,
  /// y la migración de abajo necesita reconstruir tablas sin que la validación
  /// de FK estorbe a mitad del proceso. Se reactiva en _onOpen, que corre
  /// después de que esa transacción ya se confirmó.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
  }

  /// Antes de aplicar una migración de esquema pendiente (que reconstruye
  /// tablas para corregir sus FOREIGN KEY), se respalda el archivo completo.
  /// Si algo saliera mal a mitad de la migración, el usuario no pierde su
  /// base de datos. No hace nada en una instalación nueva ni si ya está
  /// actualizada.
  Future<void> _respaldarAntesDeMigrarSiNecesario(String path) async {
    final archivo = File(path);
    if (!await archivo.exists()) return;

    int versionActual;
    try {
      final dbSoloLectura = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      versionActual = await dbSoloLectura.getVersion();
      await dbSoloLectura.close();
    } catch (_) {
      return;
    }

    if (versionActual >= _databaseVersion) return;

    try {
      final backupDir = Directory(await getBackupDirectoryPath());
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupPath = join(
        backupDir.path,
        '${timestamp}_pre_migracion_v$_databaseVersion.db',
      );
      await archivo.copy(backupPath);
    } catch (_) {
      // Respaldo best-effort: si falla (ej. disco lleno), no se bloquea la
      // apertura de la app por esto.
    }
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



    await _ensureAuditoriasTable(db);
    await _ensurePromocionesTables(db);
    await _ensureInventarioCantidadReservadaColumn(db);
    await _ensureApartadosTables(db);
    await _ensureVentasIdApartadoColumn(db);
    await _ensureCajasAnticiposColumns(db);
    await _ensureAuditoriasContextColumns(db);
    await _ensureComprasCreditoColumns(db);
    await _ensureAbonosTables(db);
    await _ensureCajasPagosProveedoresColumn(db);
    await _backfillAbonosComprasExistentes(db);
    await _ensureGuidSyncColumns(db);
    await _ensureSyncOutboxTable(db);
    await _crearIndices(db);

    // No se siembra ningún usuario por defecto: la primera cuenta de
    // administrador se crea desde SetupAdminView en el primer arranque.

    await _insertarAuditoriasDemo(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await _ensureAuditoriasTable(db);
      await _insertarAuditoriasDemo(db);
    }
    if (oldVersion < 6) {
      await _hashearContrasenasExistentes(db);
    }

    // Estas columnas/tablas se fueron agregando de forma incremental en
    // versiones anteriores (fuera del ciclo formal de versión, o antes de
    // llegar al _crearIndices de más abajo). Deben existir antes de
    // reconstruir las tablas de abajo (que copian todas sus columnas) y
    // antes de que _crearIndices intente indexar columnas/tablas que en
    // ese punto todavía no existirían.
    await _ensureVentasMetodoPagoColumn(db);
    await _ensureDetalleCompraCantidadColumn(db);
    await _ensurePedidosDireccionColumn(db);
    await _ensureVentasEstadoColumn(db);
    await _ensureDevolucionesTables(db);
    await _ensureVentasDescuentoColumns(db);
    await _ensureDetalleVentaDescuentoColumns(db);
    await _ensureConfiguracionDescuentoColumns(db);
    await _ensureVentaPagosTable(db);
    await _ensureVentasCambioColumn(db);
    await _backfillVentaPagos(db);
    await _ensureCajasTable(db);
    await _ensureVentasIdCajaColumn(db);
    await _ensureDevolucionesIdCajaColumn(db);
    await _ensurePromocionesTables(db);
    await _ensureInventarioCantidadReservadaColumn(db);
    await _ensureApartadosTables(db);
    await _ensureVentasIdApartadoColumn(db);
    await _ensureCajasAnticiposColumns(db);
    await _ensureAuditoriasContextColumns(db);
    await _ensureComprasCreditoColumns(db);
    await _ensureAbonosTables(db);
    await _ensureCajasPagosProveedoresColumn(db);
    await _backfillAbonosComprasExistentes(db);
    await _ensureGuidSyncColumns(db);
    await _ensureSyncOutboxTable(db);

    if (oldVersion < 7) {
      // SQLite no permite modificar una FOREIGN KEY ya existente con
      // ALTER TABLE; hay que reconstruir cada tabla siguiendo el
      // procedimiento oficial de SQLite (rename -> create -> copiar datos ->
      // drop). foreign_keys ya está OFF desde _onConfigure y se reactiva en
      // _onOpen, una vez que esta migración terminó de confirmarse.
      await _reconstruirTablasConIntegridadReferencial(db);
      await _crearIndices(db);
    }
    if (oldVersion < 8) {
      await _ensureConfiguracionNegocioColumns(db);
    }
    if (oldVersion < 9) {
      await _ensureProductoCodigoBarrasColumn(db);
    }

    // Idempotente (CREATE INDEX IF NOT EXISTS): se repite en cada upgrade
    // para que índices agregados en versiones nuevas (como el de
    // codigo_barras) también lleguen a instalaciones que ya estaban al
    // día en versiones anteriores del esquema.
    await _crearIndices(db);
  }

  /// Agrega la columna opcional de código de barras a `Producto`. Puede ser
  /// `NULL` (producto sin código) o un valor único: la unicidad la impone
  /// el índice `idx_producto_codigo_barras` creado en [_crearIndices].
  /// SQLite no considera colisión entre múltiples `NULL` en un índice
  /// único, así que no hace falta un índice parcial.
  Future<void> _ensureProductoCodigoBarrasColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Producto)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('codigo_barras')) {
      await db.execute('ALTER TABLE Producto ADD COLUMN codigo_barras TEXT;');
    }
  }

  /// Agrega la columna de estado a `Ventas` (Activa/Parcialmente
  /// devuelta/Cancelada). Sin CHECK a propósito: se agrega con ALTER TABLE
  /// a bases existentes, y SQLite no permite añadir restricciones CHECK así
  /// (solo reconstruyendo la tabla). La validación de valores válidos vive
  /// en [DevolucionesController].
  Future<void> _ensureVentasEstadoColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('estado')) {
      await db.execute("ALTER TABLE Ventas ADD COLUMN estado TEXT DEFAULT 'Activa';");
    }
  }

  /// Crea las tablas de devoluciones/cancelaciones si no existen. Son
  /// tablas nuevas (sin datos legacy que migrar): se prefieren en vez de
  /// modificar `Detalle_Venta`, que se conserva intacto como el registro
  /// histórico de lo realmente vendido.
  Future<void> _ensureDevolucionesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Devoluciones (
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
      CREATE TABLE IF NOT EXISTS Detalle_Devolucion (
        id_detalle_devolucion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_devolucion INTEGER NOT NULL,
        id_producto INTEGER NOT NULL,
        cantidad INTEGER NOT NULL,
        precio REAL NOT NULL,
        FOREIGN KEY (id_devolucion) REFERENCES Devoluciones(id_devolucion) ON DELETE CASCADE,
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
      );
    ''');
  }

  /// Agrega a `Ventas` las columnas de descuento (subtotal bruto, monto
  /// total descontado, tipo/valor del descuento global, motivo y quién lo
  /// autorizó). `total` no se toca: pasa a significar "total final
  /// cobrado", y en filas existentes ya coincide con `subtotal` porque no
  /// tenían descuento, así que se hace `subtotal = total` como respaldo.
  /// Sin CHECK en `descuento_global_tipo` por la misma razón que `estado`:
  /// se agrega con ALTER TABLE, y SQLite no permite CHECK así.
  Future<void> _ensureVentasDescuentoColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    final columnasNuevas = {
      // Sin DEFAULT aquí a propósito (a diferencia del onCreate de una base
      // nueva): deja subtotal en NULL en filas existentes para poder
      // rellenarlo una sola vez abajo, sin volver a escanear la tabla en
      // cada apertura una vez migrado.
      'subtotal': 'REAL',
      'descuento_total': 'REAL DEFAULT 0',
      'descuento_global_tipo': 'TEXT',
      'descuento_global_valor': 'REAL DEFAULT 0',
      'descuento_motivo': 'TEXT',
      'descuento_autorizado_por': 'INTEGER',
    };

    for (final entry in columnasNuevas.entries) {
      if (!columnNames.contains(entry.key)) {
        await db.execute('ALTER TABLE Ventas ADD COLUMN ${entry.key} ${entry.value};');
      }
    }

    await db.execute('UPDATE Ventas SET subtotal = total WHERE subtotal IS NULL;');
  }

  /// Agrega la columna de cambio entregado (solo puede originarse de pagos
  /// en efectivo, ver `lib/core/utils/pagos_mixtos.dart`). En filas
  /// existentes queda en su DEFAULT 0: el cambio histórico nunca se
  /// persistió antes de esta versión, así que no hay forma de reconstruirlo.
  Future<void> _ensureVentasCambioColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('cambio')) {
      await db.execute('ALTER TABLE Ventas ADD COLUMN cambio REAL DEFAULT 0;');
    }
  }

  /// Crea la tabla de líneas de pago (relación 1:N con `Ventas`) que permite
  /// pagar una venta con varios métodos simultáneos. Tabla nueva, sin datos
  /// legacy que migrar por ALTER TABLE: el historial se rellena aparte en
  /// [_backfillVentaPagos].
  Future<void> _ensureVentaPagosTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Venta_Pagos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_venta INTEGER NOT NULL,
        metodo_pago TEXT NOT NULL,
        monto REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE CASCADE
      );
    ''');
  }

  /// Por cada venta histórica que todavía no tenga ninguna fila en
  /// `Venta_Pagos`, asume que se pagó de una sola vez con el método ya
  /// guardado en `Ventas.metodo_pago`, por el total completo (el desglose
  /// mixto y el cambio de esas ventas nunca existieron). Un solo
  /// INSERT...SELECT con NOT IN es naturalmente idempotente: en la segunda
  /// llamada el WHERE ya no matchea ninguna fila.
  Future<void> _backfillVentaPagos(Database db) async {
    await db.execute('''
      INSERT INTO Venta_Pagos (id_venta, metodo_pago, monto)
      SELECT id_venta, IFNULL(metodo_pago, 'efectivo'), total
      FROM Ventas
      WHERE id_venta NOT IN (SELECT DISTINCT id_venta FROM Venta_Pagos);
    ''');
  }

  /// Crea la tabla de sesiones de caja (apertura/cierre por cajero). Tabla
  /// nueva, sin datos legacy que migrar. Las columnas de cierre quedan NULL
  /// mientras `estado='Abierta'` y se congelan una sola vez en
  /// `CajaController.cerrarCaja` (snapshot inmutable, mismo criterio que
  /// `Devoluciones.importe`).
  Future<void> _ensureCajasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Cajas (
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
  }

  /// Desglose de anticipos/abonos de Apartados cobrados en esta caja,
  /// congelado al cerrar (mismo criterio que `ventas_efectivo` etc.) — sin
  /// esto, una caja ya cerrada solo mostraría el total correcto en
  /// `efectivo_esperado`, pero perdería el desglose por categoría.
  Future<void> _ensureCajasAnticiposColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Cajas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    final columnasNuevas = ['anticipos_efectivo', 'anticipos_tarjeta', 'anticipos_transferencia'];
    for (final columna in columnasNuevas) {
      if (!columnNames.contains(columna)) {
        await db.execute('ALTER TABLE Cajas ADD COLUMN $columna REAL;');
      }
    }
  }

  /// Desglose de pagos a proveedores cobrados en efectivo desde esta caja,
  /// congelado al cerrar (mismo criterio que `anticipos_efectivo`) — sin
  /// esto, el cierre no podría mostrar cuánto de esa salida ya quedó fijo
  /// en el historial de cajas cerradas.
  Future<void> _ensureCajasPagosProveedoresColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Cajas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('pagos_proveedores_efectivo')) {
      await db.execute('ALTER TABLE Cajas ADD COLUMN pagos_proveedores_efectivo REAL;');
    }
  }

  /// Datos de crédito/vencimiento de una compra. `forma_pago` es solo
  /// informativa (qué intención tenía el usuario al comprar); el saldo y el
  /// estado de pago NUNCA se guardan aquí — siempre se calculan en vivo a
  /// partir de `total` y la suma de `Abonos` (ver `CuentasPorPagarController`).
  Future<void> _ensureComprasCreditoColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Compras)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('forma_pago')) {
      await db.execute("ALTER TABLE Compras ADD COLUMN forma_pago TEXT NOT NULL DEFAULT 'Contado';");
    }
    if (!columnNames.contains('fecha_vencimiento')) {
      await db.execute('ALTER TABLE Compras ADD COLUMN fecha_vencimiento TEXT;');
    }
    if (!columnNames.contains('folio_factura')) {
      await db.execute('ALTER TABLE Compras ADD COLUMN folio_factura TEXT;');
    }
  }

  /// `Abonos`: cada pago hecho a cuenta de una compra (historial inmutable,
  /// nunca se edita ni se borra). `id_caja` es NULLABLE a propósito: un
  /// abono por transferencia/tarjeta no requiere caja abierta, uno en
  /// efectivo sí (se valida en `CuentasPorPagarController`, no aquí).
  /// `Abono_Pagos` desglosa cada abono por método de pago, igual que
  /// `Apartado_Abono_Pagos` desglosa cada abono de apartado — no se reutiliza
  /// `Venta_Pagos` a propósito, es una estructura propia para compras.
  Future<void> _ensureAbonosTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Abonos (
        id_abono INTEGER PRIMARY KEY AUTOINCREMENT,
        id_compra INTEGER NOT NULL,
        id_caja INTEGER,
        id_usuario INTEGER,
        fecha TEXT NOT NULL,
        monto REAL NOT NULL DEFAULT 0,
        referencia TEXT,
        observaciones TEXT,
        FOREIGN KEY (id_compra) REFERENCES Compras(id_compra) ON DELETE RESTRICT,
        FOREIGN KEY (id_caja) REFERENCES Cajas(id_caja) ON DELETE RESTRICT,
        FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Abono_Pagos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_abono INTEGER NOT NULL,
        metodo_pago TEXT NOT NULL,
        monto REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_abono) REFERENCES Abonos(id_abono) ON DELETE CASCADE
      );
    ''');
  }

  /// Antes de esta migración, toda compra se asumía saldada de inmediato
  /// (no existía ningún concepto de crédito/pago). Sin este backfill, todas
  /// las compras históricas aparecerían de golpe como 100% pendientes al
  /// abrir la app ya migrada, porque el saldo se calcula en vivo a partir de
  /// `Abonos` y ninguna compra vieja tiene abonos.
  ///
  /// El abono retroactivo cubre el total completo (para que la compra quede
  /// `Pagada` y no se convierta en deuda pendiente que nunca existió), pero
  /// a propósito NO se marca como pagado en efectivo/tarjeta/transferencia:
  /// ese dato nunca se registró y no debe inventarse, porque falsearía los
  /// totales por método de pago y los cierres de caja (una compra vieja no
  /// tiene `id_caja`, así que jamás pudo ser un cierre real). Se usa
  /// [metodoPagoHistorico] ("sin método de pago registrado"), que
  /// deliberadamente no aparece en ninguna suma de efectivo/tarjeta/
  /// transferencia (ver `CajaController`/`ReporteController`).
  ///
  /// Idempotente: solo actúa sobre compras que todavía no tengan ningún
  /// abono, así que no duplica nada si se vuelve a llamar.
  Future<void> _backfillAbonosComprasExistentes(Database db) async {
    final comprasSinAbono = await db.rawQuery('''
      SELECT c.id_compra, c.fecha, c.total, c.id_usuario
      FROM Compras c
      LEFT JOIN Abonos a ON a.id_compra = c.id_compra
      WHERE a.id_abono IS NULL
    ''');

    for (final compra in comprasSinAbono) {
      final total = (compra['total'] as num?)?.toDouble() ?? 0;
      if (total <= 0) continue;

      final idAbono = await db.insert('Abonos', {
        'id_compra': compra['id_compra'],
        'id_caja': null,
        'id_usuario': compra['id_usuario'],
        'fecha': compra['fecha']?.toString() ?? DateTime.now().toIso8601String(),
        'monto': total,
        'referencia': 'Migración: compra previa a Cuentas por Pagar, sin método de pago registrado',
        'observaciones': null,
      });

      await db.insert('Abono_Pagos', {
        'id_abono': idAbono,
        'metodo_pago': metodoPagoHistorico,
        'monto': total,
      });
    }
  }

  /// Tabla local -> nombre de la columna de llave primaria, para cada tabla
  /// que espeja una entidad sincronizable del backend (ver
  /// `SyncEntidadRegistry` en `EsqueletoPOS/src/EsqPos.Infrastructure/
  /// Persistence/SyncService.cs`). Deliberadamente NO incluye las tablas
  /// puente/detalle de promociones (`Promocion_Productos`,
  /// `Promocion_Categorias`, `Promocion_Combo_Items`,
  /// `Venta_Promociones_Detalle`): aunque el backend también las trata como
  /// filas con identidad propia, acá se van a repoblar completas junto con su
  /// fila padre en cada pull en vez de sincronizarse una por una -- si el
  /// motor de sync que se construya después necesita tratarlas distinto,
  /// agregarles `guid_sync` es una migración aparte, no una reescritura de
  /// esta.
  static const Map<String, String> _tablasConGuidSync = {
    'Categorias': 'id_categoria',
    'Producto': 'id_producto',
    'Clientes': 'id_cliente',
    'Proveedores': 'id_proveedor',
    'Inventario': 'id_inventario',
    'Ventas': 'id_venta',
    'Detalle_Venta': 'id_detalleV',
    'Venta_Pagos': 'id',
    'Cajas': 'id_caja',
    'Promociones': 'id_promocion',
    'Venta_Promociones': 'id_venta_promocion',
  };

  /// Agrega `guid_sync` (nullable) a cada tabla de [_tablasConGuidSync] y
  /// rellena con un GUID nuevo cualquier fila que todavía no tenga uno
  /// ([GuidGenerator], nunca el mismo valor para dos filas).
  ///
  /// Esto es SOLO el esquema: dejar la columna lista y las filas existentes
  /// ya identificables. Generar un `guid_sync` para las filas NUEVAS que se
  /// creen de aquí en adelante (al vender, dar de alta un producto, etc.)
  /// requiere tocar el punto de inserción de cada controlador
  /// correspondiente -- deliberadamente fuera de esta migración, es el
  /// siguiente paso de la integración con EsqPOS (ver
  /// `lib/core/sync/README-fase2.md`). Hasta que eso exista, toda fila
  /// creada después de esta migración queda con `guid_sync = NULL` igual
  /// que las históricas, y una futura reapertura de la app la backfillea
  /// aquí mismo (este método es idempotente y corre en cada `_onOpen`).
  Future<void> _ensureGuidSyncColumns(Database db) async {
    for (final entry in _tablasConGuidSync.entries) {
      final tabla = entry.key;
      final columnaId = entry.value;

      final info = await db.rawQuery('PRAGMA table_info($tabla)');
      final columnNames = info.map((row) => row['name']?.toString()).toSet();
      if (!columnNames.contains('guid_sync')) {
        await db.execute('ALTER TABLE $tabla ADD COLUMN guid_sync TEXT;');
      }

      final filasSinGuid = await db.query(tabla, columns: [columnaId], where: 'guid_sync IS NULL');
      if (filasSinGuid.isEmpty) continue;

      final batch = db.batch();
      for (final fila in filasSinGuid) {
        batch.update(
          tabla,
          {'guid_sync': GuidGenerator.nuevo()},
          where: '$columnaId = ?',
          whereArgs: [fila[columnaId]],
        );
      }
      await batch.commit(noResult: true);
    }
  }

  /// Cola de cambios locales pendientes de subir al backend (`POST
  /// /api/sync/push`, ver `SyncClient` en `lib/core/sync/sync_client.dart`
  /// y el contrato en `docs/sync-desktop-fase2.md`). Tabla nueva, sin datos
  /// que migrar.
  ///
  /// Solo el esquema por ahora: nadie escribe en esta tabla todavía (eso es
  /// el motor de sync, siguiente paso de la integración) ni hay un proceso
  /// que la vacíe empujando al backend. `datos_json` guarda el payload ya
  /// armado a encolar (snapshot al momento de la operación) en vez de
  /// recalcularlo desde el estado actual de la fila al momento de subirlo,
  /// para que un cambio posterior sobre la misma fila no altere lo que ya
  /// estaba pendiente de subir.
  Future<void> _ensureSyncOutboxTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Sync_Outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entidad TEXT NOT NULL,
        guid_registro TEXT NOT NULL,
        operacion TEXT CHECK(operacion IN ('CREAR','ACTUALIZAR','ELIMINAR')) NOT NULL,
        datos_json TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        intentos INTEGER NOT NULL DEFAULT 0,
        ultimo_error TEXT
      );
    ''');
  }

  /// Liga cada venta a la caja que estaba abierta al momento de cobrarla.
  /// Sin `REFERENCES` en el ALTER (igual que `descuento_autorizado_por`)
  /// para evitar edge cases de SQLite con FK agregadas fuera de CREATE
  /// TABLE; la integridad referencial real solo aplica a instalaciones
  /// nuevas vía `_onCreate`. Ventas históricas quedan con `id_caja = NULL`
  /// — no se inventa una caja retroactiva.
  Future<void> _ensureVentasIdCajaColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('id_caja')) {
      await db.execute('ALTER TABLE Ventas ADD COLUMN id_caja INTEGER;');
    }
  }

  /// Liga cada devolución a la caja abierta de quien la procesó (no
  /// necesariamente la misma caja bajo la que se hizo la venta original).
  Future<void> _ensureDevolucionesIdCajaColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Devoluciones)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('id_caja')) {
      await db.execute('ALTER TABLE Devoluciones ADD COLUMN id_caja INTEGER;');
    }
  }

  /// Tablas del motor de promociones automáticas: la definición de cada
  /// promoción, sus participantes (productos/categorías, o los items del
  /// combo) y el snapshot inmutable de lo aplicado en cada venta.
  ///
  /// `Venta_Promociones`/`Venta_Promociones_Detalle` son tablas nuevas sin
  /// datos legacy que migrar. `id_promocion` en `Venta_Promociones` es
  /// `ON DELETE SET NULL` a propósito: editar o borrar una promoción no debe
  /// alterar ventas ya cerradas, por eso el nombre/tipo se guardan también
  /// como snapshot (`nombre_snapshot`/`tipo_snapshot`) en vez de leerse en
  /// vivo desde `Promociones`.
  Future<void> _ensurePromocionesTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Promociones (
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
      CREATE TABLE IF NOT EXISTS Promocion_Productos (
        id_promocion INTEGER NOT NULL,
        id_producto INTEGER NOT NULL,
        PRIMARY KEY (id_promocion, id_producto),
        FOREIGN KEY (id_promocion) REFERENCES Promociones(id_promocion) ON DELETE CASCADE,
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Promocion_Categorias (
        id_promocion INTEGER NOT NULL,
        id_categoria INTEGER NOT NULL,
        PRIMARY KEY (id_promocion, id_categoria),
        FOREIGN KEY (id_promocion) REFERENCES Promociones(id_promocion) ON DELETE CASCADE,
        FOREIGN KEY (id_categoria) REFERENCES Categorias(id_categoria) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Promocion_Combo_Items (
        id_promocion INTEGER NOT NULL,
        id_producto INTEGER NOT NULL,
        cantidad INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (id_promocion, id_producto),
        FOREIGN KEY (id_promocion) REFERENCES Promociones(id_promocion) ON DELETE CASCADE,
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Venta_Promociones (
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
      CREATE TABLE IF NOT EXISTS Venta_Promociones_Detalle (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_venta_promocion INTEGER NOT NULL,
        id_detalleV INTEGER NOT NULL,
        cantidad_afectada INTEGER NOT NULL,
        ahorro REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_venta_promocion) REFERENCES Venta_Promociones(id_venta_promocion) ON DELETE CASCADE,
        FOREIGN KEY (id_detalleV) REFERENCES Detalle_Venta(id_detalleV) ON DELETE CASCADE
      );
    ''');
  }

  /// Distingue por primera vez stock físico de stock reservado (por
  /// Apartados): `cantidad` sigue significando "existencia física" tal como
  /// ya la usan Ventas/Compras/Pedidos-al-entregar; `cantidad_reservada`
  /// nunca se resta de `cantidad` directamente — "disponible para vender"
  /// se calcula siempre como `cantidad - cantidad_reservada` en el momento
  /// de leer, nunca se guarda.
  Future<void> _ensureInventarioCantidadReservadaColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Inventario)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('cantidad_reservada')) {
      await db.execute('ALTER TABLE Inventario ADD COLUMN cantidad_reservada INTEGER NOT NULL DEFAULT 0;');
    }
  }

  /// Enlaza la venta definitiva creada al liquidar un apartado de vuelta al
  /// apartado de origen. Sin `REFERENCES` en el ALTER (mismo motivo que
  /// `id_caja`/`descuento_autorizado_por`: SQLite y sus limitaciones con FK
  /// agregadas fuera de CREATE TABLE) — la integridad referencial real solo
  /// aplica a instalaciones nuevas vía `_onCreate`.
  Future<void> _ensureVentasIdApartadoColumn(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Ventas)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('id_apartado')) {
      await db.execute('ALTER TABLE Ventas ADD COLUMN id_apartado INTEGER;');
    }
  }

  /// Tablas del módulo de Apartados (layaway): la reserva en sí
  /// (`Apartados`/`Detalle_Apartado`, snapshot inmutable igual que
  /// Ventas/Detalle_Venta), el snapshot de promociones aplicadas al crear
  /// (mismo patrón que `Venta_Promociones`), y el historial de abonos
  /// (`Apartado_Abonos`, un evento de pago) con sus métodos de pago
  /// (`Apartado_Abono_Pagos`, mismo shape que `Venta_Pagos` pero un nivel
  /// más anidado porque un apartado admite *varios* eventos de pago en el
  /// tiempo, no uno solo).
  ///
  /// Al liquidar, la Venta resultante NO copia filas a `Venta_Pagos` ni
  /// `Venta_Promociones` (evita contar el dinero dos veces en Caja/Reportes,
  /// ver `ApartadosController._liquidar`): el historial de pagos y
  /// promociones de una venta que vino de un apartado se sigue leyendo de
  /// `Apartado_Abonos`/`Apartado_Promociones` a través de `Ventas.id_apartado`.
  Future<void> _ensureApartadosTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Apartados (
        id_apartado INTEGER PRIMARY KEY AUTOINCREMENT,
        id_cliente INTEGER NOT NULL,
        id_usuario INTEGER,
        fecha_creacion TEXT NOT NULL,
        fecha_limite TEXT,
        estado TEXT CHECK(estado IN ('Pendiente','Liquidado','Cancelado','Vencido')) NOT NULL DEFAULT 'Pendiente',
        subtotal REAL NOT NULL DEFAULT 0,
        descuento_total REAL NOT NULL DEFAULT 0,
        descuento_global_tipo TEXT,
        descuento_global_valor REAL DEFAULT 0,
        descuento_motivo TEXT,
        descuento_autorizado_por INTEGER,
        total REAL NOT NULL DEFAULT 0,
        id_venta INTEGER,
        observaciones TEXT,
        FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente) ON DELETE RESTRICT,
        FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT,
        FOREIGN KEY (id_venta) REFERENCES Ventas(id_venta) ON DELETE SET NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Detalle_Apartado (
        id_detalle_apartado INTEGER PRIMARY KEY AUTOINCREMENT,
        id_apartado INTEGER NOT NULL,
        id_producto INTEGER NOT NULL,
        cantidad INTEGER NOT NULL,
        precio REAL NOT NULL,
        descuento_tipo TEXT,
        descuento_valor REAL DEFAULT 0,
        descuento_monto REAL DEFAULT 0,
        precio_neto REAL,
        FOREIGN KEY (id_apartado) REFERENCES Apartados(id_apartado) ON DELETE CASCADE,
        FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Apartado_Promociones (
        id_apartado_promocion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_apartado INTEGER NOT NULL,
        id_promocion INTEGER,
        nombre_snapshot TEXT NOT NULL,
        tipo_snapshot TEXT NOT NULL,
        ahorro_total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_apartado) REFERENCES Apartados(id_apartado) ON DELETE CASCADE,
        FOREIGN KEY (id_promocion) REFERENCES Promociones(id_promocion) ON DELETE SET NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Apartado_Promociones_Detalle (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_apartado_promocion INTEGER NOT NULL,
        id_detalle_apartado INTEGER NOT NULL,
        cantidad_afectada INTEGER NOT NULL,
        ahorro REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_apartado_promocion) REFERENCES Apartado_Promociones(id_apartado_promocion) ON DELETE CASCADE,
        FOREIGN KEY (id_detalle_apartado) REFERENCES Detalle_Apartado(id_detalle_apartado) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Apartado_Abonos (
        id_abono INTEGER PRIMARY KEY AUTOINCREMENT,
        id_apartado INTEGER NOT NULL,
        id_caja INTEGER NOT NULL,
        id_usuario INTEGER,
        fecha TEXT NOT NULL,
        tipo TEXT CHECK(tipo IN ('Anticipo','Abono','Liquidacion')) NOT NULL,
        monto REAL NOT NULL DEFAULT 0,
        cambio REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_apartado) REFERENCES Apartados(id_apartado) ON DELETE CASCADE,
        FOREIGN KEY (id_caja) REFERENCES Cajas(id_caja) ON DELETE RESTRICT,
        FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Apartado_Abono_Pagos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_abono INTEGER NOT NULL,
        metodo_pago TEXT NOT NULL,
        monto REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (id_abono) REFERENCES Apartado_Abonos(id_abono) ON DELETE CASCADE
      );
    ''');
  }

  /// Agrega a `Detalle_Venta` las columnas de descuento por línea y
  /// `precio_neto` (precio unitario ya con descuento de línea y su parte
  /// proporcional del global — lo que usan las devoluciones). `precio`
  /// (el original) nunca se toca; en filas existentes, sin descuento,
  /// `precio_neto` se rellena igual a `precio`.
  Future<void> _ensureDetalleVentaDescuentoColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Detalle_Venta)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    final columnasNuevas = {
      'descuento_tipo': 'TEXT',
      'descuento_valor': 'REAL DEFAULT 0',
      'descuento_monto': 'REAL DEFAULT 0',
      'precio_neto': 'REAL',
    };

    for (final entry in columnasNuevas.entries) {
      if (!columnNames.contains(entry.key)) {
        await db.execute('ALTER TABLE Detalle_Venta ADD COLUMN ${entry.key} ${entry.value};');
      }
    }

    await db.execute('UPDATE Detalle_Venta SET precio_neto = precio WHERE precio_neto IS NULL;');
  }

  /// Agrega a `configuracion` los 3 parámetros configurables de descuentos:
  /// el umbral (a la vez tope habitual y punto en el que se exige motivo),
  /// si el cajero puede aplicar descuentos, y si necesita autorización de
  /// administrador al superar el umbral.
  Future<void> _ensureConfiguracionDescuentoColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(configuracion)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    final columnasNuevas = {
      'descuento_maximo_porcentaje': 'REAL DEFAULT 20',
      'descuento_cajero_puede_aplicar': 'INTEGER DEFAULT 1',
      'descuento_cajero_requiere_autorizacion': 'INTEGER DEFAULT 1',
    };

    for (final entry in columnasNuevas.entries) {
      if (!columnNames.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE configuracion ADD COLUMN ${entry.key} ${entry.value};',
        );
      }
    }
  }

  /// Agrega a `configuracion` las columnas de identidad del negocio
  /// (nombre, logo, dirección, teléfono, correo, RFC, moneda, IVA, mensaje
  /// de ticket, color de marca). No se pierde la fila de configuración ya
  /// existente: simplemente queda con estos campos en NULL hasta que el
  /// negocio los llena en la pantalla de Configuración.
  Future<void> _ensureConfiguracionNegocioColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(configuracion)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    final columnasNuevas = {
      'nombre_negocio': 'TEXT',
      'logo_path': 'TEXT',
      'direccion': 'TEXT',
      'telefono': 'TEXT',
      'correo': 'TEXT',
      'rfc': 'TEXT',
      'simbolo_moneda': 'TEXT',
      'tasa_impuesto': 'REAL',
      'mensaje_ticket': 'TEXT',
      'color_primario': 'INTEGER',
    };

    for (final entry in columnasNuevas.entries) {
      if (!columnNames.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE configuracion ADD COLUMN ${entry.key} ${entry.value};',
        );
      }
    }
  }

  /// Reconstruye las tablas que necesitaban corregir su FOREIGN KEY. No se
  /// pierde ninguna fila: cada tabla se copia por completo antes de borrar
  /// la versión vieja, y todo corre dentro de una transacción (si algo
  /// falla a la mitad, SQLite revierte los cambios de esquema también).
  Future<void> _reconstruirTablasConIntegridadReferencial(Database db) async {
    await db.transaction((txn) async {
      await _reconstruirTabla(
        txn,
        nombre: 'Producto',
        columnas:
            'id_producto, nombre, descripcion, precio, precio_compra, categoria, stock_minimo, estado, id_categoria',
        definicionNueva: '''
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
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Inventario',
        columnas: 'id_inventario, id_producto, cantidad',
        definicionNueva: '''
          CREATE TABLE Inventario (
            id_inventario INTEGER PRIMARY KEY AUTOINCREMENT,
            id_producto INTEGER UNIQUE,
            cantidad INTEGER,
            FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE CASCADE
          );
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Compras',
        columnas: 'id_compra, fecha, total, id_proveedor, id_usuario',
        definicionNueva: '''
          CREATE TABLE Compras (
            id_compra INTEGER PRIMARY KEY AUTOINCREMENT,
            fecha DATE,
            total REAL,
            id_proveedor INTEGER,
            id_usuario INTEGER,
            FOREIGN KEY (id_proveedor) REFERENCES Proveedores(id_proveedor) ON DELETE RESTRICT,
            FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT
          );
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Detalle_Compra',
        columnas: 'id_detalle, id_compra, id_producto, cantidad, precio',
        definicionNueva: '''
          CREATE TABLE Detalle_Compra (
            id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
            id_compra INTEGER,
            id_producto INTEGER,
            cantidad INTEGER DEFAULT 1,
            precio REAL,
            FOREIGN KEY (id_compra) REFERENCES Compras(id_compra) ON DELETE CASCADE,
            FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
          );
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Pedidos',
        columnas:
            'id_pedido, id_cliente, fecha, estado, total, fecha_entrega, tipo_entrega, direccion',
        definicionNueva: '''
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
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Detalle_Pedido',
        columnas: 'id_detalle, id_pedido, id_producto, cantidad, precio',
        definicionNueva: '''
          CREATE TABLE Detalle_Pedido (
            id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
            id_pedido INTEGER,
            id_producto INTEGER,
            cantidad INTEGER,
            precio REAL,
            FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido) ON DELETE CASCADE,
            FOREIGN KEY (id_producto) REFERENCES Producto(id_producto) ON DELETE RESTRICT
          );
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Ventas',
        columnas: 'id_venta, id_cliente, id_usuario, id_pedido, fecha, total, metodo_pago',
        definicionNueva: '''
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
            FOREIGN KEY (id_cliente) REFERENCES Clientes(id_cliente) ON DELETE RESTRICT,
            FOREIGN KEY (id_usuario) REFERENCES Usuarios(id_usuario) ON DELETE RESTRICT,
            FOREIGN KEY (id_pedido) REFERENCES Pedidos(id_pedido) ON DELETE SET NULL
          );
        ''',
      );

      await _reconstruirTabla(
        txn,
        nombre: 'Detalle_Venta',
        columnas: 'id_detalleV, id_venta, id_producto, cantidad, precio',
        definicionNueva: '''
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
        ''',
      );
    });
  }

  /// Procedimiento oficial de SQLite para cambiar la definición de una
  /// tabla existente sin perder datos: renombrar, crear la nueva, copiar
  /// filas por columnas explícitas, borrar la vieja.
  Future<void> _reconstruirTabla(
    DatabaseExecutor db, {
    required String nombre,
    required String columnas,
    required String definicionNueva,
  }) async {
    await db.execute('ALTER TABLE $nombre RENAME TO ${nombre}_old;');
    await db.execute(definicionNueva);
    await db.execute(
      'INSERT INTO $nombre ($columnas) SELECT $columnas FROM ${nombre}_old;',
    );
    await db.execute('DROP TABLE ${nombre}_old;');
  }

  /// Índices sobre columnas usadas en WHERE/JOIN/ORDER BY frecuentes
  /// (ventas por fecha, reportes, corte de caja, joins de detalle).
  /// CREATE INDEX IF NOT EXISTS es idempotente: seguro de llamar en cada
  /// instalación nueva y en la migración de una ya existente.
  Future<void> _crearIndices(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_fecha ON Ventas(fecha);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_fecha_dia ON Ventas(date(fecha));');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_id_cliente ON Ventas(id_cliente);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_id_usuario ON Ventas(id_usuario);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_venta_id_venta ON Detalle_Venta(id_venta);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_venta_id_producto ON Detalle_Venta(id_producto);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_compras_fecha ON Compras(fecha);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_compras_fecha_dia ON Compras(date(fecha));');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_compras_id_proveedor ON Compras(id_proveedor);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_compra_id_compra ON Detalle_Compra(id_compra);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_compra_id_producto ON Detalle_Compra(id_producto);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_id_cliente ON Pedidos(id_cliente);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pedidos_fecha ON Pedidos(fecha);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_pedido ON Detalle_Pedido(id_pedido);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_producto ON Detalle_Pedido(id_producto);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_id_categoria ON Producto(id_categoria);');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_producto_codigo_barras ON Producto(codigo_barras);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_auditorias_fecha_hora ON Auditorias(fecha_hora);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_auditorias_tabla ON Auditorias(tabla);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_auditorias_id_usuario ON Auditorias(id_usuario);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_estado ON Ventas(estado);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_devoluciones_id_venta ON Devoluciones(id_venta);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_devoluciones_fecha_hora ON Devoluciones(fecha_hora);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_devolucion_id_devolucion ON Detalle_Devolucion(id_devolucion);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_devolucion_id_producto ON Detalle_Devolucion(id_producto);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_venta_pagos_id_venta ON Venta_Pagos(id_venta);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cajas_id_usuario_estado ON Cajas(id_usuario, estado);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cajas_fecha_apertura ON Cajas(fecha_apertura);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_id_caja ON Ventas(id_caja);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_devoluciones_id_caja ON Devoluciones(id_caja);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_promociones_activo ON Promociones(activo, fecha_inicio, fecha_fin);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_promocion_productos_id_producto ON Promocion_Productos(id_producto);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_promocion_categorias_id_categoria ON Promocion_Categorias(id_categoria);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_venta_promociones_id_venta ON Venta_Promociones(id_venta);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_venta_promociones_detalle_id_venta_promocion ON Venta_Promociones_Detalle(id_venta_promocion);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_venta_promociones_detalle_id_detalleV ON Venta_Promociones_Detalle(id_detalleV);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_apartados_id_cliente ON Apartados(id_cliente);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_apartados_id_venta ON Apartados(id_venta);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartados_estado_fecha_limite ON Apartados(estado, fecha_limite);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_detalle_apartado_id_apartado ON Detalle_Apartado(id_apartado);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartado_promociones_id_apartado ON Apartado_Promociones(id_apartado);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartado_promociones_detalle_id_apartado_promocion ON Apartado_Promociones_Detalle(id_apartado_promocion);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartado_abonos_id_apartado ON Apartado_Abonos(id_apartado);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartado_abonos_id_caja ON Apartado_Abonos(id_caja);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_apartado_abono_pagos_id_abono ON Apartado_Abono_Pagos(id_abono);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ventas_id_apartado ON Ventas(id_apartado);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_abonos_id_compra ON Abonos(id_compra);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_abonos_id_caja ON Abonos(id_caja);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_abono_pagos_id_abono ON Abono_Pagos(id_abono);');

    // Un índice único por tabla sincronizable: NULL no cuenta como colisión
    // en SQLite (varias filas sin sincronizar aún pueden convivir en NULL),
    // pero dos filas no pueden compartir el mismo GUID una vez asignado.
    for (final tabla in _tablasConGuidSync.keys) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${tabla.toLowerCase()}_guid_sync ON $tabla(guid_sync);',
      );
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_entidad ON Sync_Outbox(entidad);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_fecha_creacion ON Sync_Outbox(fecha_creacion);');
  }

  /// Migra a hash bcrypt cualquier contraseña que todavía esté en texto
  /// plano (instalaciones creadas antes de la versión 6 del esquema).
  /// Idempotente: si una contraseña ya está hasheada, no se toca.
  Future<void> _hashearContrasenasExistentes(Database db) async {
    final usuarios = await db.query('Usuarios', columns: ['id_usuario', 'contra']);

    for (final usuario in usuarios) {
      final contraActual = usuario['contra']?.toString() ?? '';
      if (contraActual.isEmpty || PasswordHasher.isHashed(contraActual)) {
        continue;
      }

      await db.update(
        'Usuarios',
        {'contra': PasswordHasher.hash(contraActual)},
        where: 'id_usuario = ?',
        whereArgs: [usuario['id_usuario']],
      );
    }
  }

  Future<void> _onOpen(Database db) async {
    // Se reactiva aquí (fuera de cualquier transacción) tras confirmarse la
    // creación/migración del esquema en _onCreate/_onUpgrade.
    await db.execute('PRAGMA foreign_keys = ON');
    await _ensureAuditoriasTable(db);
    await _ensureVentasMetodoPagoColumn(db);
    await _ensureDetalleCompraCantidadColumn(db);
    await _ensurePedidosDireccionColumn(db);
    await _ensureProductoCodigoBarrasColumn(db);
    await _ensureVentasEstadoColumn(db);
    await _ensureDevolucionesTables(db);
    await _ensureVentasDescuentoColumns(db);
    await _ensureDetalleVentaDescuentoColumns(db);
    await _ensureConfiguracionDescuentoColumns(db);
    await _ensureVentaPagosTable(db);
    await _ensureVentasCambioColumn(db);
    await _backfillVentaPagos(db);
    await _ensureCajasTable(db);
    await _ensureVentasIdCajaColumn(db);
    await _ensureDevolucionesIdCajaColumn(db);
    await _ensurePromocionesTables(db);
    await _ensureInventarioCantidadReservadaColumn(db);
    await _ensureApartadosTables(db);
    await _ensureVentasIdApartadoColumn(db);
    await _ensureCajasAnticiposColumns(db);
    await _ensureAuditoriasContextColumns(db);
    await _ensureComprasCreditoColumns(db);
    await _ensureAbonosTables(db);
    await _ensureCajasPagosProveedoresColumn(db);
    await _backfillAbonosComprasExistentes(db);
    await _ensureGuidSyncColumns(db);
    await _ensureSyncOutboxTable(db);
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
        descripcion TEXT,
        id_usuario INTEGER,
        id_caja INTEGER
      );
    ''');
  }

  /// Agrega a `Auditorias` el usuario (numérico) y la caja relacionados con
  /// cada evento, para poder filtrar el reporte de movimientos por usuario
  /// sin depender de parsear el campo `usuario` (texto libre). Ambas
  /// columnas son opcionales: no todo evento ocurre dentro de una caja
  /// abierta (ej. cambios de configuración).
  Future<void> _ensureAuditoriasContextColumns(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(Auditorias)');
    final columnNames = info.map((row) => row['name']?.toString()).toSet();

    if (!columnNames.contains('id_usuario')) {
      await db.execute('ALTER TABLE Auditorias ADD COLUMN id_usuario INTEGER;');
    }
    if (!columnNames.contains('id_caja')) {
      await db.execute('ALTER TABLE Auditorias ADD COLUMN id_caja INTEGER;');
    }
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
