class Auditoria {
  final int? idAuditoria;
  final String fechaHora;
  final String usuario;
  final String tabla;
  final String accion;
  final int? idRegistro;
  final String descripcion;
  final int? idUsuario;
  final int? idCaja;

  Auditoria({
    required this.idAuditoria,
    required this.fechaHora,
    required this.usuario,
    required this.tabla,
    required this.accion,
    required this.idRegistro,
    required this.descripcion,
    this.idUsuario,
    this.idCaja,
  });

  Map<String, dynamic> toMap() {
    return {
      "id_auditoria": idAuditoria,
      "fecha_hora": fechaHora,
      "usuario": usuario,
      "tabla": tabla,
      "accion": accion,
      "id_registro": idRegistro,
      "descripcion": descripcion,
      "id_usuario": idUsuario,
      "id_caja": idCaja,
    };
  }

  factory Auditoria.fromMap(Map<String, dynamic> map) {
    return Auditoria(
      idAuditoria: map["id_auditoria"],
      fechaHora: map["fecha_hora"],
      usuario: map["usuario"] ?? "",
      tabla: map["tabla"] ?? "",
      accion: map["accion"] ?? "",
      idRegistro: map["id_registro"],
      descripcion: map["descripcion"] ?? "",
      idUsuario: map["id_usuario"],
      idCaja: map["id_caja"],
    );
  }
}
