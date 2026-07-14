import '../core/database/database_helper.dart';
import '../models/usuarios_model.dart';
import 'auditoria_controller.dart';

class UsuariosController {
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Usuarios usuario) async {
    final db = await DatabaseHelper().database;
    final id = await db.insert('Usuarios', usuario.toMap());

    await _auditoriaController.registrar(
      tabla: 'Usuarios',
      accion: 'CREATE',
      idRegistro: id,
      descripcion: 'Usuario ${usuario.nombre} creado',
    );

    return id;
  }

  Future<List<Usuarios>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query('Usuarios');

    return result.map((e) => Usuarios.fromMap(e)).toList();
  }

  Future<int> actualizar(Usuarios usuario) async {
    final db = await DatabaseHelper().database;

    final rows = await db.update(
      'Usuarios',
      usuario.toMap(),
      where: 'id_usuario = ?',
      whereArgs: [usuario.idUsuario],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Usuarios',
        accion: 'EDIT',
        idRegistro: usuario.idUsuario,
        descripcion: 'Usuario ${usuario.nombre} actualizado',
      );
    }

    return rows;
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;
    final usuario = await db.query(
      'Usuarios',
      columns: ['nombre'],
      where: 'id_usuario = ?',
      whereArgs: [id],
      limit: 1,
    );

    final rows = await db.delete(
      'Usuarios',
      where: 'id_usuario = ?',
      whereArgs: [id],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Usuarios',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: usuario.isNotEmpty
            ? 'Usuario ${usuario.first["nombre"]} eliminado'
            : 'Usuario eliminado',
      );
    }

    return rows;
  }
}
