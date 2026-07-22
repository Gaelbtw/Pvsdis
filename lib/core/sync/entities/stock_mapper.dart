import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// `Inventario` (local) <-> `Stock` (backend, `ServidorGana`), **pull-only**:
/// el Flutter nunca sube su inventario, solo lo recibe -- el stock se ajusta
/// localmente con `ProductoController`/`VentasController`/etc. y esos
/// ajustes viajan como `MovimientoInventario` (ver
/// `movimiento_inventario_mapper.dart`), no como `Stock` directo.
///
/// El backend es multi-sucursal (`Stock.SucursalId`); el Flutter es
/// single-location. Se filtra contra `Sync_Config.sucursal_id` (la sucursal
/// resuelta para este dispositivo, ver `lib/core/sync/sucursal/` en la
/// sub-fase 3d) directo por consulta SQL, sin depender de `SucursalResolver`
/// como dependencia de constructor -- evita un acoplamiento innecesario y
/// mantiene este mapper instanciable sin más contexto que una conexión a la
/// base. Si todavía no hay sucursal resuelta para este dispositivo, se
/// ignora el elemento (se aplicará en un pull posterior, una vez resuelta).
///
/// No hace falta reconciliar `Stock.Id` con el `guid_sync` que ya tiene la
/// fila `Inventario` local (asignado al crear el producto, antes de que
/// exista sincronización real): como este mapper nunca hace push, esa
/// columna simplemente no participa en esta traducción.
class StockMapper extends EntityMapper {
  @override
  String get entidadBackend => 'Stock';

  @override
  String get tablaLocal => 'Inventario';

  @override
  String get columnaIdLocal => 'id_inventario';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) {
    throw UnsupportedError(
      'Stock es pull-only: el Flutter nunca sube su inventario directo, solo vía MovimientoInventario.',
    );
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final sucursalLocal = await resolver.sucursalConfigurada();
    if (sucursalLocal == null || elementoBackend['sucursalId'] != sucursalLocal) {
      return;
    }

    final productoGuid = elementoBackend['productoId'] as String;
    final idProductoLocal = await resolver.idLocalPorGuid('Producto', 'id_producto', productoGuid);
    if (idProductoLocal == null) {
      // El producto todavía no llegó por su propio pull (CategoriaProducto
      // -> Producto -> Stock, ver EntityMapperRegistry.ordenPull) -- se
      // reintentará en el próximo ciclo de sync, no es un error.
      return;
    }

    final cantidad = elementoBackend['cantidadDisponible'] as int;
    final filasInventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProductoLocal]);

    if (filasInventario.isEmpty) {
      await db.insert('Inventario', {'id_producto': idProductoLocal, 'cantidad': cantidad});
    } else {
      await db.update('Inventario', {'cantidad': cantidad}, where: 'id_producto = ?', whereArgs: [idProductoLocal]);
    }
  }
}
