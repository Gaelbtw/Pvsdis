import '../core/database/database_helper.dart';

class Authcontroller {
  final dbHelper = DatabaseHelper();

  Future<Map<String, dynamic>?> login(String nombre, String password) async {
  final db = await dbHelper.database;

  final result = await db.query(
    'Usuarios',
    where: 'LOWER(nombre) = ? AND contra = ?',
    whereArgs: [nombre.toLowerCase(), password],
  );

  return result.isNotEmpty ? result.first : null;
  }
}