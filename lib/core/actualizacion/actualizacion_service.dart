import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/app_info.dart';
import '../database/database_helper.dart';
import 'version_app.dart';

/// Una versión publicada, según el manifiesto.
@immutable
class Actualizacion {
  const Actualizacion({
    required this.version,
    required this.url,
    required this.sha256,
    required this.notas,
    this.obligatoria = false,
    this.cambiaEsquema = false,
  });

  final VersionApp version;
  final String url;

  /// Hash esperado del instalador. Sin esto, "descargar automáticamente" sería
  /// ejecutar en la caja del cliente lo que sea que devuelva la red.
  final String sha256;

  /// En español de negocio: "Ahora el corte X muestra las devoluciones del
  /// turno", no "fix: cast en corte_x_service".
  final String notas;

  final bool obligatoria;

  /// La actualización sube MAYOR o MENOR, así que por la regla del proyecto
  /// toca la base de datos. Cambia el texto del aviso: conviene que el cliente
  /// respalde antes.
  final bool cambiaEsquema;
}

/// Avisa cuando hay una versión nueva publicada.
///
/// # Lo que NO hace, y por qué
///
/// No instala nada solo. Descarga, comprueba el hash y abre la carpeta con el
/// archivo; correrlo es una decisión del negocio.
///
/// **Regla número uno de un punto de venta: una actualización nunca se aplica
/// sola a media venta.** Si le tumbas la caja a una tienda un sábado, perdiste
/// al cliente — y el ahorro de un clic no compensa ni de lejos ese riesgo. Por
/// eso tampoco hay modal: un aviso discreto que se puede ignorar hasta el
/// cierre es exactamente el comportamiento correcto.
class ActualizacionService {
  ActualizacionService._();

  static final ActualizacionService instancia = ActualizacionService._();

  /// URL de un JSON estático (Drive, R2, GitHub Releases: da igual, mientras
  /// sea una URL fija).
  ///
  /// ```json
  /// {
  ///   "version": "1.2.0",
  ///   "url": "https://.../PvControl-Setup-1.2.0.exe",
  ///   "sha256": "…",
  ///   "obligatoria": false,
  ///   "notas": "El corte X ahora incluye las devoluciones del turno."
  /// }
  /// ```
  ///
  /// **Vacía = revisión apagada**, que es el estado hasta que exista un lugar
  /// donde publicar. Igual que la clave pública de licencias: el código está
  /// listo, encenderlo es poner un valor aquí.
  static const urlManifiesto = '';

  static bool get activo => urlManifiesto.trim().isNotEmpty;

  /// Resultado de la última revisión, para que el aviso se redibuje solo.
  final ValueNotifier<Actualizacion?> disponible = ValueNotifier(null);

  /// Consulta el manifiesto. **Nunca lanza**: sin internet, con el servidor
  /// caído o con un JSON mal formado, simplemente no hay aviso. Que falle la
  /// revisión de actualizaciones no puede estorbarle a un negocio que necesita
  /// abrir la caja.
  Future<Actualizacion?> buscar() async {
    if (!activo) return null;

    try {
      final respuesta = await http
          .get(Uri.parse(urlManifiesto))
          .timeout(const Duration(seconds: 8));

      if (respuesta.statusCode != 200) return null;

      final manifiesto = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (manifiesto is! Map<String, dynamic>) return null;

      disponible.value = decidir(
        versionInstalada: AppInfo.version,
        manifiesto: manifiesto,
      );
      return disponible.value;
    } catch (e) {
      debugPrint('Actualización: no se pudo consultar ($e).');
      return null;
    }
  }

  /// Decide si el manifiesto describe algo más nuevo que lo instalado.
  ///
  /// Pura y estática para poder probarla sin red: es donde vive el error caro
  /// —comparar versiones como texto— y donde una equivocación se traduce en
  /// avisarle a un cliente que "actualice" a una versión más vieja.
  static Actualizacion? decidir({
    required String versionInstalada,
    required Map<String, dynamic> manifiesto,
  }) {
    final actual = VersionApp.parsear(versionInstalada);
    final publicada = VersionApp.parsear(manifiesto['version'] as String?);

    // Sin poder leer alguna de las dos, no se avisa. Un manifiesto ilegible
    // debe ser silencio, no una alarma que nadie sabe interpretar.
    if (actual == null || publicada == null) return null;
    if (!publicada.esMasNuevaQue(actual)) return null;

    final url = (manifiesto['url'] as String?)?.trim() ?? '';
    final sha = (manifiesto['sha256'] as String?)?.trim().toLowerCase() ?? '';
    if (url.isEmpty || sha.length != 64) return null;

    return Actualizacion(
      version: publicada,
      url: url,
      sha256: sha,
      notas: (manifiesto['notas'] as String?)?.trim() ?? '',
      obligatoria: manifiesto['obligatoria'] == true,
      cambiaEsquema: publicada.cambiaEsquemaRespectoA(actual),
    );
  }

  /// Descarga el instalador y **comprueba su SHA256** antes de dárselo a
  /// nadie. Devuelve la ruta del archivo verificado.
  ///
  /// Si el hash no coincide, el archivo se borra y se lanza: entregar un
  /// instalador que no es el publicado sería peor que no actualizar. El caso
  /// común no es un ataque, es una descarga cortada a media conexión mala —
  /// que es justo el tipo de internet que tienen los negocios a los que sirve
  /// este producto.
  Future<String> descargar(Actualizacion actualizacion) async {
    final carpeta = Directory(
      p.join(
        p.dirname(await DatabaseHelper().getDatabasePath()),
        'actualizaciones',
      ),
    );
    if (!await carpeta.exists()) await carpeta.create(recursive: true);

    final destino = File(
      p.join(carpeta.path, 'PvControl-Setup-${actualizacion.version}.exe'),
    );

    final respuesta = await http
        .get(Uri.parse(actualizacion.url))
        .timeout(const Duration(minutes: 10));

    if (respuesta.statusCode != 200) {
      throw Exception(
        'No se pudo descargar la actualización (código ${respuesta.statusCode}). '
        'Revisa tu conexión e inténtalo más tarde.',
      );
    }

    final hashRecibido = sha256.convert(respuesta.bodyBytes).toString();
    if (hashRecibido != actualizacion.sha256) {
      throw Exception(
        'El archivo descargado no coincide con el publicado. Probablemente la '
        'descarga se cortó. Vuelve a intentarlo; si sigue fallando, avisa a '
        'soporte y no ejecutes el archivo.',
      );
    }

    await destino.writeAsBytes(respuesta.bodyBytes);
    return destino.path;
  }
}
