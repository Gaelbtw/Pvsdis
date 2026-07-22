import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';
import 'enums_backend.dart';

/// `Venta_Pagos` (local) <-> `VentaPago` (backend, `ClienteGana`).
class VentaPagoMapper extends EntityMapper {
  @override
  String get entidadBackend => 'VentaPago';

  @override
  String get tablaLocal => 'Venta_Pagos';

  @override
  String get columnaIdLocal => 'id';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Venta_Pagos sin guid_sync (id local: ${filaLocal['id']}).');
    }

    final idVenta = filaLocal['id_venta'] as int;
    final ventaGuid = await resolver.guidPorIdLocal('Ventas', idVenta);
    if (ventaGuid == null) {
      throw StateError('Venta_Pagos ${filaLocal['id']}: su Venta (id_venta=$idVenta) no tiene guid_sync.');
    }

    final ahora = DateTime.now().toUtc().toIso8601String();
    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      'ventaId': ventaGuid,
      'metodoPago': metodoPagoABackend(filaLocal['metodo_pago'] as String? ?? 'efectivo'),
      'monto': (filaLocal['monto'] as num?)?.toDouble() ?? 0,
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

    final valoresLocales = <String, Object?>{
      'id_venta': idVentaLocal,
      'metodo_pago': elementoBackend['metodoPago'],
      'monto': (elementoBackend['monto'] as num?)?.toDouble() ?? 0,
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
