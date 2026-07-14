class Proveedores {
  final int? idProveedor;
  final String nombre;
  final String rfc;
  final String direccion;
  final String direccionFiscal;
  final String telefono;

  Proveedores({
    required this.idProveedor,
    required this.nombre,
    required this.rfc,
    required this.direccion,
    required this.direccionFiscal,
    required this.telefono,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_proveedor": idProveedor,
      "nombre": nombre,
      "rfc": rfc,
      "direccion": direccion,
      "direccion_fiscal": direccionFiscal,
      "telefono": telefono,
    };
  }

  factory Proveedores.fromMap(Map<String, dynamic> map) {
    return Proveedores(
      idProveedor: map["id_proveedor"],
      nombre: map["nombre"] ?? "",
      rfc: map["rfc"] ?? "",
      direccion: map["direccion"] ?? "",
      direccionFiscal: map["direccion_fiscal"] ?? "",
      telefono: map["telefono"] ?? "",
    );
  }
}