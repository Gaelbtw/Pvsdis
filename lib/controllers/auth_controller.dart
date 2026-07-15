import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/security/password_hasher.dart';

enum LoginStatus { success, usuarioNoEncontrado, contrasenaIncorrecta }

class LoginResult {
  final LoginStatus status;
  final Map<String, dynamic>? usuario;

  const LoginResult(this.status, this.usuario);
}

class Authcontroller {
  final dbHelper = DatabaseHelper();

  Future<LoginResult> login(String nombre, String password) async {
    final db = await dbHelper.database;

    final result = await db.query(
      'Usuarios',
      where: 'LOWER(nombre) = ?',
      whereArgs: [nombre.toLowerCase()],
      limit: 1,
    );

    if (result.isEmpty) {
      return const LoginResult(LoginStatus.usuarioNoEncontrado, null);
    }

    final usuario = result.first;
    final contrasenaAlmacenada = usuario['contra']?.toString() ?? '';

    if (!PasswordHasher.verify(password, contrasenaAlmacenada)) {
      return const LoginResult(LoginStatus.contrasenaIncorrecta, null);
    }

    return LoginResult(LoginStatus.success, usuario);
  }

  /// Indica si ya existe al menos un usuario registrado. Se usa para saber
  /// si la app debe pedir crear la cuenta de administrador (primer arranque)
  /// en vez de mostrar el login.
  Future<bool> existenUsuarios() async {
    final db = await dbHelper.database;
    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM Usuarios'),
        ) ??
        0;
    return total > 0;
  }
}
