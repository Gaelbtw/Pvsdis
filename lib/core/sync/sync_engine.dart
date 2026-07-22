import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';
import 'entities/entity_mapper.dart';
import 'entities/entity_mapper_registry.dart';
import 'network/conectividad_probe.dart';
import 'outbox/sync_outbox_drainer.dart';
import 'pull/sync_pull_runner.dart';
import 'sucursal/sucursal_resolver.dart';
import 'sync_client.dart';

/// Resultado de un ciclo de [SyncEngine.sincronizarUnaVez]. [completo] es
/// `false` si el ciclo se interrumpió por una excepción (red que se cae a
/// mitad de camino, sesión que expira, etc.) -- [error] trae el detalle.
/// Ninguno de los contadores usa `null` para "no aplica": si el ciclo no
/// llegó a cierta etapa, ese contador simplemente queda en `0`.
class ResultadoSync {
  const ResultadoSync({
    required this.completo,
    this.elementosPulleados = 0,
    this.itemsSubidos = 0,
    this.itemsOmitidosPorServidor = 0,
    this.itemsFallidos = 0,
    this.error,
  });

  final bool completo;
  final int elementosPulleados;
  final int itemsSubidos;
  final int itemsOmitidosPorServidor;
  final int itemsFallidos;
  final String? error;

  static const sinConexion = ResultadoSync(completo: false, error: 'Sin conexión al backend.');
  static const sinSesion = ResultadoSync(completo: false, error: 'Sin sesión de sincronización activa.');
}

/// Orquestador de alto nivel del motor de sincronización: un ciclo completo
/// de `sincronizarUnaVez()` hace, en orden, (1) resolver la sucursal del
/// dispositivo si hace falta, (2) pull de todas las entidades registradas,
/// (3) drenar `Sync_Outbox` hacia el backend, (4) un pull extra de
/// cualquier entidad que el drenado haya marcado `OmitidoServidorGana`.
///
/// Fuera de alcance de esta fase: desde dónde/cuándo se dispara este ciclo
/// en la UI (temporizador, botón manual, o al abrir la app) -- ver el
/// roadmap general del proyecto, ítem 5.
class SyncEngine {
  SyncEngine._({
    required AuthService authService,
    required SyncClient syncClient,
    required ConectividadProbe conectividadProbe,
    required SucursalResolver sucursalResolver,
    required SyncPullRunner pullRunner,
    required SyncOutboxDrainer drainer,
  })  : _authService = authService,
        _conectividadProbe = conectividadProbe,
        _sucursalResolver = sucursalResolver,
        _pullRunner = pullRunner,
        _drainer = drainer;

  factory SyncEngine({
    required AuthService authService,
    SyncClient? syncClient,
    ConectividadProbe? conectividadProbe,
    SucursalResolver? sucursalResolver,
    SyncPullRunner? pullRunner,
    SyncOutboxDrainer? drainer,
  }) {
    final cliente = syncClient ?? SyncClient(authService: authService);
    return SyncEngine._(
      authService: authService,
      syncClient: cliente,
      conectividadProbe: conectividadProbe ?? ConectividadProbe(),
      sucursalResolver: sucursalResolver ?? SucursalResolver(authService: authService),
      pullRunner: pullRunner ?? SyncPullRunner(syncClient: cliente),
      drainer: drainer ?? SyncOutboxDrainer(syncClient: cliente),
    );
  }

  final AuthService _authService;
  final ConectividadProbe _conectividadProbe;
  final SucursalResolver _sucursalResolver;
  final SyncPullRunner _pullRunner;
  final SyncOutboxDrainer _drainer;

  Future<ResultadoSync> sincronizarUnaVez() async {
    if (!await _conectividadProbe.hayConexion()) return ResultadoSync.sinConexion;
    if (_authService.sesionActual == null) return ResultadoSync.sinSesion;

    try {
      final db = await DatabaseHelper().database;

      final sucursalId = await _sucursalResolver.resolverYCachear(db);
      if (sucursalId != null) {
        await _reescribirOutboxEsperandoPrerrequisito(db);
      }

      final elementosPulleados = await _pullRunner.pullEntidades(db);

      final resultadoDrenado = await _drainer.drenar(db);

      for (final entidad in resultadoDrenado.entidadesAPullearDeNuevo) {
        await _pullRunner.pullEntidad(db, entidad);
      }

      return ResultadoSync(
        completo: true,
        elementosPulleados: elementosPulleados,
        itemsSubidos: resultadoDrenado.subidos,
        itemsOmitidosPorServidor: resultadoDrenado.omitidosPorServidor,
        itemsFallidos: resultadoDrenado.fallidos,
      );
    } catch (e) {
      return ResultadoSync(completo: false, error: e.toString());
    }
  }

  /// Reintenta armar el payload de cada fila de `Sync_Outbox` marcada
  /// `intentos = -1` (el sentinela "esperando prerrequisito" que deja
  /// `SyncOutboxWriter` cuando `EntityMapper.aBackend` no pudo resolver
  /// algo -- típicamente la sucursal del dispositivo). Se llama justo
  /// después de que [SucursalResolver] ya resolvió una, así que el
  /// prerrequisito más común ya debería estar disponible; si el payload
  /// sigue sin poder armarse (otra FK sin resolver, por ejemplo) la fila
  /// queda igual, para reintentarse en un ciclo posterior.
  Future<void> _reescribirOutboxEsperandoPrerrequisito(DatabaseExecutor db) async {
    final sesion = _authService.sesionActual;
    if (sesion == null || sesion.tenantId == null) return;

    final pendientes = await db.query('Sync_Outbox', where: 'intentos = -1');
    if (pendientes.isEmpty) return;

    final resolver = FkResolver(db);

    for (final fila in pendientes) {
      final entidad = fila['entidad'] as String;
      final guid = fila['guid_registro'] as String;
      final mapper = EntityMapperRegistry.paraEntidad(entidad);

      final filasLocales = await db.query(mapper.tablaLocal, where: 'guid_sync = ?', whereArgs: [guid], limit: 1);
      if (filasLocales.isEmpty) {
        // La fila local ya no existe (se borró después de encolarse): no
        // hay nada que reconstruir, se descarta el pendiente.
        await db.delete('Sync_Outbox', where: 'id = ?', whereArgs: [fila['id']]);
        continue;
      }

      try {
        final payload = await mapper.aBackend(
          filaLocal: filasLocales.first,
          tenantId: sesion.tenantId!,
          usuarioIdSync: sesion.usuarioId,
          resolver: resolver,
        );

        await db.update(
          'Sync_Outbox',
          {'datos_json': jsonEncode(payload), 'intentos': 0, 'ultimo_error': null},
          where: 'id = ?',
          whereArgs: [fila['id']],
        );
      } on StateError catch (e) {
        await db.update(
          'Sync_Outbox',
          {'ultimo_error': e.message.toString()},
          where: 'id = ?',
          whereArgs: [fila['id']],
        );
      }
    }
  }
}
