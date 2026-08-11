/// Sesión del usuario que está operando la app.
///
/// El estado por defecto (y el posterior a [clear]) es "sin sesión": rol
/// vacío y, por lo tanto, sin ningún privilegio. Antes el valor inicial era
/// `'Administrador'`, así que cualquier código que consultara permisos antes
/// del login —o después de cerrar sesión— pasaba como administrador. Un
/// default de seguridad debe fallar cerrado, no abierto.
class SessionManager {
  static int? currentUserId;
  static String currentUserName = '';
  static String currentUserRole = '';

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
    currentUserName = '';
    currentUserRole = '';
  }

  /// `true` si hay un usuario realmente identificado.
  static bool get haySesion => currentUserId != null;

  /// Id del usuario en sesión, o excepción si no hay ninguno.
  ///
  /// Debe usarse en cualquier operación que deje rastro contable (ventas,
  /// apertura/cierre de caja, movimientos de efectivo, devoluciones). Antes
  /// esos controladores hacían `SessionManager.currentUserId ?? 1`, que
  /// atribuía la operación en silencio al usuario con id 1 —normalmente el
  /// administrador—, falseando la auditoría y los reportes por usuario.
  static int get requiredUserId {
    final id = currentUserId;
    if (id == null) {
      throw Exception(
        'No hay una sesión de usuario activa. Vuelve a iniciar sesión antes de continuar.',
      );
    }
    return id;
  }

  /// Acepta tanto "Admin" (valor real guardado en la tabla Usuarios) como
  /// "Administrador" (valor por defecto histórico de esta clase), para no
  /// depender de cuál de los dos strings esté en uso.
  ///
  /// Este getter y [isSupervisor]/[isCajero] sirven SOLO para decidir la
  /// forma de la UI (qué módulos listar) y para el caso especial de "esto es
  /// exclusivo del administrador". Para cualquier permiso concreto y
  /// configurable se usa `PermisosService.puedeActual(...)`, que es la fuente
  /// única de verdad.
  static bool get isAdmin =>
      haySesion && (currentUserRole == 'Admin' || currentUserRole == 'Administrador');

  static bool get isSupervisor => haySesion && currentUserRole == 'Supervisor';

  /// Sin sesión no se es "cajero": no se es nada. Que un rol desconocido
  /// caiga en cajero es intencional (es el de menor privilegio), pero la
  /// ausencia de sesión se trata aparte con [haySesion].
  static bool get isCajero => haySesion && !isAdmin && !isSupervisor;

  /// Normaliza el rol al valor canónico que se guarda en `Usuarios.rol`.
  /// Existe porque `'Administrador'` fue durante un tiempo el valor por
  /// defecto de esta clase y quedó disperso en bitácoras y comparaciones.
  /// Punto único para no repetir `rol == 'Administrador' ? 'Admin' : rol` en
  /// cada controlador que escribe una auditoría.
  static String rolCanonico(String rol) => rol == 'Administrador' ? 'Admin' : rol;

  /// Rol canónico del usuario en sesión (ver [rolCanonico]).
  static String get currentUserRoleCanonico => rolCanonico(currentUserRole);

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
      case '':
        return 'Sin sesión';
      default:
        return rol;
    }
  }

  /// Etiqueta del rol del usuario en sesión (ver [etiquetaRol]).
  static String get currentUserRoleLabel => etiquetaRol(currentUserRole);
}
