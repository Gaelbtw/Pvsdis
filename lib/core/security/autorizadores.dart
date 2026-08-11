import 'package:sqflite/sqflite.dart';

/// Comprueba contra la base de datos que un id de usuario corresponda de
/// verdad a una cuenta de administrador.
///
/// Existe porque `validarPermisoDescuento` (en
/// `lib/core/utils/descuento_utils.dart`) solo podía comprobar que
/// `descuentoAutorizadoPor` no fuera `null`. Esa función es deliberadamente
/// pura —no toca base de datos ni UI— así que la verificación real tiene que
/// entrar desde fuera, ya resuelta.
///
/// El diálogo de autorización sí pide usuario y contraseña de un
/// administrador, pero esa comprobación vive en la vista: un carrito armado
/// por otro camino (o una vista futura que se olvide del diálogo) podía
/// mandar cualquier id —incluido el del propio cajero— y pasaba el control.
/// La red de seguridad del controlador existe precisamente para no depender
/// de que la UI se haya comportado bien.
///
/// Devuelve `false` si [idUsuario] es `null`, si no existe, o si su rol no es
/// administrador.
Future<bool> esAdministrador(DatabaseExecutor db, int? idUsuario) async {
  if (idUsuario == null) return false;

  final filas = await db.query(
    'Usuarios',
    columns: ['rol'],
    where: 'id_usuario = ?',
    whereArgs: [idUsuario],
    limit: 1,
  );
  if (filas.isEmpty) return false;

  final rol = filas.first['rol']?.toString();
  return rol == 'Admin' || rol == 'Administrador';
}
