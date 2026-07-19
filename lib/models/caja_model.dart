class Caja {
  final int? idCaja;
  final int idUsuario;
  final String fechaApertura;
  final String? fechaCierre;
  final double fondoInicial;
  final String? observacionesApertura;
  final double? ventasEfectivo;
  final double? ventasTarjeta;
  final double? ventasTransferencia;
  final double? cambioEntregado;
  final double? devoluciones;
  final double? efectivoEsperado;
  final double? efectivoContado;
  final double? diferencia;
  final String? observacionesCierre;
  final String estado;

  const Caja({
    this.idCaja,
    required this.idUsuario,
    required this.fechaApertura,
    this.fechaCierre,
    required this.fondoInicial,
    this.observacionesApertura,
    this.ventasEfectivo,
    this.ventasTarjeta,
    this.ventasTransferencia,
    this.cambioEntregado,
    this.devoluciones,
    this.efectivoEsperado,
    this.efectivoContado,
    this.diferencia,
    this.observacionesCierre,
    this.estado = 'Abierta',
  });

  bool get estaAbierta => estado == 'Abierta';

  Map<String, dynamic> toMap() {
    return {
      "id_usuario": idUsuario,
      "fecha_apertura": fechaApertura,
      "fecha_cierre": fechaCierre,
      "fondo_inicial": fondoInicial,
      "observaciones_apertura": observacionesApertura,
      "ventas_efectivo": ventasEfectivo,
      "ventas_tarjeta": ventasTarjeta,
      "ventas_transferencia": ventasTransferencia,
      "cambio_entregado": cambioEntregado,
      "devoluciones": devoluciones,
      "efectivo_esperado": efectivoEsperado,
      "efectivo_contado": efectivoContado,
      "diferencia": diferencia,
      "observaciones_cierre": observacionesCierre,
      "estado": estado,
    };
  }

  factory Caja.fromMap(Map<String, dynamic> map) {
    double? asDoubleOrNull(dynamic v) => (v as num?)?.toDouble();

    return Caja(
      idCaja: map["id_caja"] as int?,
      idUsuario: map["id_usuario"] as int,
      fechaApertura: map["fecha_apertura"]?.toString() ?? '',
      fechaCierre: map["fecha_cierre"]?.toString(),
      fondoInicial: (map["fondo_inicial"] as num?)?.toDouble() ?? 0,
      observacionesApertura: map["observaciones_apertura"]?.toString(),
      ventasEfectivo: asDoubleOrNull(map["ventas_efectivo"]),
      ventasTarjeta: asDoubleOrNull(map["ventas_tarjeta"]),
      ventasTransferencia: asDoubleOrNull(map["ventas_transferencia"]),
      cambioEntregado: asDoubleOrNull(map["cambio_entregado"]),
      devoluciones: asDoubleOrNull(map["devoluciones"]),
      efectivoEsperado: asDoubleOrNull(map["efectivo_esperado"]),
      efectivoContado: asDoubleOrNull(map["efectivo_contado"]),
      diferencia: asDoubleOrNull(map["diferencia"]),
      observacionesCierre: map["observaciones_cierre"]?.toString(),
      estado: map["estado"]?.toString() ?? 'Abierta',
    );
  }
}
