class Cliente {
  final int? idCliente;
  final String nombre;
  final String? direccion;

  /// Texto libre, no un número.
  ///
  /// Era `int?`, con la columna `Clientes.telefono` en INTEGER. Eso perdía el
  /// cero inicial ('0551234567' se guardaba como 551234567) y no admitía
  /// ningún formato que la gente teclee de verdad: '+52 55 1234 5678',
  /// '55-1234-5678' o una extensión. Además `fromMap` hacía
  /// `int.tryParse(...) ?? 0`, así que un cliente sin teléfono aparecía con
  /// un "0" en pantalla en vez de vacío.
  final String? telefono;

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
      // Se normaliza a `null` si viene vacío, para que la UI muestre "-" y no
      // una cadena en blanco. `toString()` cubre las filas viejas que quedaron
      // guardadas como número antes de la migración v22.
      telefono: switch (map["telefono"]) {
        null => null,
        final v => v.toString().trim().isEmpty ? null : v.toString().trim(),
      },
      correo: map["correo"],
      fechaRegistro: map["fecha_registro"]
    );
  }

}