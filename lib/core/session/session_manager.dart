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
}
