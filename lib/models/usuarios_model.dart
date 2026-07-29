class Usuarios {
  int? idUsuario;
  String nombre;
  String contra;
  String rol;

  /// PIN numérico opcional para el login rápido. En memoria puede traer el
  /// PIN en texto plano (al construirlo desde un formulario) o el hash bcrypt
  /// (al leerlo de BD con [fromMap]). No se serializa en [toMap]: el hashing y
  /// la escritura del PIN los gestiona `UsuariosController` aparte, igual que
  /// la contraseña.
  String? pin;

  Usuarios({
    required this.idUsuario,
    required this.nombre,
    required this.contra,
    required this.rol,
    this.pin,
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
      pin: map["pin"] as String?,
    );
  }
}
