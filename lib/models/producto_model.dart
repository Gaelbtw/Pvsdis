class Producto {
  final int? idProducto;
  final String nombre;
  final String descripcion;
  final double precio;
  final int stockMinimo;
  final String estado;
  final double? precioCompra;
  final int? categoriaId;
  final String? categoriaNombre;

  const Producto({
    this.idProducto,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    this.stockMinimo = 5,
    this.estado = "Activo",
    this.precioCompra,
    this.categoriaId,
    this.categoriaNombre,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'precio_compra': precioCompra,
      'id_categoria': categoriaId,
      'estado': estado,
      'stock_minimo': stockMinimo,
    };

    if (idProducto != null) {
      map['id_producto'] = idProducto;
    }

    return map;
  }

  factory Producto.fromMap(Map<String, dynamic> map) {
    return Producto(
      idProducto: map["id_producto"],
      nombre: map["nombre"],
      descripcion: map["descripcion"] ?? "",
      precio: map["precio"],
      //categoria: map["categoria"] ?? "",
      stockMinimo: map["stock_minimo"] ?? 5,
      estado: map["estado"] ?? "Activo",
      precioCompra: map["precio_compra"],
      categoriaId: map["id_categoria"],
      categoriaNombre: map["categoria_nombre"],
    );
  }
}