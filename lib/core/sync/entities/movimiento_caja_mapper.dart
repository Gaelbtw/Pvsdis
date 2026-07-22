import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// `Movimiento_Caja` (local, bitácora nueva de la Fase 3) <-> `MovimientoCaja`
/// (backend, `ClienteGana`).
///
/// `tipo_movimiento` local ya se declaró en la migración v19
/// (`_ensureBitacoraSyncTables`) con los mismos nombres exactos que el enum
/// backend (`'VentaEfectivo'`, `'VentaTarjeta'`, etc. -- ver
/// `EsqPos.Domain.Enums.TipoMovimientoCaja`), así que no hace falta tabla de
/// conversión, a diferencia de `metodo_pago` en `VentaMapper`/
/// `VentaPagoMapper`. `id_usuario` local es puramente informativo (columna
/// nullable sin FK, ver el comentario de la migración) -- el push usa
/// [usuarioIdSync], nunca esa columna.
class MovimientoCajaMapper extends EntityMapper {
  @override
  String get entidadBackend => 'MovimientoCaja';

  @override
  String get tablaLocal => 'Movimiento_Caja';

  @override
  String get columnaIdLocal => 'id_movimiento_caja';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Movimiento_Caja sin guid_sync (id local: ${filaLocal['id_movimiento_caja']}).');
    }

    final idCaja = filaLocal['id_caja'] as int;
    final cajaGuid = await resolver.guidPorIdLocal('Cajas', idCaja);
    if (cajaGuid == null) {
      throw StateError('Movimiento_Caja ${filaLocal['id_movimiento_caja']}: su Caja (id_caja=$idCaja) no tiene guid_sync.');
    }

    final idVentaReferencia = filaLocal['id_venta_referencia'] as int?;
    final ventaGuid = idVentaReferencia == null ? null : await resolver.guidPorIdLocal('Ventas', idVentaReferencia);

    final fecha = (filaLocal['fecha'] as String?) ?? DateTime.now().toUtc().toIso8601String();

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': fecha,
      'fechaModificacion': fecha,
      'isDeleted': false,
      'cajaSesionId': cajaGuid,
      'tipoMovimiento': filaLocal['tipo_movimiento'],
      'monto': (filaLocal['monto'] as num?)?.toDouble() ?? 0,
      'concepto': filaLocal['concepto'],
      'fecha': fecha,
      'referenciaVentaId': ventaGuid,
      'usuarioId': usuarioIdSync,
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final guid = elementoBackend['id'] as String;

    final cajaGuid = elementoBackend['cajaSesionId'] as String;
    final idCajaLocal = await resolver.idLocalPorGuid('Cajas', 'id_caja', cajaGuid);
    if (idCajaLocal == null) return;

    final ventaGuid = elementoBackend['referenciaVentaId'] as String?;
    final idVentaLocal = ventaGuid == null ? null : await resolver.idLocalPorGuid('Ventas', 'id_venta', ventaGuid);

    final valoresLocales = <String, Object?>{
      'id_caja': idCajaLocal,
      'tipo_movimiento': elementoBackend['tipoMovimiento'],
      'monto': (elementoBackend['monto'] as num?)?.toDouble() ?? 0,
      'concepto': elementoBackend['concepto'],
      'fecha': elementoBackend['fecha'],
      'id_venta_referencia': idVentaLocal,
    };

    final idLocalExistente = await resolver.idLocalPorGuid(tablaLocal, columnaIdLocal, guid);

    if (idLocalExistente == null) {
      final idNuevo = await db.insert(tablaLocal, {...valoresLocales, 'guid_sync': guid});
      resolver.registrar(tablaLocal, guid, idNuevo);
    } else {
      await db.update(tablaLocal, valoresLocales, where: '$columnaIdLocal = ?', whereArgs: [idLocalExistente]);
    }
  }
}
