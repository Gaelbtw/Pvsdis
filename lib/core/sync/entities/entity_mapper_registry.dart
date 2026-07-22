import 'categoria_mapper.dart';
import 'cliente_mapper.dart';
import 'entity_mapper.dart';
import 'proveedor_mapper.dart';

/// Punto único de acceso a todos los [EntityMapper] de la app, indexado por
/// el nombre exacto de entidad del backend (`SyncEntidadRegistry` en
/// `EsqueletoPOS/src/EsqPos.Infrastructure/Persistence/SyncService.cs`).
///
/// Sub-fase 3b (esta): solo los 3 catálogos declarativos (Categoria,
/// Cliente, Proveedor). Sub-fase 3c agrega el resto (Producto, Stock,
/// Promocion+puente, Venta+Detalle+Pago+Promocion, CajaSesion+Movimiento*+
/// CorteCaja) a este mismo mapa -- ningún otro archivo debería necesitar
/// tocarse para agregar un mapper nuevo.
class EntityMapperRegistry {
  EntityMapperRegistry._();

  static final Map<String, EntityMapper> _porEntidad = {
    'CategoriaProducto': categoriaMapper,
    'Cliente': clienteMapper,
    'Proveedor': proveedorMapper,
  };

  /// El [EntityMapper] registrado para [entidad] (nombre backend). Lanza
  /// [ArgumentError] si no hay ninguno -- llamar con una entidad no
  /// registrada es un error del llamador (típicamente: `SyncEntidadRegistry`
  /// del backend tiene una entidad nueva que todavía no se instrumentó acá),
  /// no un caso silencioso a tolerar.
  static EntityMapper paraEntidad(String entidad) {
    final mapper = _porEntidad[entidad];
    if (mapper == null) {
      throw ArgumentError('No hay EntityMapper registrado para la entidad "$entidad".');
    }
    return mapper;
  }

  static bool tieneMapper(String entidad) => _porEntidad.containsKey(entidad);

  /// Todas las entidades con mapper registrado (para que el motor de pull
  /// sepa qué pedir sin tener que hardcodear la lista en otro lado).
  static Iterable<String> get entidadesRegistradas => _porEntidad.keys;

  /// Orden padre-antes-que-hijo para aplicar un pull (ver comentario en
  /// `sync_dtos.dart`: el backend no es transaccional entre ítems del push,
  /// y para el pull el cliente debe poder resolver cada FK contra una fila
  /// que ya haya sido insertada). Catálogos primero, y dentro de catálogos,
  /// lo que no depende de nada antes de lo que sí (Producto depende de
  /// CategoriaProducto; Stock depende de Producto).
  ///
  /// Se define aquí (no como constante estática con todos los tipos porque
  /// varios todavía no existen en 3b) y se completa en 3c.
  static const List<String> ordenPull = [
    'CategoriaProducto',
    'Cliente',
    'Proveedor',
  ];
}
