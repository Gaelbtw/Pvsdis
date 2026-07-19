// Migración de Cuentas por pagar: Compras gana forma_pago/fecha_vencimiento/
// folio_factura, se crean Abonos/Abono_Pagos, Cajas gana
// pagos_proveedores_efectivo, y las compras que ya existían antes de esta
// funcionalidad (sin ningún concepto de crédito) quedan retroactivamente
// marcadas como pagadas (backfill) — pero SIN inventar un método de pago
// real: nunca se registró si esas compras viejas se pagaron en efectivo,
// tarjeta o transferencia, así que el backfill usa una marca neutral
// (`metodoPagoHistorico`) que no debe sumar a ningún total por método de
// pago ni afectar ningún cierre de caja.
//
// Reutiliza el mismo patrón que `database_migration_test.dart`: siembra a
// mano el esquema tal como estaba en una versión vieja (v8, antes de que
// existiera nada de esto) y abre esa base con la versión real de la app
// para disparar `_onUpgrade`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/cuentas_por_pagar_controller.dart';
import 'package:pvapp/controllers/reporte_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/pagos_mixtos.dart';

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
    tempDir = Directory.systemTemp.createTempSync('pvapp_cxp_migration_test');
    path = join(tempDir.path, 'v8.db');
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    SessionManager.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'migra una base vieja (sin crédito) agregando columnas/tablas y marcando '
    'las compras existentes como ya pagadas',
    () async {
      // 1. Sembrar una base vieja con un proveedor, un usuario y dos compras
      // ya existentes (como si el negocio llevara tiempo usando el sistema
      // antes de esta funcionalidad).
      final dbVieja = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersionV8,
          onCreate: _crearEsquemaV8,
        ),
      );

      final idProveedor = await dbVieja.insert('Proveedores', {'nombre': 'Proveedor Histórico'});
      final idUsuario = await dbVieja.insert('Usuarios', {
        'nombre': 'admin',
        'contra': 'x',
        'rol': 'Admin',
      });

      final idCompra1 = await dbVieja.insert('Compras', {
        'fecha': '2024-01-10T10:00:00',
        'total': 500.0,
        'id_proveedor': idProveedor,
        'id_usuario': idUsuario,
      });
      final idCompra2 = await dbVieja.insert('Compras', {
        'fecha': '2024-02-15T10:00:00',
        'total': 1200.0,
        'id_proveedor': idProveedor,
        'id_usuario': idUsuario,
      });

      await dbVieja.close();

      // 2. Abrir con la versión real de la app: dispara _onUpgrade.
      final helper = DatabaseHelper();
      final dbMigrada = await helper.abrirEnRuta(path);

      expect(await dbMigrada.getVersion(), greaterThanOrEqualTo(17));

      // 3. Compras tiene las columnas nuevas.
      final columnasCompras = await dbMigrada.rawQuery('PRAGMA table_info(Compras)');
      final nombresCompras = columnasCompras.map((c) => c['name']).toSet();
      expect(nombresCompras, containsAll(['forma_pago', 'fecha_vencimiento', 'folio_factura']));

      // 4. Las compras viejas quedaron con forma_pago = 'Contado' (el
      // DEFAULT del ALTER TABLE aplica retroactivamente).
      final filasCompras = await dbMigrada.query('Compras', orderBy: 'id_compra ASC');
      expect(filasCompras, hasLength(2));
      for (final fila in filasCompras) {
        expect(fila['forma_pago'], 'Contado');
        expect(fila['fecha_vencimiento'], isNull);
      }

      // 5. Existen Abonos/Abono_Pagos.
      final tablas = await dbMigrada.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('Abonos','Abono_Pagos')",
      );
      expect(tablas.map((t) => t['name']).toSet(), {'Abonos', 'Abono_Pagos'});

      // 6. El backfill creó un abono por el total completo de cada compra
      // vieja (se asume que ya estaban pagadas, igual que se comportaba el
      // sistema antes de esta funcionalidad).
      final abonosCompra1 = await dbMigrada.query(
        'Abonos',
        where: 'id_compra = ?',
        whereArgs: [idCompra1],
      );
      expect(abonosCompra1, hasLength(1));
      expect((abonosCompra1.first['monto'] as num).toDouble(), 500.0);
      expect(abonosCompra1.first['id_caja'], isNull);

      final abonosCompra2 = await dbMigrada.query(
        'Abonos',
        where: 'id_compra = ?',
        whereArgs: [idCompra2],
      );
      expect(abonosCompra2, hasLength(1));
      expect((abonosCompra2.first['monto'] as num).toDouble(), 1200.0);

      final abonoPagos = await dbMigrada.query(
        'Abono_Pagos',
        where: 'id_abono = ?',
        whereArgs: [abonosCompra1.first['id_abono']],
      );
      expect(abonoPagos, hasLength(1));
      // Marca neutral, NO 'Efectivo': ese dato nunca existió y no debe
      // inventarse (falsearía reportes y cierres de caja).
      expect(abonoPagos.first['metodo_pago'], metodoPagoHistorico);
      expect((abonoPagos.first['monto'] as num).toDouble(), 500.0);

      // 7. Cajas tiene la columna nueva.
      final columnasCajas = await dbMigrada.rawQuery('PRAGMA table_info(Cajas)');
      expect(columnasCajas.map((c) => c['name']), contains('pagos_proveedores_efectivo'));

      // 8. El backfill es idempotente: correr la migración de nuevo (p. ej.
      // simplemente reabriendo, lo que vuelve a disparar _onOpen) no
      // duplica los abonos.
      DatabaseHelper.setTestDatabase(dbMigrada);
      await helper.database; // fuerza a pasar por _onOpen otra vez si aplica
      final abonosCompra1DeNuevo = await dbMigrada.query(
        'Abonos',
        where: 'id_compra = ?',
        whereArgs: [idCompra1],
      );
      expect(abonosCompra1DeNuevo, hasLength(1));

      // 9. Con CuentasPorPagarController, las compras viejas se ven como
      // 100% pagadas (no como deuda pendiente de la nada).
      final cuentas = await CuentasPorPagarController().obtenerCuentas();
      final cuenta1 = cuentas.firstWhere((c) => c['id_compra'] == idCompra1);
      final cuenta2 = cuentas.firstWhere((c) => c['id_compra'] == idCompra2);
      expect(cuenta1['estado'], 'Pagada');
      expect((cuenta1['saldo'] as num).toDouble(), 0.0);
      expect(cuenta2['estado'], 'Pagada');
      expect((cuenta2['saldo'] as num).toDouble(), 0.0);

      // 10. El abono histórico NO cuenta como pago en efectivo, tarjeta o
      // transferencia en ningún total agregado por método.
      final totalesPorMetodo = await dbMigrada.rawQuery('''
        SELECT metodo_pago, SUM(monto) as total
        FROM Abono_Pagos
        GROUP BY metodo_pago
      ''');
      for (final fila in totalesPorMetodo) {
        expect(
          metodosPagoDisponibles,
          isNot(contains(fila['metodo_pago'])),
          reason: 'ningún abono histórico debería quedar clasificado como un método real',
        );
      }

      // 11. No altera cierres de caja: al abrir y cerrar una caja nueva para
      // el mismo usuario, el histórico no debe aparecer como salida de
      // efectivo (no tiene id_caja, así que ninguna caja real puede
      // arrastrarlo).
      SessionManager.setUser(id: idUsuario, nombre: 'admin', rol: 'Admin');
      final cajaController = CajaController();
      final idCaja = await cajaController.abrirCaja(fondoInicial: 1000);
      final resumen = await cajaController.calcularResumenCaja(idCaja);
      expect(resumen.pagosProveedoresEfectivo, 0.0);
      expect(resumen.efectivoEsperado, 1000.0);
      SessionManager.clear();

      // 12. No aparece en los reportes como una salida de caja en efectivo,
      // ni siquiera con un rango de fechas amplio que sí cubra las compras
      // históricas (2024-01-10 y 2024-02-15).
      final reporte = await ReporteController().obtenerReporteCuentasPorPagar(
        desde: DateTime(2020),
        hasta: DateTime(2030),
      );
      expect(reporte.salidasCajaEfectivo, 0.0);

      await dbMigrada.close();
    },
  );
}
