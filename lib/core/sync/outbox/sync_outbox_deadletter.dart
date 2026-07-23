/// Constantes compartidas del "dead-letter" de `Sync_Outbox`: una fila que
/// falló demasiadas veces se aparta para no reintentarse en cada ciclo (un
/// "poison message" -- típicamente datos que el backend rechaza siempre). Las
/// usan tanto el drenado ([SyncOutboxDrainer], que marca la fila) como el
/// conteo de pendientes ([SyncScheduler], que la excluye), sin que uno dependa
/// del otro.
class SyncOutboxDeadLetter {
  SyncOutboxDeadLetter._();

  /// `Sync_Outbox.intentos == -2` marca una fila que ya no se reintenta y
  /// requiere intervención manual. `-1` sigue siendo "esperando prerrequisito"
  /// (reintentable en un ciclo posterior); `>= 0` es la cuenta normal de
  /// intentos de red.
  static const int intentosFallidaPermanente = -2;

  /// Cuántos fallos de red consecutivos se toleran antes de apartar la fila.
  static const int maxIntentos = 5;
}
