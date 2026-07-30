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

  static bool get isSupervisor => currentUserRole == 'Supervisor';

  static bool get isCajero => !isAdmin && !isSupervisor;

  /// Etiqueta legible del rol para mostrar en la UI. Es SOLO presentación: el
  /// valor guardado en `Usuarios.rol` sigue siendo 'Admin'/'Cajero'/
  /// 'Supervisor', que es lo que comparan los permisos ([isAdmin], etc.).
  /// Acepta también 'Administrador' (el default histórico de esta clase).
  static String etiquetaRol(String rol) {
    switch (rol) {
      case 'Admin':
      case 'Administrador':
        return 'Administrador';
      case 'Cajero':
        return 'Cajero';
      case 'Supervisor':
        return 'Supervisor';
      default:
        return rol;
    }
  }

  /// Etiqueta del rol del usuario en sesión (ver [etiquetaRol]).
  static String get currentUserRoleLabel => etiquetaRol(currentUserRole);
}
