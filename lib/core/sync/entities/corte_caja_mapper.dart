import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// `Corte_Caja` (local, bitácora nueva de la Fase 3) <-> `CorteCaja`
/// (backend, `ClienteGana`). Mapeo directo, sin conversiones: los 4 totales
/// y la diferencia ya se calculan del lado local exactamente como los
/// espera el backend (ver `CajaController._computarResumen`).
class CorteCajaMapper extends EntityMapper {
  @override
  String get entidadBackend => 'CorteCaja';

  @override
  String get tablaLocal => 'Corte_Caja';

  @override
  String get columnaIdLocal => 'id_corte';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Corte_Caja sin guid_sync (id local: ${filaLocal['id_corte']}).');
    }

    final idCaja = filaLocal['id_caja'] as int;
    final cajaGuid = await resolver.guidPorIdLocal('Cajas', idCaja);
    if (cajaGuid == null) {
      throw StateError('Corte_Caja ${filaLocal['id_corte']}: su Caja (id_caja=$idCaja) no tiene guid_sync.');
    }

    final fecha = (filaLocal['fecha_corte'] as String?) ?? DateTime.now().toUtc().toIso8601String();

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': fecha,
      'fechaModificacion': fecha,
      'isDeleted': false,
      'cajaSesionId': cajaGuid,
      'totalEfectivoSistema': (filaLocal['total_efectivo_sistema'] as num?)?.toDouble() ?? 0,
      'totalTarjetaSistema': (filaLocal['total_tarjeta_sistema'] as num?)?.toDouble() ?? 0,
      'totalTransferenciaSistema': (filaLocal['total_transferencia_sistema'] as num?)?.toDouble() ?? 0,
      'totalEfectivoContado': (filaLocal['total_efectivo_contado'] as num?)?.toDouble() ?? 0,
      'diferencia': (filaLocal['diferencia'] as num?)?.toDouble() ?? 0,
      'fechaCorte': fecha,
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

    final valoresLocales = <String, Object?>{
      'id_caja': idCajaLocal,
      'total_efectivo_sistema': (elementoBackend['totalEfectivoSistema'] as num?)?.toDouble() ?? 0,
      'total_tarjeta_sistema': (elementoBackend['totalTarjetaSistema'] as num?)?.toDouble() ?? 0,
      'total_transferencia_sistema': (elementoBackend['totalTransferenciaSistema'] as num?)?.toDouble() ?? 0,
      'total_efectivo_contado': (elementoBackend['totalEfectivoContado'] as num?)?.toDouble() ?? 0,
      'diferencia': (elementoBackend['diferencia'] as num?)?.toDouble() ?? 0,
      'fecha_corte': elementoBackend['fechaCorte'],
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
