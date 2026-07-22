import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';
import 'enums_backend.dart';

/// `Venta_Promociones` (local) <-> `VentaPromocion` (backend, `ClienteGana`).
/// Solo el snapshot padre -- **no** `Venta_Promociones_Detalle`, por el
/// mismo motivo que `PromocionMapper` no sincroniza sus tablas puente (ver
/// esa clase): el backend limpia navegaciones anidadas en el push
/// (`LimpiarNavegaciones`), así que `VentaPromocionDetalle` necesitaría
/// sincronizarse como entidad propia con su propio `Id` estable, y
/// `Venta_Promociones_Detalle` local no tiene `guid_sync` (excluida a
/// propósito en la Fase 2, mismo criterio que las tablas puente de
/// Promocion).
class VentaPromocionMapper extends EntityMapper {
  @override
  String get entidadBackend => 'VentaPromocion';

  @override
  String get tablaLocal => 'Venta_Promociones';

  @override
  String get columnaIdLocal => 'id_venta_promocion';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError(
        'No se puede sincronizar Venta_Promociones sin guid_sync (id local: ${filaLocal['id_venta_promocion']}).',
      );
    }

    final idVenta = filaLocal['id_venta'] as int;
    final ventaGuid = await resolver.guidPorIdLocal('Ventas', idVenta);
    if (ventaGuid == null) {
      throw StateError('Venta_Promociones ${filaLocal['id_venta_promocion']}: su Venta (id_venta=$idVenta) no tiene guid_sync.');
    }

    final idPromocion = filaLocal['id_promocion'] as int?;
    final promocionGuid = idPromocion == null ? null : await resolver.guidPorIdLocal('Promociones', idPromocion);

    final tipoLocal = filaLocal['tipo_snapshot'] as String;
    final tipoBackend = tipoPromocionLocalABackend[tipoLocal] ?? 'PorcentajeProducto';

    final ahora = DateTime.now().toUtc().toIso8601String();
    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      'ventaId': ventaGuid,
      'promocionId': promocionGuid,
      'nombrePromocion': filaLocal['nombre_snapshot'],
      'tipo': tipoBackend,
      'ahorro': (filaLocal['ahorro_total'] as num?)?.toDouble() ?? 0,
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final guid = elementoBackend['id'] as String;

    final ventaGuid = elementoBackend['ventaId'] as String;
    final idVentaLocal = await resolver.idLocalPorGuid('Ventas', 'id_venta', ventaGuid);
    if (idVentaLocal == null) return;

    final promocionGuid = elementoBackend['promocionId'] as String?;
    final idPromocionLocal =
        promocionGuid == null ? null : await resolver.idLocalPorGuid('Promociones', 'id_promocion', promocionGuid);

    final tipoBackend = elementoBackend['tipo'] as String? ?? 'PorcentajeProducto';

    final valoresLocales = <String, Object?>{
      'id_venta': idVentaLocal,
      'id_promocion': idPromocionLocal,
      'nombre_snapshot': elementoBackend['nombrePromocion'],
      'tipo_snapshot': tipoPromocionBackendALocal[tipoBackend] ?? 'PORCENTAJE_PRODUCTO',
      'ahorro_total': (elementoBackend['ahorro'] as num?)?.toDouble() ?? 0,
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
