class Reporte {
  final int idReporte;
  final String tipo;
  final String descripcion;
  final String fecha;
  final int idUsuario;

  Reporte({
    required this.idReporte,
    required this.tipo,
    required this.descripcion,
    required this.fecha,
    required this.idUsuario
  });

  Map<String, dynamic> toMap() {
    return {
      "id_reporte": idReporte,
      "tipo": tipo,
      "descripcion": descripcion,
      "fecha": fecha,
      "id_usuario": idUsuario
    };
  }

  factory Reporte.fromMap(Map<String, dynamic> map) {
    return Reporte(
      idReporte: map["id_reporte"],
      tipo: map["tipo"],
      descripcion: map["descripcion"],
      fecha: map["fecha"],
      idUsuario: map["id_usuario"]
    );
  }
}