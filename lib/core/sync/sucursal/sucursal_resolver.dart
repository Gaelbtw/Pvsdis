import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../auth_service.dart';
import '../models/sucursal_dto.dart';
import 'sucursales_client.dart';

/// Resuelve la sucursal de este dispositivo para el motor de sincronización.
///
/// `SesionSync.sucursalId` (lo que devuelve el login) puede venir `null` si
/// el usuario no tiene sucursal asignada del lado del backend
/// (`LoginResponseDto.SucursalId: Guid?`, sin fallback automático -- ver
/// `AuthService.GenerarRespuestaLoginAsync` en el backend). Cuando pasa
/// eso, se resuelve una vía `GET /api/sucursales` (la marcada
/// `esPrincipal`) y se cachea en `Sync_Config` para no repetir la llamada
/// de red en cada ciclo de sync.
class SucursalResolver {
  SucursalResolver({required AuthService authService, SucursalesClient? client})
      : _authService = authService,
        _client = client ?? SucursalesClient(authService: authService);

  final AuthService _authService;
  final SucursalesClient _client;

  /// Lectura pura local (sin red): la sesión de sync si ya trae una
  /// sucursal asignada, si no la caché de `Sync_Config`. `null` si
  /// ninguna de las dos la tiene todavía -- en ese caso hace falta
  /// [resolverYCachear].
  Future<String?> sucursalIdConocido(DatabaseExecutor db) async {
    final sucursalDeSesion = _authService.sesionActual?.sucursalId;
    if (sucursalDeSesion != null) return sucursalDeSesion;

    final filas = await db.query('Sync_Config', where: 'id = 1', limit: 1);
    if (filas.isEmpty) return null;
    return filas.first['sucursal_id'] as String?;
  }

  /// Como [sucursalIdConocido], pero si no hay ninguna resuelta todavía
  /// intenta resolver una contra el backend (`GET /api/sucursales`) y la
  /// cachea en `Sync_Config`. Elige la marcada `esPrincipal == true`; si
  /// ninguna lo está (no debería pasar -- invariante del onboarding del
  /// backend, que siempre crea la primera sucursal de un tenant con
  /// `EsPrincipal = true`) usa la primera de la lista y deja un aviso en
  /// consola, sin bloquear. `null` si el tenant no tiene ninguna sucursal
  /// (tenant recién creado sin onboarding completo) o si la llamada de red
  /// falla (sin conexión) -- en ambos casos, el llamador debe reintentar en
  /// un ciclo de sync posterior, no es un error fatal.
  Future<String?> resolverYCachear(DatabaseExecutor db) async {
    final conocida = await sucursalIdConocido(db);
    if (conocida != null) return conocida;

    final List<SucursalDto> sucursales;
    try {
      sucursales = await _client.obtenerTodas();
    } catch (_) {
      return null;
    }
    if (sucursales.isEmpty) return null;

    final elegida = sucursales.firstWhere(
      (s) => s.esPrincipal,
      orElse: () {
        debugPrint(
          'SucursalResolver: ninguna sucursal del tenant está marcada esPrincipal; '
          'se usa la primera de la lista (${sucursales.first.nombre}) como fallback.',
        );
        return sucursales.first;
      },
    );

    await db.insert(
      'Sync_Config',
      {
        'id': 1,
        'sucursal_id': elegida.id,
        'sucursal_nombre': elegida.nombre,
        'actualizado_en': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return elegida.id;
  }
}
