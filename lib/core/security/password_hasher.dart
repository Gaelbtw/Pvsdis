import 'package:bcrypt/bcrypt.dart';

/// Hashing, verificación y política mínima de contraseñas.
///
/// Punto único de la app para tratar contraseñas: nadie más debería llamar
/// a `BCrypt` directamente ni comparar contraseñas por igualdad de texto.
class PasswordHasher {
  static const int minLength = 6;

  /// bcrypt siempre produce hashes con prefijo $2a$/$2b$/$2y$.
  static final RegExp _bcryptFormat = RegExp(r'^\$2[aby]\$');

  static String hash(String plainPassword) {
    return BCrypt.hashpw(plainPassword, BCrypt.gensalt());
  }

  /// Compara una contraseña en texto plano contra el valor almacenado.
  /// Si el valor almacenado no tiene formato de hash bcrypt (por ejemplo,
  /// datos corruptos), se rechaza en vez de intentar comparar en texto plano.
  static bool verify(String plainPassword, String storedValue) {
    if (!isHashed(storedValue)) return false;
    return BCrypt.checkpw(plainPassword, storedValue);
  }

  static bool isHashed(String value) => _bcryptFormat.hasMatch(value);

  /// Devuelve un mensaje de error si la contraseña no cumple la política
  /// mínima, o `null` si es válida.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'La contraseña debe tener al menos $minLength caracteres';
    }
    return null;
  }
}
