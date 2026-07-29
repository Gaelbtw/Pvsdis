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

    final pin = usuario.pin?.trim();
    if (pin != null && pin.isNotEmpty) {
      datos['pin'] = PasswordHasher.hash(pin);
    }

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

  /// Indica si algún otro usuario ya usa este [pin]. Como los PIN se guardan
  /// hasheados, no se puede comparar por igualdad en SQL: se verifica uno por
  /// uno con bcrypt. [exceptoId] excluye al propio usuario al editarlo.
  Future<bool> pinEnUso(String pin, {int? exceptoId}) async {
    final db = await DatabaseHelper().database;
    final filas = await db.query(
      'Usuarios',
      columns: ['id_usuario', 'pin'],
      where: 'pin IS NOT NULL',
    );

    for (final fila in filas) {
      if (exceptoId != null && fila['id_usuario'] == exceptoId) continue;
      final hash = fila['pin']?.toString() ?? '';
      if (PasswordHasher.verify(pin, hash)) return true;
    }
    return false;
  }

  /// Actualiza los datos del usuario. La contraseña solo se modifica cuando
  /// se pasa [nuevaContrasena] (no vacía); si se omite, se conserva el hash
  /// ya almacenado en vez de sobrescribirlo.
  ///
  /// El PIN se controla con [nuevoPin]: `null` lo deja como estaba, `''` lo
  /// borra (login por PIN deshabilitado para ese usuario) y cualquier otro
  /// valor lo fija (hasheado).
  Future<int> actualizar(Usuarios usuario, {String? nuevaContrasena, String? nuevoPin}) async {
    final db = await DatabaseHelper().database;

    final datos = usuario.toMap();
    if (nuevaContrasena != null && nuevaContrasena.isNotEmpty) {
      datos['contra'] = PasswordHasher.hash(nuevaContrasena);
    } else {
      datos.remove('contra');
    }

    if (nuevoPin != null) {
      final pin = nuevoPin.trim();
      datos['pin'] = pin.isEmpty ? null : PasswordHasher.hash(pin);
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
