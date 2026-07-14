class Categoria {
  int? idCategoria; 
  String nombre;

  Categoria({
    this.idCategoria,
    required this.nombre,
  });

  Map<String, dynamic> toMap() {
    return {
      'id_categoria': idCategoria,
      'nombre': nombre,
    };
  }

  factory Categoria.fromMap(Map<String, dynamic> map) {
    return Categoria(
      idCategoria: map['id_categoria'],
      nombre: map['nombre'],
    );
  }
}