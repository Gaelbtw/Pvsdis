import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// `Movimiento_Inventario` (local, bitácora nueva de la Fase 3) <->
/// `MovimientoInventario` (backend, `ClienteGana`).
///
/// `tipo_movimiento` local ya se declaró en la migración v19 con los mismos
/// nombres exactos que el enum backend (`'EntradaCompra'`, `'SalidaVenta'`,
/// etc. -- ver `EsqPos.Domain.Enums.TipoMovimientoInventario`), sin tabla de
/// conversión. `referencia_id` local es un `int` que apunta a una tabla
/// DISTINTA según `referencia_tipo` (`'Venta'`, `'Compra'`, `'Pedido'`,
/// `'Devolucion'`, ver los loggers de `lib/core/sync/bitacoras/` en 3e); de
/// esas, solo `Venta` es sincronizable -- para cualquier otro
/// `referencia_tipo` no hay un Guid backend al que traducir `referencia_id`,
/// así que `ReferenciaId` sale `null` y el detalle en texto libre queda solo
/// en `motivo`. `SucursalId` sale de `resolver.sucursalConfigurada()`, igual
/// que en `VentaMapper`/`CajaSesionMapper`.
class MovimientoInventarioMapper extends EntityMapper {
  @override
  String get entidadBackend => 'MovimientoInventario';

  @override
  String get tablaLocal => 'Movimiento_Inventario';

  @override
  String get columnaIdLocal => 'id_movimiento';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Movimiento_Inventario sin guid_sync (id local: ${filaLocal['id_movimiento']}).');
    }

    final sucursalId = await resolver.sucursalConfigurada();
    if (sucursalId == null) {
      throw StateError(
        'No se puede sincronizar Movimiento_Inventario ${filaLocal['id_movimiento']}: sucursal del dispositivo sin resolver todavía.',
      );
    }

    final idProducto = filaLocal['id_producto'] as int;
    final productoGuid = await resolver.guidPorIdLocal('Producto', idProducto);
    if (productoGuid == null) {
      throw StateError(
        'Movimiento_Inventario ${filaLocal['id_movimiento']}: su Producto (id_producto=$idProducto) no tiene guid_sync.',
      );
    }

    final referenciaTipo = filaLocal['referencia_tipo'] as String?;
    final referenciaIdLocal = filaLocal['referencia_id'] as int?;
    final referenciaGuid = (referenciaTipo == 'Venta' && referenciaIdLocal != null)
        ? await resolver.guidPorIdLocal('Ventas', referenciaIdLocal)
        : null;

    final fecha = (filaLocal['fecha'] as String?) ?? DateTime.now().toUtc().toIso8601String();

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': fecha,
      'fechaModificacion': fecha,
      'isDeleted': false,
      'productoId': productoGuid,
      'sucursalId': sucursalId,
      'tipoMovimiento': filaLocal['tipo_movimiento'],
      'cantidad': filaLocal['cantidad'],
      'cantidadAnterior': filaLocal['cantidad_anterior'],
      'cantidadNueva': filaLocal['cantidad_nueva'],
      'motivo': filaLocal['motivo'],
      'referenciaTipo': referenciaTipo,
      'referenciaId': referenciaGuid,
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

    final productoGuid = elementoBackend['productoId'] as String;
    final idProductoLocal = await resolver.idLocalPorGuid('Producto', 'id_producto', productoGuid);
    if (idProductoLocal == null) return;

    final valoresLocales = <String, Object?>{
      'id_producto': idProductoLocal,
      'tipo_movimiento': elementoBackend['tipoMovimiento'],
      'cantidad': elementoBackend['cantidad'],
      'cantidad_anterior': elementoBackend['cantidadAnterior'],
      'cantidad_nueva': elementoBackend['cantidadNueva'],
      'motivo': elementoBackend['motivo'],
      'referencia_tipo': elementoBackend['referenciaTipo'],
      // No se traduce referenciaId de vuelta a un id local: del lado del
      // pull, este dato es informativo (no hay UI que navegue de un
      // Movimiento_Inventario pulleado a su Venta de origen); se deja fuera
      // para no acoplar este mapper a resolver todas las posibles tablas de
      // referencia.
      'fecha': elementoBackend['fecha'],
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
