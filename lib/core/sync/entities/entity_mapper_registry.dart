import 'caja_sesion_mapper.dart';
import 'categoria_mapper.dart';
import 'cliente_mapper.dart';
import 'corte_caja_mapper.dart';
import 'entity_mapper.dart';
import 'movimiento_caja_mapper.dart';
import 'movimiento_inventario_mapper.dart';
import 'producto_mapper.dart';
import 'promocion_mapper.dart';
import 'proveedor_mapper.dart';
import 'stock_mapper.dart';
import 'venta_detalle_mapper.dart';
import 'venta_mapper.dart';
import 'venta_pago_mapper.dart';
import 'venta_promocion_mapper.dart';

/// Punto único de acceso a todos los [EntityMapper] de la app, indexado por
/// el nombre exacto de entidad del backend (`SyncEntidadRegistry` en
/// `EsqueletoPOS/src/EsqPos.Infrastructure/Persistence/SyncService.cs`).
///
/// Entidades del backend deliberadamente SIN mapper (documentado, no un
/// olvido): `PromocionProducto`, `PromocionCategoria`, `PromocionComboItem`,
/// `VentaPromocionDetalle` -- ver la nota de alcance en `promocion_mapper.dart`
/// y `venta_promocion_mapper.dart`.
class EntityMapperRegistry {
  EntityMapperRegistry._();

  static final Map<String, EntityMapper> _porEntidad = {
    'CategoriaProducto': categoriaMapper,
    'Cliente': clienteMapper,
    'Proveedor': proveedorMapper,
    'Producto': ProductoMapper(),
    'Stock': StockMapper(),
    'Promocion': PromocionMapper(),
    'CajaSesion': CajaSesionMapper(),
    'Venta': VentaMapper(),
    'VentaDetalle': VentaDetalleMapper(),
    'VentaPago': VentaPagoMapper(),
    'VentaPromocion': VentaPromocionMapper(),
    'MovimientoInventario': MovimientoInventarioMapper(),
    'MovimientoCaja': MovimientoCajaMapper(),
    'CorteCaja': CorteCajaMapper(),
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

  /// Orden padre-antes-que-hijo para aplicar un pull: cada entidad de la
  /// lista solo depende (por FK) de entidades que aparecen antes que ella.
  /// `CajaSesion` va antes que `Venta` (Venta.CajaSesionId); `Venta` antes
  /// que sus hijos (`VentaDetalle`/`VentaPago`/`VentaPromocion`);
  /// `MovimientoInventario`/`MovimientoCaja`/`CorteCaja` al final porque
  /// pueden referenciar Producto/Caja/Venta ya resueltos.
  static const List<String> ordenPull = [
    'CategoriaProducto',
    'Producto',
    'Cliente',
    'Proveedor',
    'Stock',
    'Promocion',
    'CajaSesion',
    'Venta',
    'VentaDetalle',
    'VentaPago',
    'VentaPromocion',
    'MovimientoInventario',
    'MovimientoCaja',
    'CorteCaja',
  ];
}
