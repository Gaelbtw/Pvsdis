class DetalleCompra {
  final int idDetalleCompra;
  final int idCompra;
  final int idProducto;
  final int cantidad;
  final double precio;

  DetalleCompra({
    required this.idDetalleCompra,
    required this.idCompra,
    required this.idProducto,
    required this.cantidad,
    required this.precio,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_detalle": idDetalleCompra,
      "id_compra": idCompra,
      "id_producto": idProducto,
      "cantidad": cantidad,
      "precio": precio,
    };
  }

  factory DetalleCompra.fromMap(Map<String, dynamic> map) {
    return DetalleCompra(
      idDetalleCompra: map["id_detalle"],
      idCompra: map["id_compra"],
      idProducto: map["id_producto"],
      cantidad: map["cantidad"] ?? 1,
      precio: (map["precio"] as num).toDouble(),
    );
  }
}