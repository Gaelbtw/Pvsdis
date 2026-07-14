class Compras {
  String id;
  String producto;
  int cantidad;
  double precio;

  Compras({
    required this.id,
    required this.producto,
    required this.cantidad,
    required this.precio,
  });

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "producto": producto,
      "cantidad": cantidad,
      "precio": precio,
    };
  }

  factory Compras.fromMap(Map<String, dynamic> map) {
    return Compras(
      id: map["id"],
      producto: map["producto"],
      cantidad: map["cantidad"],
      precio: map["precio"],
    );
  }
}