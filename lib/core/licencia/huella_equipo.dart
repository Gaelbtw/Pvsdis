import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Identifica el equipo donde corre la app, de forma **tolerante a que cambie
/// una pieza**.
///
/// El error clásico del licenciamiento de escritorio es atar la licencia al
/// número de serie del disco: el cliente cambia a SSD y te habla furioso un
/// domingo, con el negocio parado. Aquí se usan tres señales independientes y
/// **basta con que coincidan dos**:
///
/// | Señal | Sobrevive a | Cambia con |
/// |---|---|---|
/// | `MachineGuid` del registro | cambio de disco, cambio de nombre | reinstalar Windows |
/// | UUID del equipo (BIOS/SMBIOS) | formateo, cambio de disco | cambio de tarjeta madre |
/// | Nombre del equipo | casi todo | que alguien lo renombre |
///
/// Cambiar el disco no toca ninguna. Reinstalar Windows tumba `MachineGuid` y
/// probablemente el nombre, pero deja el UUID — ahí sí toca reactivar, y es
/// razonable. Cambiar la tarjeta madre es, para efectos prácticos, otra
/// computadora.
///
/// **Esto no es una barrera de seguridad.** Quien quiera falsificar la huella
/// puede hacerlo; lo que impide emitir licencias falsas es la firma Ed25519.
/// El objetivo aquí es evitar la copia casual ("pásame el instalador para mi
/// otra tienda"), no detener a alguien decidido.
class HuellaEquipo {
  HuellaEquipo._();

  /// Alfabeto sin caracteres que se confunden al dictarlos por teléfono: sin
  /// I, L, O, U, 0 ni 1. Alguien va a leer este código en voz alta por
  /// WhatsApp, y "cero o ele" cuesta más soporte del que ahorra la entropía.
  static const _alfabeto = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';

  /// Marca de una señal que no se pudo leer. Nunca cuenta como coincidencia:
  /// si dos equipos fallan en leer la misma señal, no por eso son el mismo
  /// equipo.
  ///
  /// **No puede contener `-`**, que es lo que separa los grupos. Un marcador
  /// como `----` hacía que `codigoDesde` produjera `-----ABCD-EFGH` y que
  /// `split('-')` devolviera siete pedazos vacíos en vez de tres grupos: la
  /// comparación posicional se desalineaba entera y dos equipos distintos
  /// podían dar por buena la licencia del otro.
  static const grupoDesconocido = '????';

  /// Cuántas de las tres señales deben coincidir para aceptar la licencia.
  static const coincidenciasMinimas = 2;

  /// Lee las tres señales del equipo actual, en orden fijo. Una señal que no
  /// se pueda leer vuelve como cadena vacía; nunca lanza.
  static Future<List<String>> senales() async {
    if (!Platform.isWindows) {
      // En pruebas y en cualquier otra plataforma solo hay una señal real.
      // Las otras dos quedan vacías, lo que hace imposible llegar a dos
      // coincidencias: fuera de Windows la licencia no ata a un equipo.
      return ['', '', _hostname()];
    }
    return [await _machineGuid(), await _uuidEquipo(), _hostname()];
  }

  /// Código de instalación que el cliente dicta o pega en WhatsApp, del estilo
  /// `A3F2-9C1B-7E44`.
  ///
  /// Cada grupo es el hash de UNA señal, en posición fija. Eso es lo que
  /// permite la tolerancia 2-de-3 sin necesidad de que el cliente mande un
  /// archivo: el código lleva las tres huellas por separado, no una sola
  /// combinada.
  static String codigoDesde(List<String> senales) =>
      senales.map(_grupo).join('-');

  static Future<String> codigoActual() async => codigoDesde(await senales());

  /// Cuántos grupos coinciden entre dos códigos, comparando **por posición**.
  ///
  /// Comparar por posición y no por contenido importa: si se compararan como
  /// conjuntos, un equipo cuyo nombre coincidiera por casualidad con el
  /// `MachineGuid` de otro sumaría un punto que no significa nada.
  static int coincidencias(String codigoA, String codigoB) {
    final a = codigoA.trim().toUpperCase().split('-');
    final b = codigoB.trim().toUpperCase().split('-');
    if (a.length != b.length) return 0;

    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] == grupoDesconocido || b[i] == grupoDesconocido) continue;
      if (a[i].isNotEmpty && a[i] == b[i]) n++;
    }
    return n;
  }

  /// `true` si [codigoLicencia] describe a este mismo equipo.
  static bool esMismoEquipo(String codigoLicencia, String codigoActual) =>
      coincidencias(codigoLicencia, codigoActual) >= coincidenciasMinimas;

  // ------------------------------------------------------------- internos

  /// 4 caracteres del hash de una señal. Son ~20 bits: no es un identificador
  /// único a nivel mundial y no pretende serlo. Lo que impide falsificar una
  /// licencia es la firma, no la longitud de esto; el código solo tiene que
  /// ser cómodo de dictar por teléfono y distinguir entre los equipos de un
  /// puñado de clientes.
  static String _grupo(String senal) {
    final limpia = senal.trim().toLowerCase();
    if (limpia.isEmpty) return grupoDesconocido;

    final digest = sha256.convert(utf8.encode(limpia)).bytes;
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buffer.write(_alfabeto[digest[i] % _alfabeto.length]);
    }
    return buffer.toString();
  }

  /// `MachineGuid`: lo genera Windows al instalarse y no cambia por cambiar
  /// hardware. Se lee con `reg query` y no con un paquete de registro para no
  /// sumar una dependencia nativa por un solo valor.
  static Future<String> _machineGuid() async {
    try {
      final r = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
        '/reg:64',
      ]);
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
          .firstMatch(r.stdout.toString());
      return m?.group(1)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// UUID del equipo según SMBIOS. Sobrevive a formatear y a cambiar el disco,
  /// que es justo el caso que rompe los esquemas atados al número de serie del
  /// disco duro.
  ///
  /// Algunos equipos armados traen un UUID de relleno (todo ceros o todo F).
  /// Se descarta explícitamente: si se aceptara, todos esos equipos
  /// compartirían señal y la licencia de uno serviría en cualquier otro.
  static Future<String> _uuidEquipo() async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-CimInstance Win32_ComputerSystemProduct).UUID',
      ]);
      final uuid = r.stdout.toString().trim();
      final normalizado = uuid.replaceAll('-', '').toUpperCase();
      if (normalizado.isEmpty ||
          RegExp(r'^0+$').hasMatch(normalizado) ||
          RegExp(r'^F+$').hasMatch(normalizado)) {
        return '';
      }
      return uuid;
    } catch (_) {
      return '';
    }
  }

  static String _hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }
}
