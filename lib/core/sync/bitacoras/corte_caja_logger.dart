import 'package:sqflite/sqflite.dart';

import '../auth_service.dart';
import '../outbox/sync_outbox_writer.dart';

/// Escribe una fila en `Corte_Caja` (bitácora nueva de la Fase 3) al cerrar
/// una caja -- un snapshot inmutable de los totales del cierre, separado de
/// `Cajas` (que también los guarda, pero como columnas mutables de la
/// sesión). Mismo patrón que [MovimientoInventarioLogger], incluido el uso
/// de [SyncOutboxWriter] para encolar el corte.
class CorteCajaLogger {
  CorteCajaLogger({SyncOutboxWriter? outboxWriter})
      : _outboxWriter = outboxWriter ?? SyncOutboxWriter(authService: AuthService.instancia);

  final SyncOutboxWriter _outboxWriter;

  Future<int> registrar(
    DatabaseExecutor db, {
    required int idCaja,
    required double totalEfectivoSistema,
    required double totalTarjetaSistema,
    required double totalTransferenciaSistema,
    required double totalEfectivoContado,
    required double diferencia,
  }) {
    return _outboxWriter.crear(
      db,
      entidad: 'CorteCaja',
      tabla: 'Corte_Caja',
      values: {
        'id_caja': idCaja,
        'total_efectivo_sistema': totalEfectivoSistema,
        'total_tarjeta_sistema': totalTarjetaSistema,
        'total_transferencia_sistema': totalTransferenciaSistema,
        'total_efectivo_contado': totalEfectivoContado,
        'diferencia': diferencia,
        'fecha_corte': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
