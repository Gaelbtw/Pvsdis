class Ventas {
  final int? idVenta;
  final int? idCliente;
  final int idUsuario;
  final String fecha;
  final double total;
  final String metodoPago;

  Ventas({
    required this.idVenta,
    required this.idCliente,
    required this.idUsuario,
    required this.fecha,
    required this.total,
    this.metodoPago = 'efectivo',
  });

  Map<String, dynamic> toMap() {
    return {
      "id_venta": idVenta,
      "id_cliente": idCliente,
      "id_usuario": idUsuario,
      "fecha": fecha,
      "total": total,
      "metodo_pago": metodoPago,
    };
  }

  factory Ventas.fromMap(Map<String, dynamic> map) {
    return Ventas(
      idVenta: map["id_venta"],
      idCliente: map["id_cliente"],
      idUsuario: map["id_usuario"],
      fecha: map["fecha"],
      total: (map["total"] as num).toDouble(),
      metodoPago: map["metodo_pago"] ?? 'efectivo',
    );
  }
}
