import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// `Cajas` (local) <-> `CajaSesion` (backend, `ClienteGana`).
///
/// `Estado` coincide textualmente entre local y backend (`'Abierta'`/
/// `'Cerrada'` en ambos lados -- ver `EsqPos.Domain.Enums.
/// EstadoCajaSesion`), no hace falta tabla de conversión. `SucursalId`/
/// `UsuarioId` salen de `resolver.sucursalConfigurada()`/[usuarioIdSync],
/// no de columnas locales (mismo criterio que `VentaMapper`, ver esa
/// clase). `FechaCreacion`/`FechaModificacion` se aproximan con
/// `fecha_apertura`/`fecha_cierre ?? fecha_apertura` -- la sesión de caja es
/// casi-inmutable una vez cerrada, así que esto es estable entre
/// reintentos.
class CajaSesionMapper extends EntityMapper {
  @override
  String get entidadBackend => 'CajaSesion';

  @override
  String get tablaLocal => 'Cajas';

  @override
  String get columnaIdLocal => 'id_caja';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Cajas sin guid_sync (id local: ${filaLocal['id_caja']}).');
    }

    final sucursalId = await resolver.sucursalConfigurada();
    if (sucursalId == null) {
      throw StateError('No se puede sincronizar Cajas ${filaLocal['id_caja']}: sucursal del dispositivo sin resolver todavía.');
    }

    final fechaApertura = (filaLocal['fecha_apertura'] as String?) ?? DateTime.now().toUtc().toIso8601String();
    final fechaCierre = filaLocal['fecha_cierre'] as String?;

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': fechaApertura,
      'fechaModificacion': fechaCierre ?? fechaApertura,
      'isDeleted': false,
      'sucursalId': sucursalId,
      'usuarioId': usuarioIdSync,
      'fechaApertura': fechaApertura,
      'montoApertura': (filaLocal['fondo_inicial'] as num?)?.toDouble() ?? 0,
      'fechaCierre': fechaCierre,
      'montoCierreDeclarado': (filaLocal['efectivo_contado'] as num?)?.toDouble(),
      'montoCierreSistema': (filaLocal['efectivo_esperado'] as num?)?.toDouble(),
      'diferencia': (filaLocal['diferencia'] as num?)?.toDouble(),
      'estado': (filaLocal['estado'] as String?) ?? 'Abierta',
      'observaciones': filaLocal['observaciones_apertura'],
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final guid = elementoBackend['id'] as String;

    final valoresLocales = <String, Object?>{
      'fecha_apertura': elementoBackend['fechaApertura'],
      'fondo_inicial': (elementoBackend['montoApertura'] as num?)?.toDouble() ?? 0,
      'fecha_cierre': elementoBackend['fechaCierre'],
      'efectivo_contado': (elementoBackend['montoCierreDeclarado'] as num?)?.toDouble(),
      'efectivo_esperado': (elementoBackend['montoCierreSistema'] as num?)?.toDouble(),
      'diferencia': (elementoBackend['diferencia'] as num?)?.toDouble(),
      'estado': elementoBackend['estado'] ?? 'Abierta',
      'observaciones_apertura': elementoBackend['observaciones'],
    };

    final idLocalExistente = await resolver.idLocalPorGuid(tablaLocal, columnaIdLocal, guid);

    if (idLocalExistente == null) {
      // Gap de identidad real, no una simplificación cualquiera: `Cajas.
      // id_usuario` es NOT NULL con FK RESTRICT a `Usuarios` (el login
      // LOCAL de cajeros, bcrypt contra pos.db) -- un sistema de identidad
      // completamente distinto al usuario de sincronización (Guid,
      // AuthService). Una CajaSesion abierta en OTRO dispositivo no tiene
      // ningún cajero local equivalente al que asignarle esta fila: no hay
      // un valor correcto que poner en id_usuario. En vez de inventar un
      // sentinela que rompería la FK (o mentir con el usuario de sync
      // actual, que sería auditoría falsa), se ignora esta sesión --
      // solo se actualizan sesiones que este dispositivo ya conoce (abiertas
      // localmente y luego reflejadas de vuelta tras su propio push). Cerrar
      // esta brecha de verdad (¿columna nullable? ¿cajero "remoto"
      // placeholder?) queda para una fase posterior.
      return;
    }

    await db.update(tablaLocal, valoresLocales, where: '$columnaIdLocal = ?', whereArgs: [idLocalExistente]);
  }
}
