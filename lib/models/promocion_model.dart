import '../core/utils/descuento_utils.dart';

/// Tipo de promoción automática. El nombre de cada valor coincide
/// exactamente con lo que se guarda en `Promociones.tipo` (columna con
/// CHECK), así que no lleva una función `nombre` separada como
/// [TipoDescuento].
enum TipoPromocion {
  porcentajeProducto,
  montoFijoProducto,
  nxy,
  descuentoCantidad,
  combo;

  String get nombreDb {
    switch (this) {
      case TipoPromocion.porcentajeProducto:
        return 'PORCENTAJE_PRODUCTO';
      case TipoPromocion.montoFijoProducto:
        return 'MONTO_FIJO_PRODUCTO';
      case TipoPromocion.nxy:
        return 'NXY';
      case TipoPromocion.descuentoCantidad:
        return 'DESCUENTO_CANTIDAD';
      case TipoPromocion.combo:
        return 'COMBO';
    }
  }

  static TipoPromocion desdeNombreDb(String nombre) {
    switch (nombre) {
      case 'PORCENTAJE_PRODUCTO':
        return TipoPromocion.porcentajeProducto;
      case 'MONTO_FIJO_PRODUCTO':
        return TipoPromocion.montoFijoProducto;
      case 'NXY':
        return TipoPromocion.nxy;
      case 'DESCUENTO_CANTIDAD':
        return TipoPromocion.descuentoCantidad;
      case 'COMBO':
        return TipoPromocion.combo;
      default:
        throw Exception('Tipo de promoción desconocido: "$nombre".');
    }
  }
}

/// Producto y cantidad requerida dentro de un combo (`Promocion_Combo_Items`).
class ComboItem {
  final int idProducto;
  final int cantidad;

  const ComboItem({required this.idProducto, required this.cantidad});

  Map<String, dynamic> toMap(int idPromocion) => {
        'id_promocion': idPromocion,
        'id_producto': idProducto,
        'cantidad': cantidad,
      };

  factory ComboItem.fromMap(Map<String, dynamic> map) => ComboItem(
        idProducto: map['id_producto'] as int,
        cantidad: map['cantidad'] as int,
      );
}

/// Definición completa de una promoción, incluyendo sus participantes ya
/// resueltos (productos/categorías, o los items del combo). No toca la base
/// de datos: es lo que [PromocionesController] arma a partir de varias
/// tablas, y lo que consume el motor puro en `promociones_engine.dart`.
class Promocion {
  final int? idPromocion;
  final String nombre;
  final TipoPromocion tipo;
  final bool activo;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final int prioridad;
  final bool combinable;

  final double? valor;
  final TipoDescuento? tipoValor;
  final int? cantidadMinima;
  final int? nxLleva;
  final int? nxPaga;
  final double? precioCombo;

  final List<int> productosIds;
  final List<int> categoriasIds;
  final List<ComboItem> comboItems;

  final DateTime? fechaCreacion;
  final String? creadoPor;

  const Promocion({
    this.idPromocion,
    required this.nombre,
    required this.tipo,
    this.activo = true,
    this.fechaInicio,
    this.fechaFin,
    this.prioridad = 0,
    this.combinable = false,
    this.valor,
    this.tipoValor,
    this.cantidadMinima,
    this.nxLleva,
    this.nxPaga,
    this.precioCombo,
    this.productosIds = const [],
    this.categoriasIds = const [],
    this.comboItems = const [],
    this.fechaCreacion,
    this.creadoPor,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'tipo': tipo.nombreDb,
      'activo': activo ? 1 : 0,
      'fecha_inicio': fechaInicio?.toIso8601String(),
      'fecha_fin': fechaFin?.toIso8601String(),
      'prioridad': prioridad,
      'combinable': combinable ? 1 : 0,
      'valor': valor,
      'tipo_valor': tipoValor?.nombre,
      'cantidad_minima': cantidadMinima,
      'nx_lleva': nxLleva,
      'nx_paga': nxPaga,
      'precio_combo': precioCombo,
      'fecha_creacion': (fechaCreacion ?? DateTime.now()).toIso8601String(),
      'creado_por': creadoPor,
    };

    if (idPromocion != null) {
      map['id_promocion'] = idPromocion;
    }

    return map;
  }

  factory Promocion.fromMap(
    Map<String, dynamic> map, {
    List<int> productosIds = const [],
    List<int> categoriasIds = const [],
    List<ComboItem> comboItems = const [],
  }) {
    return Promocion(
      idPromocion: map['id_promocion'] as int?,
      nombre: map['nombre'] as String,
      tipo: TipoPromocion.desdeNombreDb(map['tipo'] as String),
      activo: (map['activo'] as int? ?? 1) == 1,
      fechaInicio: map['fecha_inicio'] != null ? DateTime.parse(map['fecha_inicio'] as String) : null,
      fechaFin: map['fecha_fin'] != null ? DateTime.parse(map['fecha_fin'] as String) : null,
      prioridad: map['prioridad'] as int? ?? 0,
      combinable: (map['combinable'] as int? ?? 0) == 1,
      valor: (map['valor'] as num?)?.toDouble(),
      tipoValor: TipoDescuento.desdeNombre(map['tipo_valor'] as String?),
      cantidadMinima: map['cantidad_minima'] as int?,
      nxLleva: map['nx_lleva'] as int?,
      nxPaga: map['nx_paga'] as int?,
      precioCombo: (map['precio_combo'] as num?)?.toDouble(),
      productosIds: productosIds,
      categoriasIds: categoriasIds,
      comboItems: comboItems,
      fechaCreacion: map['fecha_creacion'] != null ? DateTime.parse(map['fecha_creacion'] as String) : null,
      creadoPor: map['creado_por'] as String?,
    );
  }

  Promocion copyWith({
    int? idPromocion,
    String? nombre,
    TipoPromocion? tipo,
    bool? activo,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? prioridad,
    bool? combinable,
    double? valor,
    TipoDescuento? tipoValor,
    int? cantidadMinima,
    int? nxLleva,
    int? nxPaga,
    double? precioCombo,
    List<int>? productosIds,
    List<int>? categoriasIds,
    List<ComboItem>? comboItems,
  }) {
    return Promocion(
      idPromocion: idPromocion ?? this.idPromocion,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      activo: activo ?? this.activo,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      prioridad: prioridad ?? this.prioridad,
      combinable: combinable ?? this.combinable,
      valor: valor ?? this.valor,
      tipoValor: tipoValor ?? this.tipoValor,
      cantidadMinima: cantidadMinima ?? this.cantidadMinima,
      nxLleva: nxLleva ?? this.nxLleva,
      nxPaga: nxPaga ?? this.nxPaga,
      precioCombo: precioCombo ?? this.precioCombo,
      productosIds: productosIds ?? this.productosIds,
      categoriasIds: categoriasIds ?? this.categoriasIds,
      comboItems: comboItems ?? this.comboItems,
      fechaCreacion: fechaCreacion,
      creadoPor: creadoPor,
    );
  }
}
