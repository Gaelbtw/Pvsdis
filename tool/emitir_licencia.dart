// Emisor de licencias de Pv Control.
//
//   dart run tool/emitir_licencia.dart <comando> [opciones]
//
// Comandos:
//   generar-llaves   Crea el par Ed25519. Se corre UNA sola vez en la vida.
//   emitir           Firma un .lic para un cliente.
//   verificar        Comprueba un .lic ya emitido.
//
// Es una herramienta de escritorio para ti, no parte de la app: vive en tool/
// y nunca se compila dentro del .exe que recibe el cliente.
//
// No usa Flutter a propósito, para que corra con `dart run` sin levantar el
// entorno completo. Comparte con la app el modelo `Licencia` —que es donde
// vive el formato del payload y donde de verdad podrían divergir emisor y
// verificador—, no la infraestructura.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:pvapp/core/licencia/licencia.dart';

const _uso = '''
Emisor de licencias de Pv Control

  dart run tool/emitir_licencia.dart generar-llaves --salida <ruta-base>

      Crea <ruta-base>.privada y <ruta-base>.publica, e imprime la clave
      pública lista para pegar en lib/core/licencia/clave_publica.dart.

      SE CORRE UNA SOLA VEZ. Guarda el archivo .privada FUERA del repositorio
      y con respaldo: si lo pierdes, ninguna licencia nueva será aceptada por
      las versiones ya instaladas en los clientes.

  dart run tool/emitir_licencia.dart emitir \\
      --llave    C:\\llaves\\pvcontrol.privada \\
      --negocio  "Abarrotes La Esquina" \\
      --huella   A3F2-9C1B-7E44 \\
      --edicion  pro \\
      --meses    12 \\
      [--cajas 1] [--salida archivo.lic]

      La huella es el codigo de instalacion que el cliente ve en
      Configuracion -> Licencia y te manda por WhatsApp.

  dart run tool/emitir_licencia.dart verificar \\
      --llave C:\\llaves\\pvcontrol.privada archivo.lic

      Comprueba firma, vigencia y contenido.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln(_uso);
    exit(1);
  }

  final opciones = _parsear(args.sublist(1));

  try {
    switch (args.first) {
      case 'generar-llaves':
        await _generarLlaves(opciones);
      case 'emitir':
        await _emitir(opciones);
      case 'verificar':
        await _verificar(opciones, args.sublist(1));
      case '-h':
      case '--help':
      case 'ayuda':
        stdout.writeln(_uso);
      default:
        stderr.writeln('Comando desconocido: "${args.first}"\n');
        stdout.writeln(_uso);
        exit(1);
    }
  } on _ErrorDeUso catch (e) {
    stderr.writeln('\nERROR: ${e.mensaje}\n');
    exit(1);
  }
}

// --------------------------------------------------------------- comandos

Future<void> _generarLlaves(Map<String, String> o) async {
  final base = o['salida'] ?? _exigir(o, 'salida');

  final privada = File('$base.privada');
  if (await privada.exists()) {
    throw _ErrorDeUso(
      'Ya existe ${privada.path}.\n'
      'NO lo sobrescribas: si esa llave ya emitió licencias, generarla de '
      'nuevo invalida todas. Borra el archivo a mano solo si estás seguro de '
      'que nunca se usó.',
    );
  }

  // Semilla de 32 bytes de Random.secure(). Es el material del que sale todo
  // lo demás: si esto fuera predecible, cualquiera podría reconstruir la llave
  // privada y emitir licencias.
  final rnd = Random.secure();
  final semilla = List<int>.generate(32, (_) => rnd.nextInt(256));

  final par = await Ed25519().newKeyPairFromSeed(semilla);
  final publica = (await par.extractPublicKey()).bytes;

  await privada.writeAsString('${base64.encode(semilla)}\n');
  await File('$base.publica').writeAsString('${base64.encode(publica)}\n');

  stdout.writeln('''
Llaves generadas.

  Privada : ${privada.path}   <-- GUARDALA FUERA DEL REPO, CON RESPALDO
  Publica : $base.publica

Pega esto en lib/core/licencia/clave_publica.dart y recompila:

const List<int> clavePublicaLicencias = <int>[
${_formatearBytes(publica)}
];
''');
}

Future<void> _emitir(Map<String, String> o) async {
  final par = await _cargarPar(o);

  final negocio = _exigir(o, 'negocio');
  final huella = _exigir(o, 'huella').trim().toUpperCase();
  final edicion = Edicion.desdeClave(_exigir(o, 'edicion'));
  if (edicion == null) {
    throw _ErrorDeUso(
      'Edición no reconocida. Opciones: '
      '${Edicion.values.map((e) => e.clave).join(', ')}',
    );
  }

  if (!RegExp(r'^[A-Z0-9\-]{4,}(-[A-Z0-9\-]{4,}){2}$').hasMatch(huella)) {
    throw _ErrorDeUso(
      'La huella "$huella" no parece un código de instalación. Debe verse '
      'como A3F2-9C1B-7E44. Pídele al cliente que lo copie con el botón de '
      'Configuración -> Licencia en vez de teclearlo.',
    );
  }

  final meses = int.tryParse(o['meses'] ?? '12');
  if (meses == null || meses <= 0) {
    throw const _ErrorDeUso('--meses debe ser un número mayor que cero.');
  }

  final hoy = DateTime.now();
  final licencia = Licencia(
    negocio: negocio,
    edicion: edicion,
    cajas: int.tryParse(o['cajas'] ?? '1') ?? 1,
    emitida: hoy,
    // Se suman meses, no días: un cliente que paga "un año" espera vencer el
    // mismo día del año siguiente, no 365 días después.
    expira: DateTime(hoy.year, hoy.month + meses, hoy.day),
    huella: huella,
  );

  final payload = utf8.encode(jsonEncode(licencia.aJson()));
  final firma = await Ed25519().sign(payload, keyPair: par);
  final archivo = Licencia.armarArchivo(payload, firma.bytes);

  // Se verifica lo recién emitido antes de entregarlo. Cuesta milisegundos y
  // evita el peor escenario posible: mandarle a un cliente un archivo que su
  // app va a rechazar, y enterarte por teléfono.
  final publica = await par.extractPublicKey();
  if (!await Ed25519().verify(
    payload,
    signature: Signature(firma.bytes, publicKey: publica),
  )) {
    throw const _ErrorDeUso(
      'La licencia recién firmada no se verifica contra su propia llave. '
      'No la entregues: hay algo mal en el entorno.',
    );
  }

  final salida = File(o['salida'] ?? _nombreSugerido(negocio, huella));
  await salida.writeAsString(archivo);

  stdout.writeln('''
Licencia emitida: ${salida.path}

  Negocio  : ${licencia.negocio}
  Edición  : ${licencia.edicion.nombre}
  Cajas    : ${licencia.cajas}
  Equipo   : ${licencia.huella}
  Emitida  : ${Licencia.soloFecha(licencia.emitida)}
  Expira   : ${Licencia.soloFecha(licencia.expira)}  (${licencia.diasParaVencer()} días)

--- para copiar y pegar en WhatsApp ---

Te mando el archivo de licencia de Pv Control.

Para activarlo: abre Pv Control, entra a Configuracion -> Licencia, oprime
"Importar archivo de licencia" y elige el archivo ${salida.uri.pathSegments.last}
que te acabo de mandar.

Queda vigente hasta el ${Licencia.soloFecha(licencia.expira)}.

---------------------------------------
''');
}

Future<void> _verificar(Map<String, String> o, List<String> args) async {
  final ruta = args.firstWhere(
    (a) => !a.startsWith('--') && a.toLowerCase().endsWith('.lic'),
    orElse: () => throw const _ErrorDeUso(
      'Falta el archivo .lic a verificar.',
    ),
  );

  final par = await _cargarPar(o);
  final publica = await par.extractPublicKey();
  final contenido = await File(ruta).readAsString();

  final partes = Licencia.partirArchivo(contenido);
  final valida = await Ed25519().verify(
    partes.payload,
    signature: Signature(partes.firma, publicKey: publica),
  );

  if (!valida) {
    stderr.writeln('FIRMA INVÁLIDA: el archivo fue alterado, o lo emitió otra '
        'llave distinta a la que pasaste en --llave.');
    exit(2);
  }

  final licencia = Licencia.desdeJson(
    jsonDecode(utf8.decode(partes.payload)) as Map<String, dynamic>,
  );
  final dias = licencia.diasParaVencer();

  stdout.writeln('''
Firma válida.

  Negocio  : ${licencia.negocio}
  Edición  : ${licencia.edicion.nombre}
  Cajas    : ${licencia.cajas}
  Equipo   : ${licencia.huella}
  Emitida  : ${Licencia.soloFecha(licencia.emitida)}
  Expira   : ${Licencia.soloFecha(licencia.expira)}
  Estado   : ${dias < 0 ? 'VENCIDA hace ${-dias} días' : 'vigente, faltan $dias días'}
''');
}

// -------------------------------------------------------------- utilidades

Future<SimpleKeyPair> _cargarPar(Map<String, String> o) async {
  final ruta = _exigir(o, 'llave');
  final archivo = File(ruta);
  if (!await archivo.exists()) {
    throw _ErrorDeUso('No existe el archivo de llave privada: $ruta');
  }

  final semilla = base64.decode((await archivo.readAsString()).trim());
  if (semilla.length != 32) {
    throw const _ErrorDeUso(
      'El archivo de llave privada no tiene el formato esperado (32 bytes en '
      'base64). ¿Es el .privada que generó este mismo comando?',
    );
  }
  return Ed25519().newKeyPairFromSeed(semilla);
}

String _nombreSugerido(String negocio, String huella) {
  final slug = negocio
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '$slug-${huella.replaceAll('-', '')}.lic';
}

String _formatearBytes(List<int> bytes) {
  final lineas = <String>[];
  for (var i = 0; i < bytes.length; i += 8) {
    final trozo = bytes.sublist(i, min(i + 8, bytes.length));
    lineas.add('  ${trozo.join(', ')},');
  }
  return lineas.join('\n');
}

/// Parseo mínimo de `--clave valor`. No se usa `package:args` para no sumar
/// una dependencia por tres banderas.
Map<String, String> _parsear(List<String> args) {
  final o = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    final clave = args[i].substring(2);
    final valor = (i + 1 < args.length && !args[i + 1].startsWith('--'))
        ? args[++i]
        : '';
    o[clave] = valor;
  }
  return o;
}

String _exigir(Map<String, String> o, String clave) {
  final v = o[clave];
  if (v == null || v.trim().isEmpty) {
    throw _ErrorDeUso('Falta --$clave');
  }
  return v.trim();
}

class _ErrorDeUso implements Exception {
  const _ErrorDeUso(this.mensaje);
  final String mensaje;
}
