import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../session/session_manager.dart';
import 'permisos.dart';

/// Fuente única de verdad de la matriz de permisos en tiempo de ejecución.
///
/// Carga en memoria los ajustes guardados en la tabla `Rol_Permisos` (solo se
/// guardan las casillas que el administrador cambió respecto al valor por
/// defecto) y responde `tienePermiso` combinando esos overrides con
/// [permisosPorDefecto]. El Admin siempre tiene todo.
///
/// Se carga una vez tras el login (ver login/main) y se recarga sola cuando el
/// administrador edita la matriz con [establecer].
class PermisosService {
  PermisosService._();
  static final PermisosService instancia = PermisosService._();

  final Map<String, Map<Permiso, bool>> _overrides = {};
  bool cargado = false;

  Future<void> cargar() async {
    final db = await DatabaseHelper().database;
    final rows = await db.query('Rol_Permisos');

    _overrides.clear();
    for (final row in rows) {
      final rol = row['rol']?.toString();
      final permiso = permisoDesdeClave(row['permiso']?.toString() ?? '');
      if (rol == null || permiso == null) continue;
      final permitido = (row['permitido'] as num?) != null && (row['permitido'] as num) != 0;
      (_overrides[rol] ??= {})[permiso] = permitido;
    }
    cargado = true;
  }

  /// `true` si [rol] tiene [permiso]. Admin siempre; el resto según el override
  /// guardado o, si no hay, el valor por defecto del rol.
  bool tienePermisoDeRol(String rol, Permiso permiso) {
    if (rol == Roles.admin || rol == 'Administrador') return true;
    final override = _overrides[rol]?[permiso];
    if (override != null) return override;
    return permisosPorDefecto[rol]?.contains(permiso) ?? false;
  }

  /// `true` si el usuario con la sesión actual tiene [permiso]. Sin sesión
  /// activa no hay permisos: se responde `false` sin siquiera mirar la
  /// matriz (ver el default cerrado de [SessionManager]).
  bool puedeActual(Permiso permiso) => SessionManager.haySesion &&
      tienePermisoDeRol(SessionManager.currentUserRole, permiso);

  /// Descarta la matriz cargada en memoria. Se llama al cerrar sesión para
  /// que la del usuario siguiente no herede los overrides del anterior
  /// mientras `cargar()` vuelve a correr.
  void limpiar() {
    _overrides.clear();
    cargado = false;
  }

  /// Guarda (upsert) un cambio de la matriz y lo refleja en memoria. Ignora el
  /// Admin: siempre tiene todo, no es configurable.
  Future<void> establecer(String rol, Permiso permiso, bool permitido) async {
    if (rol == Roles.admin || rol == 'Administrador') return;

    final db = await DatabaseHelper().database;
    await db.insert(
      'Rol_Permisos',
      {'rol': rol, 'permiso': permiso.clave, 'permitido': permitido ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    (_overrides[rol] ??= {})[permiso] = permitido;
  }
}
