// Pruebas del login por PIN (Authcontroller.loginConPin) y del manejo de PIN
// en UsuariosController (hasheo, unicidad, conservar/borrar al editar).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/auth_controller.dart';
import 'package:pvapp/controllers/usuarios_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/models/usuarios_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final helper = DatabaseHelper();
  late Directory tempDir;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_pin');
    db = await helper.abrirEnRuta(join(tempDir.path, 'p.db'));
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('loginConPin identifica al usuario dueño del PIN', () async {
    final ctrl = UsuariosController();
    await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));
    await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Jefa', contra: 'secreta2', rol: 'Admin', pin: '9999'));

    final auth = Authcontroller();
    final r = await auth.loginConPin('1234');
    expect(r.status, LoginStatus.success);
    expect(r.usuario?['nombre'], 'Caja');

    final r2 = await auth.loginConPin('9999');
    expect(r2.usuario?['nombre'], 'Jefa');
  });

  test('loginConPin con un PIN inexistente no encuentra usuario', () async {
    final ctrl = UsuariosController();
    await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));

    final r = await Authcontroller().loginConPin('0000');
    expect(r.status, LoginStatus.usuarioNoEncontrado);
    expect(r.usuario, isNull);
  });

  test('el PIN se guarda hasheado, nunca en texto plano', () async {
    final ctrl = UsuariosController();
    final id = await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));

    final fila = (await db.query('Usuarios', where: 'id_usuario = ?', whereArgs: [id])).first;
    expect(fila['pin'], isNot('1234'));
    expect((fila['pin'] as String).startsWith(r'$2'), isTrue, reason: 'debe ser un hash bcrypt');
  });

  test('pinEnUso detecta duplicados y excluye al propio usuario', () async {
    final ctrl = UsuariosController();
    final id = await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));

    expect(await ctrl.pinEnUso('1234'), isTrue);
    expect(await ctrl.pinEnUso('1234', exceptoId: id), isFalse);
    expect(await ctrl.pinEnUso('5678'), isFalse);
  });

  test('actualizar con nuevoPin vacío borra el PIN (deshabilita login por PIN)', () async {
    final ctrl = UsuariosController();
    final id = await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));

    await ctrl.actualizar(Usuarios(idUsuario: id, nombre: 'Caja', contra: '', rol: 'Cajero'), nuevoPin: '');

    final fila = (await db.query('Usuarios', where: 'id_usuario = ?', whereArgs: [id])).first;
    expect(fila['pin'], isNull);
  });

  test('actualizar sin nuevoPin conserva el PIN existente', () async {
    final ctrl = UsuariosController();
    final id = await ctrl.insertar(Usuarios(idUsuario: null, nombre: 'Caja', contra: 'secreta1', rol: 'Cajero', pin: '1234'));

    await ctrl.actualizar(Usuarios(idUsuario: id, nombre: 'Caja Renombrada', contra: '', rol: 'Cajero'));

    final r = await Authcontroller().loginConPin('1234');
    expect(r.status, LoginStatus.success);
    expect(r.usuario?['nombre'], 'Caja Renombrada');
  });
}
