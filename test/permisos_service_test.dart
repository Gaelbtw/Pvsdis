// Pruebas de PermisosService: la matriz de permisos por rol combinando los
// valores por defecto del código con los overrides guardados en BD.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/permisos.dart';
import 'package:pvapp/core/security/permisos_service.dart';
import 'package:pvapp/core/session/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final helper = DatabaseHelper();
  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_permisos_service');
    db = await helper.abrirEnRuta(join(tempDir.path, 'p.db'));
    DatabaseHelper.setTestDatabase(db);
    await PermisosService.instancia.cargar();
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    SessionManager.clear();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('Admin siempre tiene todos los permisos', () {
    for (final p in Permiso.values) {
      expect(PermisosService.instancia.tienePermisoDeRol('Admin', p), isTrue);
      expect(PermisosService.instancia.tienePermisoDeRol('Administrador', p), isTrue);
    }
  });

  test('sin overrides: Cajero no tiene ninguno, Supervisor tiene sus defaults', () {
    for (final p in Permiso.values) {
      expect(PermisosService.instancia.tienePermisoDeRol('Cajero', p), isFalse,
          reason: 'Cajero no debería tener $p por defecto');
    }
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.realizarDevoluciones), isTrue);
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.movimientosCaja), isTrue);
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.gestionarUsuarios), isFalse);
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.abrirConfiguracion), isFalse);
  });

  test('establecer concede un permiso y sobrevive a recargar desde BD', () async {
    await PermisosService.instancia.establecer('Cajero', Permiso.verGanancias, true);
    expect(PermisosService.instancia.tienePermisoDeRol('Cajero', Permiso.verGanancias), isTrue);

    await PermisosService.instancia.cargar();
    expect(PermisosService.instancia.tienePermisoDeRol('Cajero', Permiso.verGanancias), isTrue);
  });

  test('establecer puede quitar un permiso que venía por defecto', () async {
    await PermisosService.instancia.establecer('Supervisor', Permiso.realizarDevoluciones, false);
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.realizarDevoluciones), isFalse);

    await PermisosService.instancia.cargar();
    expect(PermisosService.instancia.tienePermisoDeRol('Supervisor', Permiso.realizarDevoluciones), isFalse);
  });

  test('establecer sobre Admin se ignora: Admin no puede perder permisos', () async {
    await PermisosService.instancia.establecer('Admin', Permiso.gestionarUsuarios, false);
    expect(PermisosService.instancia.tienePermisoDeRol('Admin', Permiso.gestionarUsuarios), isTrue);
  });

  test('puedeActual usa el rol de la sesión activa', () {
    SessionManager.setUser(id: 1, nombre: 'Caja', rol: 'Cajero');
    expect(PermisosService.instancia.puedeActual(Permiso.movimientosCaja), isFalse);

    SessionManager.setUser(id: 2, nombre: 'Sup', rol: 'Supervisor');
    expect(PermisosService.instancia.puedeActual(Permiso.movimientosCaja), isTrue);

    SessionManager.setUser(id: 3, nombre: 'Jefa', rol: 'Admin');
    expect(PermisosService.instancia.puedeActual(Permiso.gestionarUsuarios), isTrue);
  });
}
