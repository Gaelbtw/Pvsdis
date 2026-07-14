class Configuracion {
  final String horaInicioMatutino;
  final String horaFinMatutino;
  final String horaInicioVespertino;
  final String horaFinVespertino;
  final int stockMinimo;
  final double fondoCaja;

  Configuracion({
    required this.horaInicioMatutino,
    required this.horaFinMatutino,
    required this.horaInicioVespertino,
    required this.horaFinVespertino,
    required this.stockMinimo,
    required this.fondoCaja,
  });

  factory Configuracion.fromMap(Map<String, dynamic> map) {
    return Configuracion(
      horaInicioMatutino: map['hora_inicio_matutino'] as String,
      horaFinMatutino: map['hora_fin_matutino'] as String,
      horaInicioVespertino: map['hora_inicio_vespertino'] as String,
      horaFinVespertino: map['hora_fin_vespertino'] as String,
      stockMinimo: map['stock_minimo'] as int,
      fondoCaja: (map['fondo_caja'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hora_inicio_matutino': horaInicioMatutino,
      'hora_fin_matutino': horaFinMatutino,
      'hora_inicio_vespertino': horaInicioVespertino,
      'hora_fin_vespertino': horaFinVespertino,
      'stock_minimo': stockMinimo,
      'fondo_caja': fondoCaja,
    };
  }
}
