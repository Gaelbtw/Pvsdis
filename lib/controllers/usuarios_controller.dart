import '../core/database/database_helper.dart';
import '../core/database/db_exceptions.dart';
import '../core/security/password_hasher.dart';
import '../models/usuarios_model.dart';
import 'auditoria_controller.dart';

class UsuariosController {
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Usuarios usuario) async {
    final db = await DatabaseHelper().database;

    final datos = usuario.toMap();
    datos['contra'] = PasswordHasher.hash(usuario.contra);

    final id = await db.insert('Usuarios', datos);

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

  /// Actualiza los datos del usuario. La contraseña solo se modifica cuando
  /// se pasa [nuevaContrasena] (no vacía); si se omite, se conserva el hash
  /// ya almacenado en vez de sobrescribirlo.
  Future<int> actualizar(Usuarios usuario, {String? nuevaContrasena}) async {
    final db = await DatabaseHelper().database;

    final datos = usuario.toMap();
    if (nuevaContrasena != null && nuevaContrasena.isNotEmpty) {
      datos['contra'] = PasswordHasher.hash(nuevaContrasena);
    } else {
      datos.remove('contra');
    }

    final rows = await db.update(
      'Usuarios',
      datos,
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

    final rows = await ejecutarConMensajeDeIntegridad(
      () => db.delete(
        'Usuarios',
        where: 'id_usuario = ?',
        whereArgs: [id],
      ),
      'No se puede eliminar: el usuario tiene ventas o compras registradas.',
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
