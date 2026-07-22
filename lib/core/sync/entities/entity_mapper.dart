import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Traduce identidad entre el mundo local (`int` autoincremental por tabla)
/// y el mundo del backend (`Guid` compartido vía la columna `guid_sync`).
///
/// Es la pieza que hace posible que un `Producto.id_categoria` (int local)
/// se convierta en `CategoriaId` (Guid) al subir, y que un `CategoriaId`
/// recibido en un pull se convierta de vuelta en el `id_categoria` local
/// correcto -- sin esto, cada [EntityMapper] tendría que reimplementar la
/// misma búsqueda `WHERE guid_sync = ?`.
///
/// Cachea en memoria por instancia (pensado para vivir el tiempo de un solo
/// ciclo de sincronización, no como singleton de larga vida: si una fila
/// cambia de guid_sync a mitad de un ciclo -- no debería pasar nunca, pero
/// si pasara -- una instancia vieja quedaría con una lectura obsoleta).
class FkResolver {
  FkResolver(this._db);

  final DatabaseExecutor _db;

  final Map<String, Map<String, int>> _guidAIdLocal = {};
  final Map<String, Map<int, String>> _idLocalAGuid = {};

  /// Id local (`int`) de la fila de [tablaLocal] cuyo `guid_sync` es [guid],
  /// o `null` si esa fila no existe todavía localmente. [columnaId] es la
  /// columna de llave primaria de [tablaLocal] (ver
  /// `DatabaseHelper.tablasSincronizables`).
  Future<int?> idLocalPorGuid(String tablaLocal, String columnaId, String guid) async {
    final cache = _guidAIdLocal.putIfAbsent(tablaLocal, () => {});
    if (cache.containsKey(guid)) return cache[guid];

    final filas = await _db.query(
      tablaLocal,
      columns: [columnaId],
      where: 'guid_sync = ?',
      whereArgs: [guid],
      limit: 1,
    );
    if (filas.isEmpty) return null;

    final idLocal = filas.first[columnaId] as int;
    registrar(tablaLocal, guid, idLocal);
    return idLocal;
  }

  /// `guid_sync` de la fila [idLocal] de [tablaLocal], o `null` si esa fila
  /// no existe o todavía no tiene `guid_sync` asignado (no debería pasar
  /// para una fila que se está empujando al backend: `insertarConGuidSync`
  /// se lo asigna de una vez al crearla).
  Future<String?> guidPorIdLocal(String tablaLocal, int idLocal) async {
    final cache = _idLocalAGuid.putIfAbsent(tablaLocal, () => {});
    if (cache.containsKey(idLocal)) return cache[idLocal];

    final columnaId = DatabaseHelper.tablasSincronizables[tablaLocal];
    if (columnaId == null) {
      throw ArgumentError('$tablaLocal no está registrada en DatabaseHelper.tablasSincronizables');
    }

    final filas = await _db.query(
      tablaLocal,
      columns: ['guid_sync'],
      where: '$columnaId = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    if (filas.isEmpty) return null;

    final guid = filas.first['guid_sync'] as String?;
    if (guid != null) registrar(tablaLocal, guid, idLocal);
    return guid;
  }

  /// Primea la caché con un par ya conocido (ej. justo después de insertar
  /// una fila nueva en `upsertLocal`), para que una referencia posterior
  /// dentro del mismo ciclo de sync no dispare una consulta redundante.
  void registrar(String tablaLocal, String guid, int idLocal) {
    _guidAIdLocal.putIfAbsent(tablaLocal, () => {})[guid] = idLocal;
    _idLocalAGuid.putIfAbsent(tablaLocal, () => {})[idLocal] = guid;
  }

  /// `sucursal_id` (Guid del backend) resuelto para este dispositivo, o
  /// `null` si todavía no se ha resuelto (ver `Sync_Config` en
  /// `database_helper.dart` y `SucursalResolver`, sub-fase 3d). Mappers que
  /// necesiten `SucursalId` en su payload de push (Venta, CajaSesion,
  /// Movimiento*) lo leen de acá en vez de recibir `db` directo -- mantiene
  /// [FkResolver] como el único objeto de "contexto ambiente" que un
  /// [EntityMapper] necesita, sin agregar un parámetro más a `aBackend`.
  Future<String?> sucursalConfigurada() async {
    final filas = await _db.query('Sync_Config', where: 'id = 1', limit: 1);
    if (filas.isEmpty) return null;
    return filas.first['sucursal_id'] as String?;
  }
}

/// Contrato que traduce una entidad sincronizable en ambas direcciones:
///
/// - [aBackend]: fila local (`Map` con columnas snake_case, tal como vuelve
///   de `db.query`) -> payload JSON que espera `POST /api/sync/push`
///   (camelCase -- ver la nota de casing más abajo).
/// - [upsertLocal]: elemento de un pull (`Map` camelCase, tal como lo
///   parsea `SyncPullResponse.elementos`) -> INSERT o UPDATE sobre la tabla
///   local correspondiente.
///
/// **Casing verificado, no asumido**: el backend expone sus controladores
/// vía `AddControllers().AddJsonOptions(...)` sin `PropertyNamingPolicy`
/// explícito (`EsqueletoPOS/src/EsqPos.API/Program.cs:19-20`), que es el
/// default de ASP.NET Core MVC -- **camelCase**, no PascalCase. El lado de
/// push del backend además deserializa con `PropertyNameCaseInsensitive =
/// true` (`SyncService.cs:59-63`), así que un payload en camelCase nunca
/// tiene mismatch de campo. Todo [EntityMapper] de esta app produce/consume
/// camelCase.
abstract class EntityMapper {
  /// Nombre exacto tal como aparece en `SyncEntidadRegistry` del backend
  /// (ej. `'CategoriaProducto'`, no `'Categoria'` -- los nombres del
  /// backend no siempre coinciden con los de la tabla local).
  String get entidadBackend;

  /// Tabla local que espeja esta entidad (ver
  /// `DatabaseHelper.tablasSincronizables`).
  String get tablaLocal;

  /// Columna de llave primaria local de [tablaLocal].
  String get columnaIdLocal;

  /// Arma el payload de push a partir de una fila local. [filaLocal] debe
  /// tener `guid_sync` ya asignado (lo asigna `insertarConGuidSync` al
  /// crear la fila) -- llamarlo sobre una fila sin `guid_sync` es un error
  /// del llamador, no un caso que este método deba tolerar en silencio.
  ///
  /// [usuarioIdSync] es el `usuarioId` (Guid) de la sesión de
  /// sincronización vigente (`AuthService.sesionActual!.usuarioId`) -- NUNCA
  /// el `id_usuario` local del cajero (sistema de login completamente
  /// distinto, bcrypt contra `pos.db`, sin `guid_sync`). Solo lo usan los
  /// mappers de entidades que llevan un campo `UsuarioId` propio (Venta,
  /// CajaSesion, Movimiento*, CorteCaja); los catálogos lo ignoran.
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  });

  /// Aplica un elemento recibido en un pull (`elementoBackend`, camelCase)
  /// a la tabla local: INSERT si el `id` (Guid) todavía no existe
  /// localmente (buscado vía `guid_sync`), UPDATE si ya existe.
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  });
}
