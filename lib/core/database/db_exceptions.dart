import 'package:sqflite/sqflite.dart';

/// Ejecuta una operación de base de datos y, si SQLite la rechaza por una
/// violación de llave foránea (por ejemplo, borrar un registro que todavía
/// tiene ventas, compras o pedidos asociados), la convierte en un mensaje
/// claro para quien llama en vez de dejar pasar la excepción técnica cruda
/// de SQLite.
Future<T> ejecutarConMensajeDeIntegridad<T>(
  Future<T> Function() accion,
  String mensajeSiHayDependientes,
) async {
  try {
    return await accion();
  } on DatabaseException catch (e) {
    if (e.toString().toLowerCase().contains('foreign key constraint failed')) {
      throw Exception(mensajeSiHayDependientes);
    }
    rethrow;
  }
}

/// Red de seguridad a nivel de base de datos para violaciones de unicidad
/// (por ejemplo, dos productos con el mismo código de barras). La UI ya
/// valida esto antes de guardar, pero esto cubre condiciones de carrera u
/// otros puntos de entrada que no pasen por esa validación.
Future<T> ejecutarConMensajeDeDuplicado<T>(
  Future<T> Function() accion,
  String mensajeSiEsDuplicado,
) async {
  try {
    return await accion();
  } on DatabaseException catch (e) {
    if (e.isUniqueConstraintError()) {
      throw Exception(mensajeSiEsDuplicado);
    }
    rethrow;
  }
}
