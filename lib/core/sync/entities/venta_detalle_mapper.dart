import 'package:sqflite/sqflite.dart';

import '../../config/app_config.dart';
import 'entity_mapper.dart';

/// `Detalle_Venta` (local) <-> `VentaDetalle` (backend, `ClienteGana`).
///
/// `CantidadDevuelta` siempre sale en `0`: el local no propaga devoluciones
/// parciales sobre una línea ya sincronizada (`Devoluciones`/
/// `Detalle_Devolucion` no son entidades sincronizables hoy, ver el README
/// de esta fase). `SubtotalSinIva`/`MontoIva` se derivan de `precio_neto`
/// con la misma tasa global de IVA que usa `ProductoMapper` (misma
/// simplificación ya acordada: no hay IVA por producto en el modelo local).
class VentaDetalleMapper extends EntityMapper {
  @override
  String get entidadBackend => 'VentaDetalle';

  @override
  String get tablaLocal => 'Detalle_Venta';

  @override
  String get columnaIdLocal => 'id_detalleV';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Detalle_Venta sin guid_sync (id local: ${filaLocal['id_detalleV']}).');
    }

    final idVenta = filaLocal['id_venta'] as int;
    final ventaGuid = await resolver.guidPorIdLocal('Ventas', idVenta);
    if (ventaGuid == null) {
      throw StateError('Detalle_Venta ${filaLocal['id_detalleV']}: su Venta (id_venta=$idVenta) no tiene guid_sync.');
    }

    final idProducto = filaLocal['id_producto'] as int;
    final productoGuid = await resolver.guidPorIdLocal('Producto', idProducto);
    if (productoGuid == null) {
      throw StateError('Detalle_Venta ${filaLocal['id_detalleV']}: su Producto (id_producto=$idProducto) no tiene guid_sync.');
    }

    final subtotal = (filaLocal['precio_neto'] as num?)?.toDouble() ??
        ((filaLocal['cantidad'] as num).toDouble() * (filaLocal['precio'] as num).toDouble() -
            ((filaLocal['descuento_monto'] as num?)?.toDouble() ?? 0));

    final tasaDecimal = AppConfig.actual.tasaImpuestoPorcentaje / 100;
    final aplicaIva = tasaDecimal > 0;
    final subtotalSinIva = aplicaIva ? subtotal / (1 + tasaDecimal) : subtotal;
    final montoIva = subtotal - subtotalSinIva;

    final ahora = DateTime.now().toUtc().toIso8601String();
    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      'ventaId': ventaGuid,
      'productoId': productoGuid,
      'cantidad': filaLocal['cantidad'],
      'cantidadDevuelta': 0,
      'precioUnitario': (filaLocal['precio'] as num).toDouble(),
      'descuento': (filaLocal['descuento_monto'] as num?)?.toDouble() ?? 0,
      'subtotalSinIva': subtotalSinIva,
      'montoIva': montoIva,
      'subtotal': subtotal,
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
    if (idVentaLocal == null) return; // la Venta llegará en su propio pull; se reintenta después.

    final productoGuid = elementoBackend['productoId'] as String;
    final idProductoLocal = await resolver.idLocalPorGuid('Producto', 'id_producto', productoGuid);
    if (idProductoLocal == null) return;

    final valoresLocales = <String, Object?>{
      'id_venta': idVentaLocal,
      'id_producto': idProductoLocal,
      'cantidad': elementoBackend['cantidad'],
      'precio': (elementoBackend['precioUnitario'] as num?)?.toDouble() ?? 0,
      'descuento_monto': (elementoBackend['descuento'] as num?)?.toDouble() ?? 0,
      'precio_neto': (elementoBackend['subtotal'] as num?)?.toDouble() ?? 0,
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
