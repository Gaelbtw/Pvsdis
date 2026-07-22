import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';

/// Un campo escalar mapeado entre la fila local y el payload backend.
/// [campoBackend] ya va en camelCase (ver la nota de casing en
/// `entity_mapper.dart`). [aBackend]/[aLocal] son transformaciones
/// opcionales para cuando el tipo/forma no coincide 1:1 (ej. `telefono`
/// local es `int`, el backend lo espera como `string`).
class CampoMapeo {
  const CampoMapeo(this.campoLocal, this.campoBackend, {this.aBackend, this.aLocal});

  final String campoLocal;
  final String campoBackend;
  final dynamic Function(dynamic valorLocal)? aBackend;
  final dynamic Function(dynamic valorBackend)? aLocal;

  dynamic valorParaBackend(dynamic valorLocal) => aBackend != null ? aBackend!(valorLocal) : valorLocal;
  dynamic valorParaLocal(dynamic valorBackend) => aLocal != null ? aLocal!(valorBackend) : valorBackend;
}

/// [EntityMapper] declarativo para catálogos "id + escalares" sin lógica de
/// negocio propia (Categoria, Cliente, Proveedor): se instancia con una
/// lista de [CampoMapeo] en vez de escribir una subclase por entidad.
///
/// Entidades con lógica propia (cálculo de IVA en Producto, mapeo de
/// `estado` en Venta, participantes de Promocion, etc.) NO caben aquí --
/// necesitan su propio archivo implementando [EntityMapper] directo.
///
/// Todas las instancias de esta clase son [ServidorGana] del lado del
/// backend (catálogos): el push de una fila que ya existe en el servidor
/// siempre vuelve como `"OmitidoServidorGana"`, nunca sobrescribe. Por eso
/// campos de negocio que no tienen columna local equivalente (ej.
/// `Cliente.LimiteCredito`, `Proveedor.Email`) simplemente se omiten del
/// payload de push en vez de forzarlos a `null`: el backend los deja en su
/// valor por default de todos modos, y como nunca se llega a sobrescribir
/// una fila ya existente desde el cliente, no hay riesgo de "borrar" un
/// valor que el usuario haya cargado directamente en el backend. Es una
/// limitación real del esquema local (no hay dónde guardar esos campos hoy
/// en `pos.db`), documentada aquí en vez de disimulada.
class SimpleCatalogMapper extends EntityMapper {
  SimpleCatalogMapper({
    required this.entidadBackend,
    required this.tablaLocal,
    required this.columnaIdLocal,
    required this.campos,
    this.esAuditable = true,
  });

  @override
  final String entidadBackend;

  @override
  final String tablaLocal;

  @override
  final String columnaIdLocal;

  final List<CampoMapeo> campos;

  /// Si `true`, agrega `activo: true` al payload de push (sobre de
  /// `AuditableEntity` del backend). Ninguna de las tablas locales de
  /// catálogo (`Categorias`, `Clientes`, `Proveedores`) tiene hoy una
  /// columna de estado activo/inactivo propia, así que se asume `true` fijo
  /// -- si más adelante se agrega soft-delete local a alguna, este campo
  /// deja de ser un booleano fijo y pasa a ser un [CampoMapeo] más.
  final bool esAuditable;

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError(
        'No se puede sincronizar la fila de $tablaLocal sin guid_sync (id local: ${filaLocal[columnaIdLocal]}). '
        '¿Se insertó con DatabaseHelper.insertarConGuidSync?',
      );
    }

    final ahora = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'id': guid,
      'tenantId': tenantId,
      // No hay columna local de fecha de alta/edición para estos catálogos
      // (Categorias/Clientes/Proveedores no la llevan): se aproxima con
      // "ahora". Solo importa para el primer "Insertado" -- reintentos
      // posteriores de la misma fila (ya existente en el servidor) vuelven
      // "OmitidoServidorGana" y nunca llegan a sobrescribir estas fechas
      // (ver AplicarCambioAsync en SyncService.cs).
      'fechaCreacion': ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      if (esAuditable) 'activo': true,
    };

    for (final campo in campos) {
      payload[campo.campoBackend] = campo.valorParaBackend(filaLocal[campo.campoLocal]);
    }

    return payload;
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    final guid = elementoBackend['id'] as String;

    if (elementoBackend['isDeleted'] == true) {
      // Ver la nota de alcance en el README de la Fase 3: propagar borrados
      // de catálogo hacia abajo (¿hard delete? ¿algún estado local
      // "inactivo" que hoy no existe para estas tablas?) queda fuera de
      // esta sub-fase. Se ignora en vez de fallar, para no tumbar el resto
      // del pull por un borrado que todavía no se sabe aplicar.
      return;
    }

    final valoresLocales = <String, Object?>{
      for (final campo in campos) campo.campoLocal: campo.valorParaLocal(elementoBackend[campo.campoBackend]),
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
