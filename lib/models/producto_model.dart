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
  final String? codigoBarras;

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
    this.codigoBarras,
  });

  /// Normaliza un código de barras ingresado por el usuario: recorta
  /// espacios y convierte cadenas vacías a `null`, para no guardar `""`
  /// como si fuera un valor real (evita falsos duplicados/columna sucia).
  static String? normalizarCodigoBarras(String? valor) {
    final limpio = valor?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'precio_compra': precioCompra,
      'id_categoria': categoriaId,
      'estado': estado,
      'stock_minimo': stockMinimo,
      'codigo_barras': normalizarCodigoBarras(codigoBarras),
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
      codigoBarras: map["codigo_barras"],
    );
  }
}