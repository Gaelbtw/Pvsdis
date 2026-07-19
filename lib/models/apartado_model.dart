import '../core/utils/descuento_utils.dart';

/// Estado de un apartado. El nombre de cada valor coincide exactamente con
/// lo que se guarda en `Apartados.estado` (columna con CHECK).
enum EstadoApartado {
  pendiente,
  liquidado,
  cancelado,
  vencido;

  String get nombreDb {
    switch (this) {
      case EstadoApartado.pendiente:
        return 'Pendiente';
      case EstadoApartado.liquidado:
        return 'Liquidado';
      case EstadoApartado.cancelado:
        return 'Cancelado';
      case EstadoApartado.vencido:
        return 'Vencido';
    }
  }

  static EstadoApartado desdeNombreDb(String nombre) {
    switch (nombre) {
      case 'Pendiente':
        return EstadoApartado.pendiente;
      case 'Liquidado':
        return EstadoApartado.liquidado;
      case 'Cancelado':
        return EstadoApartado.cancelado;
      case 'Vencido':
        return EstadoApartado.vencido;
      default:
        throw Exception('Estado de apartado desconocido: "$nombre".');
    }
  }
}

/// Tipo de un evento de pago (`Apartado_Abonos.tipo`): el anticipo inicial,
/// un abono intermedio, o el abono que deja el saldo en cero y dispara la
/// liquidación.
enum TipoAbonoApartado {
  anticipo,
  abono,
  liquidacion;

  String get nombreDb {
    switch (this) {
      case TipoAbonoApartado.anticipo:
        return 'Anticipo';
      case TipoAbonoApartado.abono:
        return 'Abono';
      case TipoAbonoApartado.liquidacion:
        return 'Liquidacion';
    }
  }
}

/// Cabecera de un apartado: snapshot inmutable de subtotal/descuento/total
/// (mismo criterio que `Ventas`) tomado al crearlo. Nunca se recalcula
/// cuando el cliente regresa a abonar o liquidar semanas después.
class Apartado {
  final int? idApartado;
  final int idCliente;
  final int? idUsuario;
  final DateTime fechaCreacion;
  final DateTime? fechaLimite;
  final EstadoApartado estado;
  final double subtotal;
  final double descuentoTotal;
  final TipoDescuento? descuentoGlobalTipo;
  final double descuentoGlobalValor;
  final String? descuentoMotivo;
  final int? descuentoAutorizadoPor;
  final double total;
  final int? idVenta;
  final String? observaciones;

  const Apartado({
    this.idApartado,
    required this.idCliente,
    this.idUsuario,
    required this.fechaCreacion,
    this.fechaLimite,
    this.estado = EstadoApartado.pendiente,
    this.subtotal = 0,
    this.descuentoTotal = 0,
    this.descuentoGlobalTipo,
    this.descuentoGlobalValor = 0,
    this.descuentoMotivo,
    this.descuentoAutorizadoPor,
    this.total = 0,
    this.idVenta,
    this.observaciones,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id_cliente': idCliente,
      'id_usuario': idUsuario,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_limite': fechaLimite?.toIso8601String(),
      'estado': estado.nombreDb,
      'subtotal': subtotal,
      'descuento_total': descuentoTotal,
      'descuento_global_tipo': descuentoGlobalTipo?.nombre,
      'descuento_global_valor': descuentoGlobalValor,
      'descuento_motivo': descuentoMotivo,
      'descuento_autorizado_por': descuentoAutorizadoPor,
      'total': total,
      'id_venta': idVenta,
      'observaciones': observaciones,
    };

    if (idApartado != null) {
      map['id_apartado'] = idApartado;
    }

    return map;
  }

  factory Apartado.fromMap(Map<String, dynamic> map) {
    return Apartado(
      idApartado: map['id_apartado'] as int?,
      idCliente: map['id_cliente'] as int,
      idUsuario: map['id_usuario'] as int?,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaLimite: map['fecha_limite'] != null ? DateTime.parse(map['fecha_limite'] as String) : null,
      estado: EstadoApartado.desdeNombreDb(map['estado'] as String),
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      descuentoTotal: (map['descuento_total'] as num?)?.toDouble() ?? 0,
      descuentoGlobalTipo: TipoDescuento.desdeNombre(map['descuento_global_tipo'] as String?),
      descuentoGlobalValor: (map['descuento_global_valor'] as num?)?.toDouble() ?? 0,
      descuentoMotivo: map['descuento_motivo'] as String?,
      descuentoAutorizadoPor: map['descuento_autorizado_por'] as int?,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      idVenta: map['id_venta'] as int?,
      observaciones: map['observaciones'] as String?,
    );
  }
}
