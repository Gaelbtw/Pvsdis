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
    int? idUsuario,
    int? idCaja,
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
      "id_usuario": idUsuario ?? SessionManager.currentUserId,
      "id_caja": idCaja,
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

  /// Consulta usada por el reporte de movimientos por usuario: reutiliza la
  /// misma tabla `Auditorias` que ya alimentan ventas, caja, inventario,
  /// clientes, proveedores, usuarios, promociones, apartados y devoluciones,
  /// solo que con filtros combinables (todos opcionales).
  Future<List<Auditoria>> obtenerFiltradas({
    int? idUsuario,
    String? accion,
    String? tabla,
    int? idCaja,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await dbHelper.database;

    final condiciones = <String>[];
    final argumentos = <Object?>[];

    if (idUsuario != null) {
      condiciones.add('id_usuario = ?');
      argumentos.add(idUsuario);
    }
    if (accion != null && accion.isNotEmpty) {
      condiciones.add('accion = ?');
      argumentos.add(accion);
    }
    if (tabla != null && tabla.isNotEmpty) {
      condiciones.add('tabla = ?');
      argumentos.add(tabla);
    }
    if (idCaja != null) {
      condiciones.add('id_caja = ?');
      argumentos.add(idCaja);
    }
    if (desde != null) {
      condiciones.add('fecha_hora >= ?');
      argumentos.add(desde.toIso8601String());
    }
    if (hasta != null) {
      condiciones.add('fecha_hora <= ?');
      argumentos.add(hasta.toIso8601String());
    }

    final result = await db.query(
      'Auditorias',
      where: condiciones.isEmpty ? null : condiciones.join(' AND '),
      whereArgs: condiciones.isEmpty ? null : argumentos,
      orderBy: 'fecha_hora DESC',
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

  String _rolVisible(String rol) {
    if (rol == 'Administrador') return 'Admin';
    return rol;
  }
}
