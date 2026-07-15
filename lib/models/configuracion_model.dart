class Configuracion {
  // Operación (turnos, caja, inventario)
  final String horaInicioMatutino;
  final String horaFinMatutino;
  final String horaInicioVespertino;
  final String horaFinVespertino;
  final int stockMinimo;
  final double fondoCaja;

  // Identidad del negocio: esto es lo único que debe variar entre clientes.
  final String nombreNegocio;
  final String? logoPath;
  final String? direccion;
  final String? telefono;
  final String? correo;
  final String? rfc;
  final String simboloMoneda;
  final double tasaImpuestoPorcentaje;
  final String mensajeTicket;
  final int colorPrimario;

  // Descuentos: ver DevolucionesController/VentasController y
  // core/utils/descuento_utils.dart para cómo se usan.
  final double descuentoMaximoPorcentaje;
  final bool descuentoCajeroPuedeAplicar;
  final bool descuentoCajeroRequiereAutorizacion;

  Configuracion({
    required this.horaInicioMatutino,
    required this.horaFinMatutino,
    required this.horaInicioVespertino,
    required this.horaFinVespertino,
    required this.stockMinimo,
    required this.fondoCaja,
    required this.nombreNegocio,
    this.logoPath,
    this.direccion,
    this.telefono,
    this.correo,
    this.rfc,
    required this.simboloMoneda,
    required this.tasaImpuestoPorcentaje,
    required this.mensajeTicket,
    required this.colorPrimario,
    this.descuentoMaximoPorcentaje = 20,
    this.descuentoCajeroPuedeAplicar = true,
    this.descuentoCajeroRequiereAutorizacion = true,
  });

  /// Valores de fábrica para una instalación nueva: sin ningún dato de un
  /// negocio en particular. El nombre genérico "Mi Negocio" se reemplaza
  /// la primera vez que el cliente guarda su configuración.
  factory Configuracion.porDefecto() {
    return Configuracion(
      horaInicioMatutino: "07:00",
      horaFinMatutino: "14:00",
      horaInicioVespertino: "14:00",
      horaFinVespertino: "21:00",
      stockMinimo: 5,
      fondoCaja: 500,
      nombreNegocio: "Mi Negocio",
      logoPath: null,
      direccion: null,
      telefono: null,
      correo: null,
      rfc: null,
      simboloMoneda: r"$",
      tasaImpuestoPorcentaje: 0,
      mensajeTicket: "¡Gracias por su compra!",
      colorPrimario: 0xFFF2C500,
      descuentoMaximoPorcentaje: 20,
      descuentoCajeroPuedeAplicar: true,
      descuentoCajeroRequiereAutorizacion: true,
    );
  }

  factory Configuracion.fromMap(Map<String, dynamic> map) {
    final base = Configuracion.porDefecto();

    return Configuracion(
      horaInicioMatutino:
          map['hora_inicio_matutino'] as String? ?? base.horaInicioMatutino,
      horaFinMatutino: map['hora_fin_matutino'] as String? ?? base.horaFinMatutino,
      horaInicioVespertino:
          map['hora_inicio_vespertino'] as String? ?? base.horaInicioVespertino,
      horaFinVespertino:
          map['hora_fin_vespertino'] as String? ?? base.horaFinVespertino,
      stockMinimo: (map['stock_minimo'] as num?)?.toInt() ?? base.stockMinimo,
      fondoCaja: (map['fondo_caja'] as num?)?.toDouble() ?? base.fondoCaja,
      nombreNegocio: map['nombre_negocio'] as String? ?? base.nombreNegocio,
      logoPath: map['logo_path'] as String?,
      direccion: map['direccion'] as String?,
      telefono: map['telefono'] as String?,
      correo: map['correo'] as String?,
      rfc: map['rfc'] as String?,
      simboloMoneda: map['simbolo_moneda'] as String? ?? base.simboloMoneda,
      tasaImpuestoPorcentaje:
          (map['tasa_impuesto'] as num?)?.toDouble() ?? base.tasaImpuestoPorcentaje,
      mensajeTicket: map['mensaje_ticket'] as String? ?? base.mensajeTicket,
      colorPrimario: (map['color_primario'] as num?)?.toInt() ?? base.colorPrimario,
      descuentoMaximoPorcentaje: (map['descuento_maximo_porcentaje'] as num?)?.toDouble() ??
          base.descuentoMaximoPorcentaje,
      descuentoCajeroPuedeAplicar: map['descuento_cajero_puede_aplicar'] == null
          ? base.descuentoCajeroPuedeAplicar
          : (map['descuento_cajero_puede_aplicar'] as num) != 0,
      descuentoCajeroRequiereAutorizacion: map['descuento_cajero_requiere_autorizacion'] == null
          ? base.descuentoCajeroRequiereAutorizacion
          : (map['descuento_cajero_requiere_autorizacion'] as num) != 0,
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
      'nombre_negocio': nombreNegocio,
      'logo_path': logoPath,
      'direccion': direccion,
      'telefono': telefono,
      'correo': correo,
      'rfc': rfc,
      'simbolo_moneda': simboloMoneda,
      'tasa_impuesto': tasaImpuestoPorcentaje,
      'mensaje_ticket': mensajeTicket,
      'color_primario': colorPrimario,
      'descuento_maximo_porcentaje': descuentoMaximoPorcentaje,
      'descuento_cajero_puede_aplicar': descuentoCajeroPuedeAplicar ? 1 : 0,
      'descuento_cajero_requiere_autorizacion': descuentoCajeroRequiereAutorizacion ? 1 : 0,
    };
  }

  Configuracion copyWith({
    String? horaInicioMatutino,
    String? horaFinMatutino,
    String? horaInicioVespertino,
    String? horaFinVespertino,
    int? stockMinimo,
    double? fondoCaja,
    String? nombreNegocio,
    String? logoPath,
    String? direccion,
    String? telefono,
    String? correo,
    String? rfc,
    String? simboloMoneda,
    double? tasaImpuestoPorcentaje,
    String? mensajeTicket,
    int? colorPrimario,
    double? descuentoMaximoPorcentaje,
    bool? descuentoCajeroPuedeAplicar,
    bool? descuentoCajeroRequiereAutorizacion,
  }) {
    return Configuracion(
      horaInicioMatutino: horaInicioMatutino ?? this.horaInicioMatutino,
      horaFinMatutino: horaFinMatutino ?? this.horaFinMatutino,
      horaInicioVespertino: horaInicioVespertino ?? this.horaInicioVespertino,
      horaFinVespertino: horaFinVespertino ?? this.horaFinVespertino,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      fondoCaja: fondoCaja ?? this.fondoCaja,
      nombreNegocio: nombreNegocio ?? this.nombreNegocio,
      logoPath: logoPath ?? this.logoPath,
      direccion: direccion ?? this.direccion,
      telefono: telefono ?? this.telefono,
      correo: correo ?? this.correo,
      rfc: rfc ?? this.rfc,
      simboloMoneda: simboloMoneda ?? this.simboloMoneda,
      tasaImpuestoPorcentaje: tasaImpuestoPorcentaje ?? this.tasaImpuestoPorcentaje,
      mensajeTicket: mensajeTicket ?? this.mensajeTicket,
      colorPrimario: colorPrimario ?? this.colorPrimario,
      descuentoMaximoPorcentaje: descuentoMaximoPorcentaje ?? this.descuentoMaximoPorcentaje,
      descuentoCajeroPuedeAplicar: descuentoCajeroPuedeAplicar ?? this.descuentoCajeroPuedeAplicar,
      descuentoCajeroRequiereAutorizacion:
          descuentoCajeroRequiereAutorizacion ?? this.descuentoCajeroRequiereAutorizacion,
    );
  }
}
