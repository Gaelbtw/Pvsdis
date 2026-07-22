import 'package:sqflite/sqflite.dart';

import 'entity_mapper.dart';
import 'enums_backend.dart';

/// `Promociones` (local) <-> `Promocion` (backend, `ServidorGana`). Solo la
/// fila propia de la promoción -- **no** sus participantes
/// (`Promocion_Productos`/`Promocion_Categorias`/`Promocion_Combo_Items`).
///
/// Sincronizar los participantes se deja fuera de esta sub-fase a
/// propósito, no es un olvido: el backend limpia toda propiedad de
/// navegación del objeto recibido antes de guardar un push
/// (`LimpiarNavegaciones` en `SyncService.cs:150-157`, para no insertar en
/// cascada catálogos relacionados), así que mandar `Productos`/`Categorias`/
/// `ComboItems` anidados dentro del payload de `Promocion` no tendría efecto
/// -- estas 3 tablas puente tendrían que sincronizarse como entidades
/// propias (`PromocionProducto`, `PromocionCategoria`, `PromocionComboItem`,
/// que sí están en `SyncEntidadRegistry`), cada una con su propio `Id`
/// estable. Eso choca con una decisión ya tomada en la Fase 2 (ver
/// `lib/core/sync/README-fase2.md`): estas tablas locales NO tienen
/// `guid_sync` propio a propósito, porque se asumió que se repoblarían
/// completas junto con su fila padre en cada pull. Además, el pull de
/// `Promocion` tal como está implementado hoy (`PullGenericoAsync` en
/// `SyncService.cs`, sin `.Include(...)`) tampoco trae poblada esa
/// colección. Sincronizar participantes es, entonces, un cambio que
/// necesita tocar ambos lados (cliente y backend) y verificarse contra un
/// pull real antes de diseñarse -- se deja como siguiente paso explícito,
/// no se improvisa una solución a medias acá.
class PromocionMapper extends EntityMapper {
  @override
  String get entidadBackend => 'Promocion';

  @override
  String get tablaLocal => 'Promociones';

  @override
  String get columnaIdLocal => 'id_promocion';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Promocion sin guid_sync (id local: ${filaLocal['id_promocion']}).');
    }

    final tipoLocal = filaLocal['tipo'] as String;
    final tipoBackend = tipoPromocionLocalABackend[tipoLocal];
    if (tipoBackend == null) {
      throw StateError('Tipo de promoción local desconocido: "$tipoLocal".');
    }

    final tipoValorLocal = filaLocal['tipo_valor'] as String?;
    final fechaInicioLocal = filaLocal['fecha_inicio'] as String?;
    final ahora = DateTime.now().toUtc().toIso8601String();

    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': (filaLocal['fecha_creacion'] as String?) ?? ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      'activo': (filaLocal['activo'] as int? ?? 1) == 1,
      'nombre': filaLocal['nombre'],
      'tipo': tipoBackend,
      'prioridad': filaLocal['prioridad'] ?? 0,
      'combinable': (filaLocal['combinable'] as int? ?? 0) == 1,
      'valor': (filaLocal['valor'] as num?)?.toDouble(),
      if (tipoValorLocal != null) 'tipoValor': tipoValorLocalABackend[tipoValorLocal],
      'cantidadMinima': filaLocal['cantidad_minima'],
      'nxLleva': filaLocal['nx_lleva'],
      'nxPaga': filaLocal['nx_paga'],
      'precioCombo': (filaLocal['precio_combo'] as num?)?.toDouble(),
      // FechaInicio no es nullable del lado del backend; si la promoción
      // local nunca tuvo fecha de inicio (campo nullable acá), se aproxima
      // con "ahora" en vez de fallar el push.
      'fechaInicio': fechaInicioLocal ?? ahora,
      'fechaFin': filaLocal['fecha_fin'],
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    if (elementoBackend['isDeleted'] == true) {
      return;
    }

    final guid = elementoBackend['id'] as String;
    final tipoBackend = elementoBackend['tipo'] as String;
    final tipoLocal = tipoPromocionBackendALocal[tipoBackend];
    if (tipoLocal == null) {
      throw StateError('Tipo de promoción del backend desconocido: "$tipoBackend".');
    }

    final tipoValorBackend = elementoBackend['tipoValor'] as String?;

    final valoresLocales = <String, Object?>{
      'nombre': elementoBackend['nombre'],
      'tipo': tipoLocal,
      'activo': (elementoBackend['activo'] as bool? ?? true) ? 1 : 0,
      'fecha_inicio': elementoBackend['fechaInicio'],
      'fecha_fin': elementoBackend['fechaFin'],
      'prioridad': elementoBackend['prioridad'] ?? 0,
      'combinable': (elementoBackend['combinable'] as bool? ?? false) ? 1 : 0,
      'valor': (elementoBackend['valor'] as num?)?.toDouble(),
      'tipo_valor': tipoValorBackend == null ? null : tipoValorBackendALocal[tipoValorBackend],
      'cantidad_minima': elementoBackend['cantidadMinima'],
      'nx_lleva': elementoBackend['nxLleva'],
      'nx_paga': elementoBackend['nxPaga'],
      'precio_combo': (elementoBackend['precioCombo'] as num?)?.toDouble(),
      'fecha_creacion': elementoBackend['fechaCreacion'] ?? DateTime.now().toUtc().toIso8601String(),
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
