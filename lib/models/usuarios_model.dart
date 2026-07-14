class Usuarios {
  int? idUsuario;
  String nombre;
  String contra;
  String rol;

  Usuarios({
    required this.idUsuario,
    required this.nombre,
    required this.contra,
    required this.rol,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_usuario": idUsuario,
      "nombre": nombre,
      "contra": contra,
      "rol": rol,
    };
  }

  factory Usuarios.fromMap(Map<String, dynamic> map) {
    return Usuarios(
      idUsuario: map["id_usuario"],
      nombre: map["nombre"],
      contra: map["contra"],
      rol: map["rol"],
    );
  }
}

