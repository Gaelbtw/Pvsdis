import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import 'sync_outbox_deadletter.dart';

/// Una fila de `Sync_Outbox` presentada para la UI de "pendientes y problemas"
/// ([SyncProblemasView]). No expone el `datos_json` crudo (ruido para el
/// usuario); solo lo que sirve para entender qué cambio está atorado y por qué.
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.entidad,
    required this.operacion,
    required this.guidRegistro,
    required this.intentos,
    required this.fechaCreacion,
    this.ultimoError,
  });

  final int id;
  final String entidad;
  final String operacion;
  final String guidRegistro;
  final int intentos;
  final String fechaCreacion;
  final String? ultimoError;

  /// Fila apartada tras demasiados rechazos del backend: no se reintenta sola,
  /// necesita que el usuario decida (reintentar o descartar).
  bool get esDeadLetter => intentos == SyncOutboxDeadLetter.intentosFallidaPermanente;

  /// Fila esperando que se resuelva un prerrequisito (típicamente la sucursal
  /// del dispositivo): se reintenta sola en un ciclo posterior.
  bool get esperandoPrerrequisito => intentos == -1;

  factory OutboxItem.desdeFila(Map<String, Object?> f) => OutboxItem(
        id: f['id'] as int,
        entidad: f['entidad'] as String,
        operacion: f['operacion'] as String,
        guidRegistro: f['guid_registro'] as String,
        intentos: f['intentos'] as int,
        fechaCreacion: f['fecha_creacion'] as String,
        ultimoError: f['ultimo_error'] as String?,
      );
}

/// Lee y opera sobre `Sync_Outbox` para la vista de diagnóstico. Concentra las
/// consultas y las dos acciones manuales sobre una fila atorada (reintentar /
/// descartar) fuera del widget, para poder testearlas sin UI.
class SyncOutboxInspector {
  /// Cambios que todavía se subirán solos (cuenta normal de intentos o
  /// esperando prerrequisito). Excluye el dead-letter.
  Future<List<OutboxItem>> pendientes(DatabaseExecutor db) async {
    final filas = await db.query(
      'Sync_Outbox',
      where: 'intentos > ?',
      whereArgs: [SyncOutboxDeadLetter.intentosFallidaPermanente],
      orderBy: 'id ASC',
    );
    return filas.map(OutboxItem.desdeFila).toList();
  }

  /// Filas en dead-letter: rechazadas de forma persistente por el backend,
  /// necesitan intervención manual.
  Future<List<OutboxItem>> fallidas(DatabaseExecutor db) async {
    final filas = await db.query(
      'Sync_Outbox',
      where: 'intentos = ?',
      whereArgs: [SyncOutboxDeadLetter.intentosFallidaPermanente],
      orderBy: 'id ASC',
    );
    return filas.map(OutboxItem.desdeFila).toList();
  }

  /// Devuelve una fila en dead-letter a la cola normal (`intentos = 0`) para
  /// que el próximo drenado la reintente. Útil cuando el rechazo del backend
  /// era por una causa ya resuelta (p. ej. se corrigió un dato relacionado).
  Future<void> reintentar(DatabaseExecutor db, int id) async {
    await db.update(
      'Sync_Outbox',
      {'intentos': 0, 'ultimo_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina definitivamente una fila del outbox. Es pérdida de datos (ese
  /// cambio no llegará a la nube), así que la UI lo confirma antes de llamar.
  Future<void> descartar(DatabaseExecutor db, int id) async {
    await db.delete('Sync_Outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// Atajo para la vista: abre la base local y lee ambos grupos de una vez.
  Future<({List<OutboxItem> pendientes, List<OutboxItem> fallidas})> cargar() async {
    final db = await DatabaseHelper().database;
    return (pendientes: await pendientes(db), fallidas: await fallidas(db));
  }
}
