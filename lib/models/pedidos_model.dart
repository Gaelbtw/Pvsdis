class Pedidos {
  final int? idPedido;
  final int idCliente;
  final String fecha;
  final String fechaEntrega;
  final String tipoEntrega;
  final String estado;
  final double total;
  final String? direccion;

  Pedidos({
    this.idPedido,
    required this.idCliente,
    required this.fecha,
    required this.fechaEntrega,
    required this.tipoEntrega,
    required this.total,
    required this.estado,
    this.direccion,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_pedido": idPedido,
      "id_cliente": idCliente,
      "fecha": fecha,
      "fecha_entrega": fechaEntrega,
      "tipo_entrega": tipoEntrega,
      "total": total,
      "estado": estado,
      "direccion": direccion,
    };
  }

  factory Pedidos.fromMap(Map<String, dynamic> map) {
    return Pedidos(
      idPedido: map["id_pedido"],
      idCliente: map["id_cliente"],
      fecha: map["fecha"],
      fechaEntrega: map["fecha_entrega"],
      tipoEntrega: map["tipo_entrega"],
      total: map["total"],
      estado: map["estado"],
      direccion: map["direccion"],
    );
  }
}
