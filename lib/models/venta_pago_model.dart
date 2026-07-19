class VentaPago {
  final int? id;
  final int? idVenta;
  final String metodoPago;
  final double monto;

  const VentaPago({
    this.id,
    required this.idVenta,
    required this.metodoPago,
    required this.monto,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_venta": idVenta,
      "metodo_pago": metodoPago,
      "monto": monto,
    };
  }

  factory VentaPago.fromMap(Map<String, dynamic> map) {
    return VentaPago(
      id: map["id"] as int?,
      idVenta: map["id_venta"] as int?,
      metodoPago: map["metodo_pago"]?.toString() ?? '',
      monto: (map["monto"] as num?)?.toDouble() ?? 0,
    );
  }
}
