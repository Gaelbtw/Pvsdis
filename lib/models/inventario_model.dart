class Inventario {
  final int idInventario;
  final int idProducto;
  final int cantidad;

  Inventario({
    required this.idInventario,
    required this.idProducto,
    required this.cantidad
  });

  Map<String, dynamic> toMap() {
    return {
      "id_inventario": idInventario,
      "id_producto": idProducto,
      "cantidad": cantidad
    };
  }

  factory Inventario.fromMap(Map<String, dynamic> map) {
    return Inventario(
      idInventario: map["id_inventario"],
      idProducto: map["id_producto"],
      cantidad: map["cantidad"]
    );
  }
}
