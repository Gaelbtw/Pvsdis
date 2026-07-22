import 'package:sqflite/sqflite.dart';

import '../../config/app_config.dart';
import 'entity_mapper.dart';

/// `Producto` (local) <-> `Producto` (backend, `ServidorGana`).
///
/// No es un [SimpleCatalogMapper] porque el shape no es 1:1: el backend
/// pide IVA por producto (`AplicaIva`, `TasaIva`, `PrecioBase` sin IVA) y el
/// local solo guarda un `precio` único con IVA incluido, sin concepto de
/// IVA por producto. Decisión de negocio ya acordada con el usuario (no es
/// una suposición de esta clase): se usa la tasa GLOBAL de
/// `Configuracion.tasaImpuestoPorcentaje` para todos los productos por
/// igual. `AplicaIva = tasa > 0`; si aplica, `PrecioBase = precio /
/// (1 + tasa)`, si no, `PrecioBase = precio`. `CostoPromedio = precio_compra
/// ?? 0`. `UnidadMedida` no existe en el modelo local -> fija en `'Pieza'`.
/// `FactorConversion`/`UnidadCompra` se omiten del payload (el backend los
/// deja en su default -- `1`/`null` -- al insertar; como Producto es
/// ServidorGana, un push posterior sobre una fila ya existente nunca llega
/// a sobrescribir, así que omitirlos es seguro, no solo en el primer
/// insert).
///
/// `Codigo` es obligatorio en el backend; `codigo_barras` local es
/// opcional. Si no hay código de barras se genera un fallback determinista
/// (`'SIN-CODIGO-<id_producto>'`) -- estable entre reintentos del mismo
/// producto, aunque no garantiza unicidad real entre dispositivos distintos
/// del mismo tenant (limitación conocida, documentada, no bloqueante para
/// esta fase).
///
/// Al insertar un producto nuevo recibido por pull (server -> cliente), se
/// crea también su fila `Inventario` local en `cantidad: 0` -- el resto de
/// la app asume que todo `Producto` tiene exactamente una fila `Inventario`
/// (`id_producto UNIQUE`); sin esto, un producto creado en el backend y
/// jalado por pull antes de que llegue su `Stock` rompería esa asunción.
/// `StockMapper` (pull-only) actualiza la cantidad real en un pull
/// posterior.
class ProductoMapper extends EntityMapper {
  @override
  String get entidadBackend => 'Producto';

  @override
  String get tablaLocal => 'Producto';

  @override
  String get columnaIdLocal => 'id_producto';

  @override
  Future<Map<String, dynamic>> aBackend({
    required Map<String, dynamic> filaLocal,
    required String tenantId,
    required String usuarioIdSync,
    required FkResolver resolver,
  }) async {
    final guid = filaLocal['guid_sync'] as String?;
    if (guid == null) {
      throw StateError('No se puede sincronizar Producto sin guid_sync (id local: ${filaLocal['id_producto']}).');
    }

    final idCategoriaLocal = filaLocal['id_categoria'] as int?;
    final categoriaGuid = idCategoriaLocal == null
        ? null
        : await resolver.guidPorIdLocal('Categorias', idCategoriaLocal);
    if (categoriaGuid == null) {
      throw StateError(
        'Producto ${filaLocal['id_producto']} no se puede sincronizar: el backend exige una categoría '
        '(CategoriaId) y este producto no tiene una categoría local con guid_sync resuelto todavía.',
      );
    }

    final tasaPorcentaje = AppConfig.actual.tasaImpuestoPorcentaje;
    final tasaDecimal = tasaPorcentaje / 100;
    final aplicaIva = tasaPorcentaje > 0;
    final precio = (filaLocal['precio'] as num).toDouble();
    final precioBase = aplicaIva ? precio / (1 + tasaDecimal) : precio;
    final precioCompra = (filaLocal['precio_compra'] as num?)?.toDouble();
    final idProducto = filaLocal['id_producto'];
    final codigoBarras = filaLocal['codigo_barras'] as String?;

    final ahora = DateTime.now().toUtc().toIso8601String();
    return {
      'id': guid,
      'tenantId': tenantId,
      'fechaCreacion': ahora,
      'fechaModificacion': ahora,
      'isDeleted': false,
      'activo': (filaLocal['estado'] as String?) != 'Inactivo',
      'codigo': (codigoBarras == null || codigoBarras.isEmpty) ? 'SIN-CODIGO-$idProducto' : codigoBarras,
      'nombre': filaLocal['nombre'],
      'descripcion': filaLocal['descripcion'],
      'categoriaId': categoriaGuid,
      'unidadMedida': 'Pieza',
      'precioBase': precioBase,
      'precioVenta': precio,
      'aplicaIva': aplicaIva,
      'tasaIva': tasaDecimal,
      'costoPromedio': precioCompra ?? 0,
      'stockMinimo': filaLocal['stock_minimo'] ?? 0,
    };
  }

  @override
  Future<void> upsertLocal({
    required DatabaseExecutor db,
    required Map<String, dynamic> elementoBackend,
    required FkResolver resolver,
  }) async {
    if (elementoBackend['isDeleted'] == true) {
      // Ver la nota de alcance de SimpleCatalogMapper: propagar borrados de
      // catálogo hacia el local queda fuera de esta sub-fase.
      return;
    }

    final guid = elementoBackend['id'] as String;
    final categoriaGuid = elementoBackend['categoriaId'] as String?;
    final idCategoriaLocal =
        categoriaGuid == null ? null : await resolver.idLocalPorGuid('Categorias', 'id_categoria', categoriaGuid);

    final valoresLocales = <String, Object?>{
      'nombre': elementoBackend['nombre'],
      'descripcion': elementoBackend['descripcion'],
      'precio': (elementoBackend['precioVenta'] as num).toDouble(),
      'precio_compra': (elementoBackend['costoPromedio'] as num?)?.toDouble(),
      'id_categoria': idCategoriaLocal,
      'codigo_barras': elementoBackend['codigo'],
      'stock_minimo': elementoBackend['stockMinimo'] ?? 0,
      'estado': (elementoBackend['activo'] as bool? ?? true) ? 'Activo' : 'Inactivo',
    };

    final idLocalExistente = await resolver.idLocalPorGuid(tablaLocal, columnaIdLocal, guid);

    if (idLocalExistente == null) {
      final idNuevo = await db.insert(tablaLocal, {...valoresLocales, 'guid_sync': guid});
      resolver.registrar(tablaLocal, guid, idNuevo);
      // Todo Producto tiene exactamente una fila Inventario (id_producto
      // UNIQUE) -- ver nota de clase. StockMapper corrige la cantidad real
      // en un pull posterior de 'Stock'.
      await db.insert('Inventario', {'id_producto': idNuevo, 'cantidad': 0});
    } else {
      await db.update(tablaLocal, valoresLocales, where: '$columnaIdLocal = ?', whereArgs: [idLocalExistente]);
    }
  }
}
