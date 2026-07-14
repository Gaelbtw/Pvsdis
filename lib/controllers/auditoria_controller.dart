import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../models/auditoria_model.dart';

class AuditoriaController {
  final dbHelper = DatabaseHelper();

  Future<int> registrar({
    required String tabla,
    required String accion,
    required String descripcion,
    int? idRegistro,
    String? usuario,
  }) async {
    final db = await dbHelper.database;
    final rol = _rolVisible(SessionManager.currentUserRole);
    final usuarioActual = '$rol: ${SessionManager.currentUserName}';

    return await db.insert('Auditorias', {
      "fecha_hora": DateTime.now().toIso8601String(),
      "usuario": usuario ?? usuarioActual,
      "tabla": tabla,
      "accion": accion,
      "id_registro": idRegistro,
      "descripcion": descripcion,
    });
  }

  Future<List<Auditoria>> obtenerTodas() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'Auditorias',
      orderBy: 'fecha_hora DESC',
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

  Future<List<Auditoria>> obtenerPorTablas(List<String> tablas) async {
    if (tablas.isEmpty) return [];

    final db = await dbHelper.database;
    final placeholders = List.filled(tablas.length, '?').join(',');
    final result = await db.query(
      'Auditorias',
      where: 'tabla IN ($placeholders)',
      whereArgs: tablas,
      orderBy: 'fecha_hora DESC',
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

  String _rolVisible(String rol) {
    if (rol == 'Administrador') return 'Admin';
    return rol;
  }
}
