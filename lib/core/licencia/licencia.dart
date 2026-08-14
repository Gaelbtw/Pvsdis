import 'dart:convert';

/// Edición contratada. Es un campo de la licencia, no un binario distinto:
/// **un solo .exe para todos los clientes**, y la licencia habilita.
///
/// Hacer builds separados por edición duplicaría el trabajo de release, los
/// instaladores y las pruebas, y garantizaría que tarde o temprano alguien
/// reciba el .exe equivocado.
enum Edicion {
  basica('basica', 'Básica'),
  pro('pro', 'Pro'),
  multisucursal('multisucursal', 'Multisucursal');

  const Edicion(this.clave, this.nombre);

  final String clave;
  final String nombre;

  static Edicion? desdeClave(String? clave) {
    if (clave == null) return null;
    final limpia = clave.trim().toLowerCase();
    for (final e in Edicion.values) {
      if (e.clave == limpia) return e;
    }
    return null;
  }
}

/// Motivo por el que un archivo de licencia no se pudo aceptar.
class LicenciaInvalidaException implements Exception {
  const LicenciaInvalidaException(this.motivo);

  /// Redactado para mostrarse tal cual en pantalla. Quien lo lee es el dueño
  /// de una tienda, no un programador.
  final String motivo;

  @override
  String toString() => motivo;
}

/// Contenido de un archivo `.lic` ya verificado.
///
/// El archivo es `payloadBase64Url.firmaBase64Url`. El payload es JSON en
/// UTF-8; la firma es Ed25519 sobre **los bytes exactos del payload**, no
/// sobre el JSON reserializado — reserializar antes de verificar es el error
/// clásico que hace que una licencia válida se rechace porque cambió el orden
/// de las llaves o el formato de un número.
class Licencia {
  const Licencia({
    required this.negocio,
    required this.edicion,
    required this.cajas,
    required this.emitida,
    required this.expira,
    required this.huella,
  });

  /// Nombre del negocio, solo informativo (se muestra en Configuración para
  /// que quede claro a nombre de quién está la licencia).
  final String negocio;

  final Edicion edicion;

  /// Equipos autorizados. Hoy no se valida contra nada: la huella ata la
  /// licencia a UN equipo, así que dos cajas son dos licencias. Se guarda para
  /// que el dato exista el día que haya activación en línea y sí se pueda
  /// contar de verdad.
  final int cajas;

  final DateTime emitida;
  final DateTime expira;

  /// Código de instalación del equipo al que se emitió (`A3F2-9C1B-7E44`).
  final String huella;

  /// Formato de versión del payload. Se guarda para poder cambiar el esquema
  /// de la licencia sin invalidar las ya emitidas.
  static const versionFormato = 1;

  /// Parsea el JSON del payload. No verifica la firma: eso es responsabilidad
  /// de quien llama (`LicenciaService`), y separarlo permite probar el parseo
  /// sin criptografía.
  factory Licencia.desdeJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is int && version > versionFormato) {
      throw const LicenciaInvalidaException(
        'Esta licencia fue emitida para una versión más reciente de Pv '
        'Control. Actualiza el sistema para poder usarla.',
      );
    }

    final edicion = Edicion.desdeClave(json['edicion'] as String?);
    if (edicion == null) {
      throw LicenciaInvalidaException(
        'La licencia indica una edición que este sistema no reconoce '
        '("${json['edicion']}").',
      );
    }

    final emitida = DateTime.tryParse('${json['emitida']}');
    final expira = DateTime.tryParse('${json['expira']}');
    if (emitida == null || expira == null) {
      throw const LicenciaInvalidaException(
        'La licencia tiene fechas ilegibles.',
      );
    }

    final huella = (json['huella'] as String?)?.trim().toUpperCase() ?? '';
    if (huella.isEmpty) {
      throw const LicenciaInvalidaException(
        'La licencia no indica a qué equipo pertenece.',
      );
    }

    return Licencia(
      negocio: (json['negocio'] as String?)?.trim() ?? 'Sin nombre',
      edicion: edicion,
      cajas: (json['cajas'] as num?)?.toInt() ?? 1,
      emitida: emitida,
      expira: expira,
      huella: huella,
    );
  }

  /// Payload canónico: llaves en orden alfabético y fechas en `AAAA-MM-DD`.
  ///
  /// El orden fijo no lo necesita la verificación (que firma bytes crudos),
  /// pero sí hace que emitir dos veces la misma licencia produzca exactamente
  /// el mismo archivo. Eso vuelve reproducible el proceso y permite comparar
  /// dos `.lic` a simple vista cuando algo no cuadra.
  Map<String, dynamic> aJson() => {
        'cajas': cajas,
        'edicion': edicion.clave,
        'emitida': soloFecha(emitida),
        'expira': soloFecha(expira),
        'huella': huella,
        'negocio': negocio,
        'version': versionFormato,
      };

  static String soloFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Días que faltan para vencer. Negativo si ya venció.
  ///
  /// Se compara a nivel de DÍA y no de instante: una licencia que expira "el
  /// 12 de agosto" vale todo el 12 de agosto. Comparar contra `DateTime.now()`
  /// la mataría a las 00:00:01 de ese día, y explicarle eso a un cliente que
  /// pagó hasta el 12 es una llamada que nadie quiere.
  int diasParaVencer({DateTime? ahora}) {
    final hoy = _aMedianoche(ahora ?? DateTime.now());
    final fin = _aMedianoche(expira);
    return fin.difference(hoy).inDays;
  }

  bool estaVencida({DateTime? ahora}) => diasParaVencer(ahora: ahora) < 0;

  static DateTime _aMedianoche(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Serializa a la forma `payload.firma` que se guarda en el `.lic`. Solo lo
  /// usa el emisor; la app nunca escribe licencias.
  static String armarArchivo(List<int> payload, List<int> firma) =>
      '${base64Url.encode(payload)}.${base64Url.encode(firma)}';

  /// Separa un `.lic` en sus dos partes decodificadas.
  static ({List<int> payload, List<int> firma}) partirArchivo(
    String contenido,
  ) {
    // Se quitan saltos de línea y espacios: el archivo viaja por WhatsApp y
    // por correo, y ambos le meten saltos de línea a un texto largo. Rechazar
    // una licencia buena por un salto de línea sería una llamada de soporte
    // completamente evitable.
    final limpio = contenido.replaceAll(RegExp(r'\s'), '');
    final partes = limpio.split('.');
    if (partes.length != 2 || partes[0].isEmpty || partes[1].isEmpty) {
      throw const LicenciaInvalidaException(
        'El archivo de licencia no tiene el formato esperado. Revisa que sea '
        'el .lic completo y que no se haya cortado al copiarlo.',
      );
    }

    try {
      return (
        payload: base64Url.decode(base64Url.normalize(partes[0])),
        firma: base64Url.decode(base64Url.normalize(partes[1])),
      );
    } on FormatException {
      throw const LicenciaInvalidaException(
        'El archivo de licencia está dañado o incompleto.',
      );
    }
  }
}
