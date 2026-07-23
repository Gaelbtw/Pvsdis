import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/sync_dtos.dart';
import '../network/api_exceptions.dart';
import '../sync_client.dart';
import 'sync_outbox_deadletter.dart';

/// Contadores de un ciclo de [SyncOutboxDrainer.drenar], útiles para un
/// futuro badge de UI (fuera de alcance de esta fase construirlo).
class ResultadoDrenado {
  const ResultadoDrenado({
    required this.subidos,
    required this.omitidosPorServidor,
    required this.fallidos,
    required this.entidadesAPullearDeNuevo,
  });

  final int subidos;
  final int omitidosPorServidor;
  final int fallidos;

  /// Entidades `ServidorGana` donde el push chocó con una fila que ya
  /// existía server-side (`"OmitidoServidorGana"`): el servidor tiene una
  /// versión más nueva que la local, así que [SyncEngine] debe hacer un
  /// pull extra de estas antes de terminar el ciclo.
  final Set<String> entidadesAPullearDeNuevo;
}

/// Drena `Sync_Outbox` hacia `POST /api/sync/push`, en lotes.
///
/// Hallazgo del backend que condiciona todo este diseño (ver
/// `AplicarCambioAsync` en `EsqueletoPOS/src/EsqPos.Infrastructure/
/// Persistence/SyncService.cs:115-143`): cada ítem del lote hace su propio
/// `SaveChangesAsync` individual, sin transacción de lote ni try/catch en
/// el `foreach` de `PushAsync`. Si un ítem falla a mitad de un lote, los
/// anteriores YA quedaron persistidos en el servidor, pero el cliente
/// recibe un error HTTP sin `resultados` -- no hay forma de saber cuáles se
/// aplicaron. Por eso: lotes chicos ([tamanoLote], default 25), y si el
/// POST completo falla, se incrementan los `intentos` de todo el lote y se
/// sigue con el siguiente lote (no se aborta el drenado completo por un
/// lote fallido -- los demás lotes son independientes). El reintento es
/// seguro porque el push es idempotente por `Id`: reinsertar una fila
/// `ServidorGana` que ya se aplicó vuelve `"OmitidoServidorGana"` sin
/// duplicar, y sobrescribir una `ClienteGana` con los mismos datos no
/// cambia nada.
class SyncOutboxDrainer {
  SyncOutboxDrainer({required SyncClient syncClient, this.tamanoLote = 25}) : _syncClient = syncClient;

  final SyncClient _syncClient;
  final int tamanoLote;

  Future<ResultadoDrenado> drenar(DatabaseExecutor db) async {
    var subidos = 0;
    var omitidosPorServidor = 0;
    var fallidos = 0;
    final entidadesAPullearDeNuevo = <String>{};

    // `id > idMinimo` (no un simple LIMIT sin cursor) es lo que evita un
    // loop infinito dentro de esta misma llamada: si un lote falla, sus
    // filas siguen con `intentos >= 0` (solo incrementado), así que sin
    // este cursor la siguiente vuelta del `while` volvería a seleccionar
    // EXACTAMENTE el mismo lote para siempre. `intentos = -1` (sentinela
    // "esperando prerrequisito", ver `SyncOutboxWriter`) queda excluido del
    // drenado -- `SyncEngine` las reintenta aparte, no acá.
    var idMinimo = 0;

    while (true) {
      final filas = await db.query(
        'Sync_Outbox',
        where: 'intentos >= 0 AND id > ?',
        whereArgs: [idMinimo],
        orderBy: 'id ASC',
        limit: tamanoLote,
      );
      if (filas.isEmpty) break;

      idMinimo = filas.last['id'] as int;

      final cambios = filas
          .map((fila) => SyncPushItem(
                entidad: fila['entidad'] as String,
                datos: jsonDecode(fila['datos_json'] as String) as Map<String, dynamic>,
              ))
          .toList();

      SyncPushResponse respuesta;
      try {
        respuesta = await _syncClient.push(SyncPushRequest(cambios));
      } on ErrorRespuestaApi catch (e) {
        // El backend respondió con un error (4xx/5xx no-401): el lote fue
        // *rechazado*, no es una caída de red. La causa más común es un dato
        // que el backend no acepta ("poison message") -- reintentarlo para
        // siempre solo gasta red y nunca avanza. Por eso este camino SÍ cuenta
        // hacia el dead-letter: tras `maxIntentos` rechazos, la fila se aparta
        // (`intentos = -2`) para intervención manual y deja de seleccionarse en
        // el drenado (`where: intentos >= 0`). Limitación conocida: como el
        // backend falla el POST completo sin decir cuál ítem lo rompió (ver el
        // doc de la clase), las filas buenas que compartan lote con el poison
        // también acumulan intentos; se acepta porque un rechazo persistente
        // del backend necesita revisión humana de todos modos.
        await _registrarFalloDeLote(db, filas, e.mensaje, progresaDeadLetter: true);
        fallidos += filas.length;
        continue;
      } catch (e) {
        // Sin conexión (`ErrorRed`), sesión por re-loguear
        // (`SesionExpiradaException`), o cualquier otro fallo transitorio: el
        // dato está bien, lo que falló es el transporte. NO progresa hacia
        // dead-letter -- solo se registra el motivo y el lote se reintenta
        // íntegro en el próximo ciclo. Así una tienda que pasa horas sin
        // internet no termina mandando ventas buenas al dead-letter.
        await _registrarFalloDeLote(db, filas, e.toString(), progresaDeadLetter: false);
        fallidos += filas.length;
        continue;
      }

      // El backend preserva el orden y la cantidad de `resultados` respecto
      // a `cambios` (itera `request.Cambios` una vez, agregando un
      // resultado por ítem -- ver `PushAsync` en SyncService.cs): si esto
      // dejara de cumplirse sería un cambio de contrato del backend, no un
      // caso a tolerar en silencio acá.
      for (var i = 0; i < filas.length; i++) {
        final fila = filas[i];
        final resultado = respuesta.resultados[i];

        if (resultado.omitidoPorServidor) {
          entidadesAPullearDeNuevo.add(fila['entidad'] as String);
          omitidosPorServidor++;
        } else {
          subidos++;
        }

        await db.delete('Sync_Outbox', where: 'id = ?', whereArgs: [fila['id']]);
      }
    }

    return ResultadoDrenado(
      subidos: subidos,
      omitidosPorServidor: omitidosPorServidor,
      fallidos: fallidos,
      entidadesAPullearDeNuevo: entidadesAPullearDeNuevo,
    );
  }

  /// Marca cada fila de un lote fallido con el motivo del error. Si
  /// [progresaDeadLetter] es `true`, incrementa `intentos` y, al alcanzar
  /// [SyncOutboxDeadLetter.maxIntentos], aparta la fila como fallida permanente
  /// ([SyncOutboxDeadLetter.intentosFallidaPermanente]). Si es `false`, solo
  /// registra el motivo sin tocar `intentos` (fallo transitorio, no imputable a
  /// los datos).
  Future<void> _registrarFalloDeLote(
    DatabaseExecutor db,
    List<Map<String, Object?>> filas,
    String motivo, {
    required bool progresaDeadLetter,
  }) async {
    for (final fila in filas) {
      final valores = <String, Object?>{'ultimo_error': motivo};

      if (progresaDeadLetter) {
        final nuevosIntentos = (fila['intentos'] as int) + 1;
        valores['intentos'] = nuevosIntentos >= SyncOutboxDeadLetter.maxIntentos
            ? SyncOutboxDeadLetter.intentosFallidaPermanente
            : nuevosIntentos;
      }

      await db.update('Sync_Outbox', valores, where: 'id = ?', whereArgs: [fila['id']]);
    }
  }
}
