import 'package:sqflite/sqflite.dart';

/// Lee/escribe `Sync_Pull_Estado` (tabla creada en la migración v19): el
/// cursor incremental por entidad que le permite a [SyncPullRunner] pedir
/// solo lo nuevo (`desde: ultimaFechaModificacion`) en vez de traer el
/// catálogo completo en cada ciclo de sync.
class SyncPullCursorStore {
  Future<DateTime?> obtenerUltimaFecha(DatabaseExecutor db, String entidad) async {
    final filas = await db.query('Sync_Pull_Estado', where: 'entidad = ?', whereArgs: [entidad], limit: 1);
    if (filas.isEmpty) return null;

    final valor = filas.first['ultima_fecha_modificacion'] as String?;
    return valor == null ? null : DateTime.parse(valor);
  }

  Future<void> guardarUltimaFecha(DatabaseExecutor db, String entidad, DateTime fecha) async {
    await db.insert(
      'Sync_Pull_Estado',
      {'entidad': entidad, 'ultima_fecha_modificacion': fecha.toUtc().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
