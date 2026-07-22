import 'package:sqflite/sqflite.dart';

import '../auth_service.dart';
import '../outbox/sync_outbox_writer.dart';

/// Escribe una fila en `Movimiento_Inventario` (bitácora nueva de la
/// Fase 3, ver `database_helper.dart::_ensureBitacoraSyncTables`) cada vez
/// que un controlador ajusta `Inventario.cantidad`. Mismo patrón que
/// `AuditoriaController`: un campo en cada controlador que la usa, llamado
/// explícitamente en cada punto de escritura -- los controladores CRUD no
/// deben saber nada de mappers/outbox más allá de esto.
///
/// [tipoMovimiento] debe ser uno de los valores del CHECK de la tabla
/// (`'EntradaCompra'`, `'SalidaVenta'`, `'AjustePositivo'`,
/// `'AjusteNegativo'`, `'TransferenciaEntrada'`, `'TransferenciaSalida'`,
/// `'DevolucionVenta'`, `'DevolucionCompra'`) -- son los mismos nombres
/// exactos que el enum `TipoMovimientoInventario` del backend, a propósito
/// (ver `MovimientoInventarioMapper`), así que no hace falta traducir nada
/// al sincronizar.
///
/// Usa [SyncOutboxWriter] (no `DatabaseHelper.insertarConGuidSync` directo)
/// desde la Fase 3f: cada movimiento registrado queda encolado para push de
/// una vez, sin que el controlador que llama tenga que saberlo.
class MovimientoInventarioLogger {
  MovimientoInventarioLogger({SyncOutboxWriter? outboxWriter})
      : _outboxWriter = outboxWriter ?? SyncOutboxWriter(authService: AuthService.instancia);

  final SyncOutboxWriter _outboxWriter;

  Future<int> registrar(
    DatabaseExecutor db, {
    required int idProducto,
    required String tipoMovimiento,
    required int cantidad,
    required int cantidadAnterior,
    required int cantidadNueva,
    String? motivo,
    String? referenciaTipo,
    int? referenciaId,
  }) {
    return _outboxWriter.crear(
      db,
      entidad: 'MovimientoInventario',
      tabla: 'Movimiento_Inventario',
      values: {
        'id_producto': idProducto,
        'tipo_movimiento': tipoMovimiento,
        'cantidad': cantidad,
        'cantidad_anterior': cantidadAnterior,
        'cantidad_nueva': cantidadNueva,
        'motivo': motivo,
        'referencia_tipo': referenciaTipo,
        'referencia_id': referenciaId,
        'fecha': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}
