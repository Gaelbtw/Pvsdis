import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';
import 'enums_backend.dart';

const Map<String, String> _estadoLocalABackend = {
  'Activa': 'Completada',
  // "Cancelada" local significa "todo lo pendiente ya se devolvió" (ver
  // devoluciones_controller.dart:392: nuevoEstado se pone en 'Cancelada'
  // solo cuando pendienteTotalRestante == 0), no "se anuló antes de
  // completarse" como sugeriría el nombre -- por eso mapea a Devuelta, no a
  // Cancelada, del lado del backend.
  'Cancelada': 'Devuelta',
  'Parcialmente devuelta': 'ParcialmenteDevuelta',
};
const Map<String, String> _estadoBackendALocal = {
  'Completada': 'Activa',
  'Devuelta': 'Cancelada',
  'ParcialmenteDevuelta': 'Parcialmente devuelta',
  // 'Credito' del backend no tiene contraparte local (el Flutter no modela
  // ventas a crédito hoy) -- se aterriza en 'Activa' como el estado menos
  // sorprendente en vez de fallar el pull.
  'Credito': 'Activa',
};

/// `Ventas` (local) <-> `Venta` (backend, `ClienteGana`: es un hecho ya
/// ocurrido, nunca se rechaza).
///
/// `SucursalId` y `UsuarioId` no salen de la fila local (que no tiene
/// ninguno de los dos con ese significado): `UsuarioId` es
/// [usuarioIdSync] (la sesión de sincronización, nunca el `id_usuario`
/// local del cajero -- ver la nota en `entity_mapper.dart`), `SucursalId`
/// sale de `resolver.sucursalConfigurada()`. Si todavía no hay sucursal
/// resuelta para este dispositivo, se lanza [StateError] -- el llamador
/// (`SyncOutboxWriter`, sub-fase 3f) debe capturarlo y dejar el push en
/// espera hasta que `SucursalResolver` (3d) resuelva una, no reintentarlo a
/// ciegas.
///
/// `Numero` no tiene columna local equivalente -- se sintetiza como
/// `'V-<id_venta>'`, estable entre reintentos del mismo registro.
/// `MontoRecibido` tampoco se guarda directo localmente: se aproxima como
/// `total + cambio` (por definición, `cambio = recibido - total`).
/// `Observaciones` no tiene columna local -- se omite del push.
class VentaMapper extends EntityMapper {
  @override
  String get entidadBackend => 'Venta';

  @override
  String get tablaLocal => 'Ventas';

  @override
  String get columnaIdLocal => 'id_venta';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Venta sin guid_sync (id local: ${filaLocal['id_venta']}).');
    }

    final sucursalId = await resolver.sucursalConfigurada();
    if (sucursalId == null) {
      throw StateError('No se puede sincronizar Venta ${filaLocal['id_venta']}: sucursal del dispositivo sin resolver todavía.');
    }

    final idCaja = filaLocal['id_caja'] as int?;
    final cajaGuid = idCaja == null ? null : await resolver.guidPorIdLocal('Cajas', idCaja);
    if (cajaGuid == null) {
      throw StateError(
        'No se puede sincronizar Venta ${filaLocal['id_venta']}: su caja (id_caja=$idCaja) no tiene guid_sync resuelto.',
      );
    }

    final idCliente = filaLocal['id_cliente'] as int?;
    final clienteGuid = idCliente == null ? null : await resolver.guidPorIdLocal('Clientes', idCliente);

    final estadoLocal = (filaLocal['estado'] as String?) ?? 'Activa';
    final estadoBackend = _estadoLocalABackend[estadoLocal] ?? 'Completada';

    final total = (filaLocal['total'] as num?)?.toDouble() ?? 0;
    final cambio = (filaLocal['cambio'] as num?)?.toDouble() ?? 0;
    final fecha = (filaLocal['fecha'] as String?) ?? DateTime.now().toUtc().toIso8601String();

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': fecha,
      'fechaModificacion': fecha,
      'isDeleted': false,
      'numero': 'V-${filaLocal['id_venta']}',
      'clienteId': clienteGuid,
      'sucursalId': sucursalId,
      'usuarioId': usuarioIdSync,
      'cajaSesionId': cajaGuid,
      'fecha': fecha,
      'descuento': (filaLocal['descuento_total'] as num?)?.toDouble() ?? 0,
      'total': total,
      'montoRecibido': total + cambio,
      'cambio': cambio,
      'metodoPago': metodoPagoABackend((filaLocal['metodo_pago'] as String?) ?? 'efectivo'),
      'estado': estadoBackend,
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final guid = elementoBackend['id'] as String;

    final clienteGuid = elementoBackend['clienteId'] as String?;
    final idClienteLocal =
        clienteGuid == null ? null : await resolver.idLocalPorGuid('Clientes', 'id_cliente', clienteGuid);

    final cajaGuid = elementoBackend['cajaSesionId'] as String?;
    final idCajaLocal = cajaGuid == null ? null : await resolver.idLocalPorGuid('Cajas', 'id_caja', cajaGuid);

    final estadoBackend = elementoBackend['estado'] as String? ?? 'Completada';

    // 'id_usuario' se deja fuera a propósito: es un cajero LOCAL (login
    // bcrypt contra pos.db), sistema de identidad distinto al usuario de
    // sincronización (Guid) que trae el pull -- no hay un valor correcto
    // que poner para una Venta hecha en otro dispositivo. A diferencia de
    // `Cajas.id_usuario` (NOT NULL, ver CajaSesionMapper), esta columna es
    // nullable, así que simplemente se omite en vez de bloquear el pull.
    final valoresLocales = <String, Object?>{
      'id_cliente': idClienteLocal,
      'id_caja': idCajaLocal,
      'fecha': elementoBackend['fecha'],
      'total': (elementoBackend['total'] as num?)?.toDouble() ?? 0,
      'metodo_pago': (elementoBackend['metodoPago'] as String? ?? 'Efectivo').toLowerCase(),
      'estado': _estadoBackendALocal[estadoBackend] ?? 'Activa',
      'descuento_total': (elementoBackend['descuento'] as num?)?.toDouble() ?? 0,
      'cambio': (elementoBackend['cambio'] as num?)?.toDouble() ?? 0,
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
