import 'package:sqflite/sqflite.dart';

import '../entities/entity_mapper.dart';
import '../entities/entity_mapper_registry.dart';
import '../sync_client.dart';
import 'sync_pull_cursor_store.dart';

/// Aplica el lado de pull del motor de sync: pide a [SyncClient] los
/// cambios de una entidad desde el último cursor conocido
/// ([SyncPullCursorStore]), paginando mientras el backend indique
/// `hayMas`, y aplica cada elemento a la tabla local vía
/// `EntityMapper.upsertLocal`.
class SyncPullRunner {
  SyncPullRunner({required SyncClient syncClient, SyncPullCursorStore? cursorStore})
      : _syncClient = syncClient,
        _cursorStore = cursorStore ?? SyncPullCursorStore();

  final SyncClient _syncClient;
  final SyncPullCursorStore _cursorStore;

  /// Pullea [entidad] completa (todas las páginas pendientes) y devuelve
  /// cuántos elementos se aplicaron. [resolver] se reutiliza a través de
  /// todas las entidades de un mismo ciclo (ver [pullEntidades]) para
  /// aprovechar su caché de `guid_sync -> id local` en vez de reconstruirla
  /// por entidad.
  Future<int> pullEntidad(DatabaseExecutor db, String entidad, {FkResolver? resolver}) async {
    final mapper = EntityMapperRegistry.paraEntidad(entidad);
    final resolverEfectivo = resolver ?? FkResolver(db);

    var desde = await _cursorStore.obtenerUltimaFecha(db, entidad);
    var aplicados = 0;

    while (true) {
      final respuesta = await _syncClient.pull(entidad, desde: desde);

      for (final elemento in respuesta.elementos) {
        await mapper.upsertLocal(db: db, elementoBackend: elemento, resolver: resolverEfectivo);
        aplicados++;
      }

      await _cursorStore.guardarUltimaFecha(db, entidad, respuesta.ultimaFechaModificacion);
      desde = respuesta.ultimaFechaModificacion;

      // hayMas solo es true si la página vino llena (ver PullGenericoAsync
      // en SyncService.cs: `HayMas: items.Count == limite`) -- una página
      // vacía nunca la deja en true, así que no hace falta un guard extra
      // contra un loop infinito por "hayMas siempre true sin avanzar".
      if (!respuesta.hayMas) break;
    }

    return aplicados;
  }

  /// Pullea [entidades] (por default, `EntityMapperRegistry.ordenPull`) en
  /// orden -- padre antes que hijo, para que cada FK se pueda resolver
  /// contra una fila que el pull ya insertó en esta misma pasada.
  Future<int> pullEntidades(DatabaseExecutor db, {List<String>? entidades}) async {
    final resolver = FkResolver(db);
    var total = 0;

    for (final entidad in entidades ?? EntityMapperRegistry.ordenPull) {
      total += await pullEntidad(db, entidad, resolver: resolver);
    }

    return total;
  }
}
