import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';
import 'outbox/sync_outbox_deadletter.dart';
import 'sync_engine.dart';

/// Fase visible del motor para la UI (badge de estado, ver
/// `SyncEstadoBadge`). No distingue "offline" de "sin sesión" acá: ambos
/// dejan al motor `inactivo` con un [ResultadoSync] no-`completo` en
/// [EstadoSyncUI.ultimoResultado], y el badge decide cómo mostrarlo.
enum FaseSync { inactivo, sincronizando }

/// Snapshot inmutable del estado del sync para pintar la UI sin acoplarla al
/// [SyncScheduler]. Se expone vía un [ValueNotifier] para que un
/// `ValueListenableBuilder` se repinte solo cuando algo cambia, sin sumar un
/// paquete de manejo de estado (mismo criterio "sin dependencias extra" del
/// resto del módulo de sync).
@immutable
class EstadoSyncUI {
  const EstadoSyncUI({
    this.fase = FaseSync.inactivo,
    this.pendientes = 0,
    this.ultimoResultado,
    this.ultimaSincronizacion,
  });

  final FaseSync fase;

  /// Cambios locales aún sin subir (filas vivas en `Sync_Outbox`). `0` = todo
  /// al día.
  final int pendientes;

  /// Resultado del último ciclo, o `null` si todavía no corrió ninguno.
  final ResultadoSync? ultimoResultado;

  /// Momento del último ciclo *completo* (sin error). `null` si nunca hubo uno.
  final DateTime? ultimaSincronizacion;

  EstadoSyncUI copyWith({
    FaseSync? fase,
    int? pendientes,
    ResultadoSync? ultimoResultado,
    DateTime? ultimaSincronizacion,
  }) {
    return EstadoSyncUI(
      fase: fase ?? this.fase,
      pendientes: pendientes ?? this.pendientes,
      ultimoResultado: ultimoResultado ?? this.ultimoResultado,
      ultimaSincronizacion: ultimaSincronizacion ?? this.ultimaSincronizacion,
    );
  }
}

/// Orquesta *cuándo* corre el motor de sync ([SyncEngine] resuelve *qué* hace
/// cada ciclo). Decisión de producto: automático (al abrir la app + cada
/// [intervalo]) **más** manual (botón "Sincronizar ahora"). Ambos entran por
/// [sincronizarAhora], que tiene un guard de concurrencia: si ya hay un ciclo
/// en curso, la segunda llamada es un no-op -- así el tick del timer nunca se
/// solapa con un disparo manual (dos `push` simultáneos del mismo outbox
/// duplicarían el trabajo).
///
/// Singleton compartido (`instancia`), mismo criterio que
/// [AuthService.instancia]: este proyecto no usa inyección de dependencias, y
/// el badge de la UI y el arranque en `main()` deben ver el mismo estado.
class SyncScheduler {
  SyncScheduler({SyncEngine? engine, Duration intervalo = const Duration(minutes: 2)})
      : _engine = engine ?? SyncEngine(authService: AuthService.instancia),
        _intervalo = intervalo;

  static final SyncScheduler instancia = SyncScheduler();

  final SyncEngine _engine;
  final Duration _intervalo;

  Timer? _timer;
  bool _enProgreso = false;

  /// Estado observable para la UI. Nunca es `null`; arranca "inactivo, 0
  /// pendientes, sin resultado".
  final ValueNotifier<EstadoSyncUI> estado = ValueNotifier(const EstadoSyncUI());

  /// Arranca el ciclo automático: una corrida inmediata + un tick cada
  /// [intervalo]. Idempotente -- llamarlo dos veces no crea dos timers.
  void iniciar() {
    if (_timer != null) return;
    unawaited(sincronizarAhora());
    _timer = Timer.periodic(_intervalo, (_) => unawaited(sincronizarAhora()));
  }

  /// Detiene el ciclo automático (el estado observable se conserva). Un
  /// disparo manual con [sincronizarAhora] sigue funcionando después.
  void detener() {
    _timer?.cancel();
    _timer = null;
  }

  /// Corre un ciclo ahora. Devuelve el [ResultadoSync], o `null` si se saltó
  /// por haber ya uno en curso (guard de concurrencia). Nunca lanza: cualquier
  /// error del motor ya viene envuelto en `ResultadoSync(completo: false)`.
  Future<ResultadoSync?> sincronizarAhora() async {
    if (_enProgreso) return null;
    _enProgreso = true;
    estado.value = estado.value.copyWith(fase: FaseSync.sincronizando);

    ResultadoSync? resultado;
    try {
      resultado = await _engine.sincronizarUnaVez();
    } finally {
      _enProgreso = false;
      final pendientes = await _contarPendientes();
      final completo = resultado?.completo ?? false;
      estado.value = EstadoSyncUI(
        fase: FaseSync.inactivo,
        pendientes: pendientes,
        ultimoResultado: resultado,
        ultimaSincronizacion: completo ? DateTime.now() : estado.value.ultimaSincronizacion,
      );
    }
    return resultado;
  }

  /// Cuenta las filas de `Sync_Outbox` que todavía se intentarán subir. Excluye
  /// el sentinela de "fallida permanente" ([SyncOutboxDrainer], dead-letter):
  /// esas ya no cuentan como "pendientes de subir", se reportan aparte.
  Future<int> _contarPendientes() async {
    try {
      final db = await DatabaseHelper().database;
      final filas = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM Sync_Outbox WHERE intentos > ${SyncOutboxDeadLetter.intentosFallidaPermanente}",
      );
      return (filas.first['c'] as int?) ?? 0;
    } catch (_) {
      // Si la BD no está lista todavía, conserva el conteo previo en vez de
      // parpadear a 0.
      return estado.value.pendientes;
    }
  }
}
