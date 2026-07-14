class Cliente {
  final int? idCliente;
  final String nombre;
  final String? direccion;
  final int? telefono;
  final String? correo;
  final String fechaRegistro;

  Cliente({
    required this.idCliente,
    required this.nombre,
    required this.direccion,
    required this.telefono,
    required this.correo,
    required this.fechaRegistro
  });

  Map<String, dynamic> toMap() {
    return {
      "id_cliente": idCliente,
      "nombre": nombre,
      "direccion": direccion,
      "telefono": telefono,
      "correo": correo,
      "fecha_registro": fechaRegistro
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      idCliente: map["id_cliente"],
      nombre: map["nombre"],
      direccion: map["direccion"],
      telefono: int.tryParse(map["telefono"].toString()) ?? 0,
      correo: map["correo"],
      fechaRegistro: map["fecha_registro"]
    );
  }

}