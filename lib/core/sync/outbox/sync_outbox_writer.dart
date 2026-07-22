import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../auth_service.dart';
import '../entities/entity_mapper.dart';
import '../entities/entity_mapper_registry.dart';

/// Punto único que reemplaza `DatabaseHelper.insertarConGuidSync` (y los
/// `UPDATE` manuales) en cada tabla que participa en la sincronización:
/// hace la escritura local Y encola el cambio en `Sync_Outbox`, en la MISMA
/// transacción -- si algo más adelante en esa transacción falla y hace
/// rollback, la fila del outbox se revierte junto con todo lo demás.
///
/// Solo sirve para entidades `ClienteGana`/`ServidorGana` con
/// [EntityMapper] registrado (ver [EntityMapperRegistry]) que además
/// soporten push (`Stock` es pull-only y su `aBackend` lanza
/// [UnsupportedError] a propósito -- `Inventario` sigue insertándose con
/// `DatabaseHelper.insertarConGuidSync` directo, sin pasar por acá).
///
/// Si no hay sesión de sincronización vigente (`AuthService.sesionActual ==
/// null`), la escritura local se completa igual y simplemente no se encola
/// nada -- principio ya establecido en la Fase 2 (un dispositivo puede
/// vender 100% offline sin haber iniciado sesión de sync nunca). Esa fila
/// queda sin sincronizar hasta que exista un barrido de "resync completo"
/// (fuera de alcance de esta fase, gap documentado).
class SyncOutboxWriter {
  SyncOutboxWriter({required AuthService authService}) : _authService = authService;

  final AuthService _authService;

  /// Inserta en [tabla] (vía `insertarConGuidSync`, así que la fila recibe
  /// `guid_sync` de inmediato) y encola el alta como `'CREAR'` en
  /// `Sync_Outbox`. Devuelve el id local nuevo, igual que
  /// `insertarConGuidSync`.
  Future<int> crear(
    DatabaseExecutor txn, {
    required String entidad,
    required String tabla,
    required Map<String, Object?> values,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final idNuevo = await DatabaseHelper.insertarConGuidSync(txn, tabla, values, conflictAlgorithm: conflictAlgorithm);
    await _encolarSiHaySesion(txn, entidad: entidad, tabla: tabla, idLocal: idNuevo, operacion: 'CREAR');
    return idNuevo;
  }

  /// Encola un `'ACTUALIZAR'` para una fila que YA se actualizó en [tabla]
  /// (el `UPDATE` en sí lo hace el llamador, antes de invocar esto -- este
  /// método solo lee el estado ya escrito y arma el payload a partir de
  /// él). [idLocal] es el id de la fila en su columna de llave primaria
  /// (ver `DatabaseHelper.tablasSincronizables`).
  Future<void> actualizar(
    DatabaseExecutor txn, {
    required String entidad,
    required String tabla,
    required int idLocal,
  }) {
    return _encolarSiHaySesion(txn, entidad: entidad, tabla: tabla, idLocal: idLocal, operacion: 'ACTUALIZAR');
  }

  Future<void> _encolarSiHaySesion(
    DatabaseExecutor txn, {
    required String entidad,
    required String tabla,
    required int idLocal,
    required String operacion,
  }) async {
    final sesion = _authService.sesionActual;
    if (sesion == null || sesion.tenantId == null) return;

    final columnaId = DatabaseHelper.tablasSincronizables[tabla];
    if (columnaId == null) {
      throw ArgumentError('$tabla no está registrada en DatabaseHelper.tablasSincronizables.');
    }

    final filas = await txn.query(tabla, where: '$columnaId = ?', whereArgs: [idLocal], limit: 1);
    if (filas.isEmpty) return; // la fila ya no existe (borrada más adelante en la misma transacción)

    final fila = filas.first;
    final guid = fila['guid_sync'] as String?;
    if (guid == null) return; // no debería pasar tras insertarConGuidSync, pero no hay identidad con la que encolar

    final mapper = EntityMapperRegistry.paraEntidad(entidad);
    final resolver = FkResolver(txn);
    final ahora = DateTime.now().toUtc().toIso8601String();

    try {
      final payload = await mapper.aBackend(
        filaLocal: fila,
        tenantId: sesion.tenantId!,
        usuarioIdSync: sesion.usuarioId,
        resolver: resolver,
      );

      await txn.insert('Sync_Outbox', {
        'entidad': entidad,
        'guid_registro': guid,
        'operacion': operacion,
        'datos_json': jsonEncode(payload),
        'fecha_creacion': ahora,
        'intentos': 0,
      });
    } on StateError catch (e) {
      // El payload no se pudo armar todavía -- típicamente la sucursal del
      // dispositivo aún sin resolver (`SucursalResolver`, Fase 3d) o una FK
      // que apunta a una fila que todavía no tiene `guid_sync`. Se encola
      // igual con `datos_json` vacío e `intentos = -1` (sentinela "esperando
      // prerrequisito"): el drainer (`SyncEngine`, Fase 3g) la salta sin
      // gastar reintentos reales hasta reconstruir el payload más adelante
      // (re-consultando esta misma fila por `guid_registro`), en vez de
      // perder la operación silenciosamente.
      await txn.insert('Sync_Outbox', {
        'entidad': entidad,
        'guid_registro': guid,
        'operacion': operacion,
        'datos_json': '{}',
        'fecha_creacion': ahora,
        'intentos': -1,
        'ultimo_error': e.message.toString(),
      });
    }
  }
}
