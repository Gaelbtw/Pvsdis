/// Catálogo de permisos configurables por rol (la "matriz de permisos") y sus
/// valores por defecto. Los roles son fijos: Cajero, Supervisor y Admin.
///
/// El Admin SIEMPRE tiene todos los permisos (no es configurable): es la
/// cuenta que administra la matriz, así que no puede quitarse acceso a sí
/// misma. Para Cajero y Supervisor, [PermisosService] lee la matriz guardada
/// (tabla `Rol_Permisos`) y usa estos valores por defecto para cualquier
/// combinación rol/permiso que aún no se haya personalizado.
library;

enum Permiso {
  realizarDevoluciones,
  movimientosCaja,
  verGanancias,
  gestionarProductos,
  ajustarInventario,
  gestionarUsuarios,
  abrirConfiguracion,
}

extension PermisoInfo on Permiso {
  /// Clave estable para persistir en BD (no cambiar: rompería la matriz
  /// guardada de instalaciones existentes).
  String get clave => switch (this) {
        Permiso.realizarDevoluciones => 'realizar_devoluciones',
        Permiso.movimientosCaja => 'movimientos_caja',
        Permiso.verGanancias => 'ver_ganancias',
        Permiso.gestionarProductos => 'gestionar_productos',
        Permiso.ajustarInventario => 'ajustar_inventario',
        Permiso.gestionarUsuarios => 'gestionar_usuarios',
        Permiso.abrirConfiguracion => 'abrir_configuracion',
      };

  String get etiqueta => switch (this) {
        Permiso.realizarDevoluciones => 'Devoluciones y cancelaciones',
        Permiso.movimientosCaja => 'Entradas/salidas de efectivo',
        Permiso.verGanancias => 'Ver ganancias y costos',
        Permiso.gestionarProductos => 'Crear y editar productos',
        Permiso.ajustarInventario => 'Ajustar inventario',
        Permiso.gestionarUsuarios => 'Administrar usuarios',
        Permiso.abrirConfiguracion => 'Abrir configuración',
      };

  String get descripcion => switch (this) {
        Permiso.realizarDevoluciones => 'Cancelar ventas y devolver productos.',
        Permiso.movimientosCaja => 'Registrar dinero que entra o sale de la caja.',
        Permiso.verGanancias => 'Ver reportes con márgenes, costos y utilidad.',
        Permiso.gestionarProductos => 'Alta y edición del catálogo de productos.',
        Permiso.ajustarInventario => 'Modificar existencias con un ajuste manual.',
        Permiso.gestionarUsuarios => 'Crear, editar y desactivar usuarios.',
        Permiso.abrirConfiguracion => 'Entrar al panel de configuración del sistema.',
      };
}

/// Busca un permiso por su [Permiso.clave]. `null` si no corresponde a ninguno
/// (por ejemplo una clave vieja guardada en BD que ya no existe en el código).
Permiso? permisoDesdeClave(String clave) {
  for (final p in Permiso.values) {
    if (p.clave == clave) return p;
  }
  return null;
}

/// Roles fijos del sistema. El orden es de menor a mayor privilegio, útil para
/// mostrarlos como columnas en la matriz.
class Roles {
  static const cajero = 'Cajero';
  static const supervisor = 'Supervisor';
  static const admin = 'Admin';

  /// Roles configurables en la matriz (Admin se omite: siempre tiene todo).
  static const configurables = [cajero, supervisor];

  /// Todos los roles asignables a un usuario.
  static const todos = [cajero, supervisor, admin];
}

/// Matriz por defecto para los roles configurables. El Admin no aparece aquí
/// porque siempre tiene todos los permisos.
const Map<String, Set<Permiso>> permisosPorDefecto = {
  Roles.cajero: <Permiso>{},
  Roles.supervisor: {
    Permiso.realizarDevoluciones,
    Permiso.movimientosCaja,
    Permiso.verGanancias,
    Permiso.gestionarProductos,
    Permiso.ajustarInventario,
  },
};

/// Valida un PIN numérico (4 a 6 dígitos). Devuelve un mensaje de error o
/// `null` si es válido. El PIN es opcional; esta validación solo aplica cuando
/// el usuario decide fijar uno.
String? validarPin(String pin) {
  if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
    return 'El PIN debe tener entre 4 y 6 dígitos.';
  }
  return null;
}
