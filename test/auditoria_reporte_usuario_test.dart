// Pruebas del reporte de movimientos por usuario: AuditoriaController.
// obtenerFiltradas combina filtros sobre la misma tabla Auditorias (usuario,
// acción, módulo, rango de fechas), y los huecos de auditoría cerrados en
// esta tarea (Compras, Proveedores) efectivamente insertan un registro.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/auditoria_controller.dart';
import 'package:pvapp/controllers/compras_controller.dart';
import 'package:pvapp/controllers/proveedor_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/models/proveedores_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late AuditoriaController auditoria;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_auditoria_reporte_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    auditoria = AuditoriaController();

    // La base nueva siembra unas auditorías demo (ver
    // _insertarAuditoriasDemo en database_helper.dart); se limpian para que
    // los conteos de estas pruebas reflejen solo lo que cada prueba genera.
    await db.delete('Auditorias');

    SessionManager.clear();
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    SessionManager.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> crearUsuario(String rol, {String nombre = 'usuario'}) {
    return db.insert('Usuarios', {
      'nombre': nombre,
      'contra': PasswordHasher.hash('1234'),
      'rol': rol,
    });
  }

  group('AuditoriaController.registrar', () {
    test('autocompleta id_usuario desde SessionManager cuando no se pasa explícito', () async {
      final idUsuario = await crearUsuario('Admin', nombre: 'Gael');
      SessionManager.setUser(id: idUsuario, nombre: 'Gael', rol: 'Admin');

      await auditoria.registrar(tabla: 'Configuracion', accion: 'EDIT', descripcion: 'Config actualizada');

      final rows = await db.query('Auditorias', where: "tabla = 'Configuracion'");
      expect(rows, hasLength(1));
      expect(rows.first['id_usuario'], idUsuario);
      expect(rows.first['id_caja'], isNull);
    });
  });

  group('AuditoriaController.obtenerFiltradas', () {
    test('filtra por usuario, acción, módulo y rango de fechas combinados', () async {
      final idAdmin = await crearUsuario('Admin', nombre: 'Admin Uno');
      final idCajero = await crearUsuario('Cajero', nombre: 'Cajero Uno');

      SessionManager.setUser(id: idAdmin, nombre: 'Admin Uno', rol: 'Admin');
      await auditoria.registrar(tabla: 'Productos', accion: 'CREATE', descripcion: 'Producto A creado');
      await auditoria.registrar(tabla: 'Productos', accion: 'EDIT', descripcion: 'Producto A editado');

      SessionManager.setUser(id: idCajero, nombre: 'Cajero Uno', rol: 'Cajero');
      await auditoria.registrar(tabla: 'Ventas', accion: 'CREATE', descripcion: 'Venta registrada');

      // Sin filtros: ve las 3.
      expect(await auditoria.obtenerFiltradas(), hasLength(3));

      // Solo del admin.
      final delAdmin = await auditoria.obtenerFiltradas(idUsuario: idAdmin);
      expect(delAdmin, hasLength(2));
      expect(delAdmin.every((a) => a.idUsuario == idAdmin), isTrue);

      // Solo del cajero.
      final delCajero = await auditoria.obtenerFiltradas(idUsuario: idCajero);
      expect(delCajero, hasLength(1));
      expect(delCajero.single.tabla, 'Ventas');

      // Por acción.
      final ediciones = await auditoria.obtenerFiltradas(accion: 'EDIT');
      expect(ediciones, hasLength(1));
      expect(ediciones.single.descripcion, contains('editado'));

      // Por módulo.
      final deProductos = await auditoria.obtenerFiltradas(tabla: 'Productos');
      expect(deProductos, hasLength(2));

      // Combinando usuario + módulo, sin resultados.
      final vacio = await auditoria.obtenerFiltradas(idUsuario: idCajero, tabla: 'Productos');
      expect(vacio, isEmpty);

      // Rango de fechas que excluye todo (futuro).
      final fueraDeRango = await auditoria.obtenerFiltradas(
        desde: DateTime.now().add(const Duration(days: 1)),
      );
      expect(fueraDeRango, isEmpty);

      // Rango de fechas que incluye todo (desde ayer).
      final dentroDeRango = await auditoria.obtenerFiltradas(
        desde: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(dentroDeRango, hasLength(3));
    });
  });

  group('Huecos de auditoría cerrados', () {
    test('ComprasController audita creación y eliminación de una compra', () async {
      final idUsuario = await crearUsuario('Admin');
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final idProveedor = await db.insert('Proveedores', {'nombre': 'Proveedor X'});
      final idProducto = await db.insert('Producto', {
        'nombre': 'Producto compra',
        'descripcion': '',
        'precio': 10,
        'stock_minimo': 0,
        'estado': 'Activo',
      });
      await db.insert('Inventario', {'id_producto': idProducto, 'cantidad': 0});

      await ComprasController().insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 5, 'precio_compra': 8},
        ],
        40,
        idProveedor,
      );

      final creadas = await auditoria.obtenerFiltradas(tabla: 'Compras', accion: 'CREATE');
      expect(creadas, hasLength(1));

      final compras = await db.query('Compras');
      final idCompra = compras.first['id_compra'] as int;

      await ComprasController().eliminarCompra(idCompra);

      final eliminadas = await auditoria.obtenerFiltradas(tabla: 'Compras', accion: 'DELETE');
      expect(eliminadas, hasLength(1));
    });

    test('ProveedorController audita alta, edición y baja', () async {
      final idUsuario = await crearUsuario('Admin');
      SessionManager.setUser(id: idUsuario, nombre: 'Admin', rol: 'Admin');

      final proveedorController = ProveedorController();

      final id = await proveedorController.insertar(
        Proveedores(
          idProveedor: null,
          nombre: 'Proveedor Y',
          rfc: '',
          direccion: '',
          direccionFiscal: '',
          telefono: '',
        ),
      );

      await proveedorController.actualizar(
        Proveedores(
          idProveedor: id,
          nombre: 'Proveedor Y Editado',
          rfc: '',
          direccion: '',
          direccionFiscal: '',
          telefono: '',
        ),
      );

      await proveedorController.eliminar(id);

      expect(await auditoria.obtenerFiltradas(tabla: 'Proveedores', accion: 'CREATE'), hasLength(1));
      expect(await auditoria.obtenerFiltradas(tabla: 'Proveedores', accion: 'EDIT'), hasLength(1));
      expect(await auditoria.obtenerFiltradas(tabla: 'Proveedores', accion: 'DELETE'), hasLength(1));
    });
  });
}
