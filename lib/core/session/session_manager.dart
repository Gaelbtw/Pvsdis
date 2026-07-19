class SessionManager {
  static int? currentUserId;
  static String currentUserName = "Admin";
  static String currentUserRole = "Administrador";

  static void setUser({
    required int? id,
    required String nombre,
    required String rol,
  }) {
    currentUserId = id;
    currentUserName = nombre;
    currentUserRole = rol;
  }

  static void clear() {
    currentUserId = null;
    currentUserName = "Admin";
    currentUserRole = "Administrador";
  }

  /// Permiso centralizado: acepta tanto "Admin" (valor real guardado en la
  /// tabla Usuarios) como "Administrador" (valor por defecto histórico de
  /// esta clase), para no depender de cuál de los dos strings esté en uso.
  static bool get isAdmin =>
      currentUserRole == 'Admin' || currentUserRole == 'Administrador';

  static bool get isCajero => !isAdmin;
}
