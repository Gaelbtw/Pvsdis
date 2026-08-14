// Licenciamiento: huella del equipo, formato del archivo, firma Ed25519 y
// —lo más importante— cuándo se degrada y cuándo no.
//
// La prueba que más vale de este archivo es la última: que vender y cobrar
// nunca queden del lado bloqueable. Todo lo demás se puede corregir en una
// versión; dejar a un negocio sin poder cobrar un sábado, no.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/licencia/huella_equipo.dart';
import 'package:pvapp/core/licencia/licencia.dart';
import 'package:pvapp/core/licencia/licencia_service.dart';

/// Par de llaves de juguete para las pruebas. No tiene nada que ver con la
/// llave real de producción, que nunca vive en el repositorio.
Future<SimpleKeyPair> _parDePruebas([int semillaBase = 7]) {
  final rnd = Random(semillaBase);
  return Ed25519().newKeyPairFromSeed(
    List<int>.generate(32, (_) => rnd.nextInt(256)),
  );
}

Future<String> _firmar(Licencia licencia, SimpleKeyPair par) async {
  final payload = utf8.encode(jsonEncode(licencia.aJson()));
  final firma = await Ed25519().sign(payload, keyPair: par);
  return Licencia.armarArchivo(payload, firma.bytes);
}

Licencia _licencia({
  DateTime? expira,
  String huella = 'ABCD-EFGH-JKMN',
  Edicion edicion = Edicion.pro,
}) =>
    Licencia(
      negocio: 'Abarrotes La Esquina',
      edicion: edicion,
      cajas: 1,
      emitida: DateTime(2026, 1, 1),
      expira: expira ?? DateTime(2027, 1, 1),
      huella: huella,
    );

void main() {
  // ==================================================== huella del equipo

  group('Huella del equipo', () {
    test('el código son tres grupos, uno por señal', () {
      final codigo = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      expect(codigo.split('-'), hasLength(3));
      expect(codigo.split('-').every((g) => g.length == 4), isTrue);
    });

    test('las mismas señales dan siempre el mismo código', () {
      final a = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      final b = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      expect(a, b);
    });

    test('no distingue mayúsculas ni espacios sobrantes', () {
      expect(
        HuellaEquipo.codigoDesde([' GUID-1 ', 'UUID-1', 'caja-01']),
        HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']),
      );
    });

    test('una señal ilegible queda marcada y nunca cuenta como coincidencia',
        () {
      final codigo = HuellaEquipo.codigoDesde(['', 'uuid-1', 'CAJA-01']);
      expect(codigo.split('-').first, HuellaEquipo.grupoDesconocido);

      // Dos equipos distintos en los que falla la misma señal no son el mismo
      // equipo por ese hecho.
      final otro = HuellaEquipo.codigoDesde(['', 'uuid-9', 'CAJA-09']);
      expect(HuellaEquipo.coincidencias(codigo, otro), 0);
    });

    test('cambiar el disco duro NO invalida la licencia', () {
      // Ninguna de las tres señales depende del disco.
      final antes = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      final despues = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      expect(HuellaEquipo.esMismoEquipo(antes, despues), isTrue);
    });

    test('renombrar la computadora NO invalida la licencia (2 de 3)', () {
      final antes = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      final despues =
          HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'MOSTRADOR']);
      expect(HuellaEquipo.coincidencias(antes, despues), 2);
      expect(HuellaEquipo.esMismoEquipo(antes, despues), isTrue);
    });

    test('reinstalar Windows SÍ obliga a reactivar', () {
      // Se pierden MachineGuid y el nombre; solo sobrevive el UUID del equipo.
      final antes = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      final despues =
          HuellaEquipo.codigoDesde(['guid-2', 'uuid-1', 'DESKTOP-XYZ']);
      expect(HuellaEquipo.coincidencias(antes, despues), 1);
      expect(HuellaEquipo.esMismoEquipo(antes, despues), isFalse);
    });

    test('otra computadora no pasa', () {
      final a = HuellaEquipo.codigoDesde(['guid-1', 'uuid-1', 'CAJA-01']);
      final b = HuellaEquipo.codigoDesde(['guid-2', 'uuid-2', 'CAJA-02']);
      expect(HuellaEquipo.esMismoEquipo(a, b), isFalse);
    });

    test('compara por posición, no como conjunto', () {
      // Mismos grupos, en distinto orden: son equipos distintos.
      final a = HuellaEquipo.codigoDesde(['x', 'y', 'z']);
      final b = HuellaEquipo.codigoDesde(['y', 'x', 'z']);
      expect(HuellaEquipo.coincidencias(a, b), 1);
      expect(HuellaEquipo.esMismoEquipo(a, b), isFalse);
    });

    test('el alfabeto no incluye caracteres que se confundan al dictarlos', () {
      // Alguien va a leer esto en voz alta por teléfono.
      final codigos = List.generate(
        200,
        (i) => HuellaEquipo.codigoDesde(['g$i', 'u$i', 'c$i']),
      ).join();
      for (final prohibido in ['I', 'L', 'O', 'U', '0', '1']) {
        expect(codigos.contains(prohibido), isFalse,
            reason: 'el código no debe contener "$prohibido"');
      }
    });
  });

  // ===================================================== formato del .lic

  group('Formato de la licencia', () {
    test('el payload es canónico: mismas llaves, mismo orden', () {
      final json = _licencia().aJson();
      expect(json.keys.toList(), List.of(json.keys)..sort());
    });

    test('ida y vuelta conserva los datos', () {
      final original = _licencia();
      final copia = Licencia.desdeJson(jsonDecode(jsonEncode(original.aJson())));

      expect(copia.negocio, original.negocio);
      expect(copia.edicion, original.edicion);
      expect(copia.cajas, original.cajas);
      expect(copia.huella, original.huella);
      expect(Licencia.soloFecha(copia.expira),
          Licencia.soloFecha(original.expira));
    });

    test('rechaza una edición desconocida', () {
      final json = _licencia().aJson()..['edicion'] = 'platino';
      expect(
        () => Licencia.desdeJson(json),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('rechaza fechas ilegibles', () {
      final json = _licencia().aJson()..['expira'] = 'algún día';
      expect(
        () => Licencia.desdeJson(json),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('rechaza un formato más nuevo del que entiende', () {
      final json = _licencia().aJson()
        ..['version'] = Licencia.versionFormato + 1;
      expect(
        () => Licencia.desdeJson(json),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('tolera los saltos de línea que mete WhatsApp o el correo', () {
      final payload = utf8.encode(jsonEncode(_licencia().aJson()));
      final armado = Licencia.armarArchivo(payload, List.filled(64, 3));

      // El mismo archivo, partido en renglones de 40 caracteres.
      final troceado = RegExp('.{1,40}')
          .allMatches(armado)
          .map((m) => m.group(0))
          .join('\n');

      final partes = Licencia.partirArchivo(troceado);
      expect(partes.payload, payload);
    });

    test('rechaza un archivo cortado a la mitad', () {
      expect(
        () => Licencia.partirArchivo('solo-una-parte-sin-punto'),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('la vigencia se mide por día, no por instante', () {
      // Una licencia que expira "hoy" vale todo el día de hoy. Matarla a las
      // 00:00:01 y explicárselo a un cliente que pagó hasta hoy es una llamada
      // que nadie quiere.
      final hoy = DateTime.now();
      final licencia = _licencia(expira: DateTime(hoy.year, hoy.month, hoy.day));

      expect(licencia.diasParaVencer(), 0);
      expect(licencia.estaVencida(), isFalse);
    });
  });

  // ============================================================ la firma

  group('Firma Ed25519', () {
    final servicio = LicenciaService.instancia;

    tearDown(servicio.reiniciarParaPruebas);

    test('sin clave pública compilada, el licenciamiento está apagado', () {
      servicio.reiniciarParaPruebas();
      expect(servicio.activo, isFalse,
          reason: 'el repo no debe traer una clave de producción');
    });

    test('acepta una licencia bien firmada', () async {
      final par = await _parDePruebas();
      servicio.configurarClavePublica((await par.extractPublicKey()).bytes);

      final licencia =
          await servicio.verificarContenido(await _firmar(_licencia(), par));

      expect(licencia.negocio, 'Abarrotes La Esquina');
      expect(licencia.edicion, Edicion.pro);
    });

    test('rechaza una licencia con el contenido alterado', () async {
      final par = await _parDePruebas();
      servicio.configurarClavePublica((await par.extractPublicKey()).bytes);

      // Alguien edita el JSON para estirarse la fecha y vuelve a armar el
      // archivo con la firma vieja.
      final original = _licencia();
      final firmado = await _firmar(original, par);
      final firma = firmado.split('.')[1];

      final alterada = original.aJson()..['expira'] = '2099-12-31';
      final falsificado =
          '${base64Url.encode(utf8.encode(jsonEncode(alterada)))}.$firma';

      await expectLater(
        servicio.verificarContenido(falsificado),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('rechaza una licencia firmada con otra llave', () async {
      final mia = await _parDePruebas(7);
      final ajena = await _parDePruebas(99);
      servicio.configurarClavePublica((await mia.extractPublicKey()).bytes);

      await expectLater(
        servicio.verificarContenido(await _firmar(_licencia(), ajena)),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });

    test('con el licenciamiento apagado, verificar no finge que funciona',
        () async {
      servicio.reiniciarParaPruebas();
      await expectLater(
        servicio.verificarContenido('lo.que.sea'),
        throwsA(isA<LicenciaInvalidaException>()),
      );
    });
  });

  // ======================================================== degradación

  group('Degradación por vencimiento', () {
    final hoy = DateTime(2026, 8, 14);
    EstadoLicencia estadoCon(int diasRestantes) =>
        LicenciaService.evaluarVigencia(
          _licencia(expira: hoy.add(Duration(days: diasRestantes))),
          ahora: hoy,
        );

    test('vigente cuando falta bastante', () {
      expect(estadoCon(200).situacion, SituacionLicencia.vigente);
      expect(estadoCon(200).requiereAvisoAlAbrir, isFalse);
    });

    test('avisa 15 días antes, sin bloquear nada', () {
      final e = estadoCon(LicenciaService.diasAvisoPrevio);
      expect(e.situacion, SituacionLicencia.porVencer);
      expect(e.requiereAvisoAlAbrir, isTrue);
      expect(e.requiereBanner, isFalse);
      expect(e.estaDegradada, isFalse);
    });

    test('el día que vence todavía funciona todo', () {
      final e = estadoCon(0);
      expect(e.situacion, SituacionLicencia.porVencer);
      expect(e.estaDegradada, isFalse);
    });

    test('vencida hace poco: banner permanente, nada bloqueado', () {
      final e = estadoCon(-10);
      expect(e.situacion, SituacionLicencia.enGracia);
      expect(e.requiereBanner, isTrue);
      expect(e.estaDegradada, isFalse);
      for (final f in FuncionLicenciada.values) {
        expect(e.permite(f), isTrue);
      }
    });

    test('el último día de gracia todavía no degrada', () {
      expect(
        estadoCon(-LicenciaService.diasDeGracia).situacion,
        SituacionLicencia.enGracia,
      );
    });

    test('pasada la gracia se bloquean las funciones administrativas', () {
      final e = estadoCon(-LicenciaService.diasDeGracia - 1);
      expect(e.situacion, SituacionLicencia.vencida);
      expect(e.estaDegradada, isTrue);
      for (final f in FuncionLicenciada.values) {
        expect(e.permite(f), isFalse);
      }
    });

    test('una licencia de otro equipo degrada, no bloquea', () {
      final e = LicenciaService.evaluarVigencia(
        _licencia(),
        ahora: hoy,
        mismoEquipo: false,
      );
      expect(e.situacion, SituacionLicencia.otroEquipo);
      expect(e.estaDegradada, isTrue);
    });

    test('sin licencia, todo está permitido', () {
      const e = EstadoLicencia(situacion: SituacionLicencia.sinLicencia);
      expect(e.estaDegradada, isFalse);
      expect(e.requiereAvisoAlAbrir, isFalse);
      expect(e.edicion, isNull, reason: 'sin licencia no es edición básica');
      for (final f in FuncionLicenciada.values) {
        expect(e.permite(f), isTrue);
      }
    });

    test('el reloj atrasado se marca pero no bloquea', () {
      final e = LicenciaService.evaluarVigencia(
        _licencia(expira: hoy.add(const Duration(days: 100))),
        ahora: hoy,
        relojSospechoso: true,
      );
      expect(e.relojSospechoso, isTrue);
      expect(e.situacion, SituacionLicencia.vigente);
      expect(e.estaDegradada, isFalse);
    });

    test('los mensajes no traen jerga técnica', () {
      for (final dias in [200, 5, -10, -60]) {
        final m = estadoCon(dias).mensaje.toLowerCase();
        expect(m, isNot(contains('exception')));
        expect(m, isNot(contains('ed25519')));
        expect(m, isNot(contains('null')));
      }
    });
  });

  // ============================================ la regla que no se negocia

  test('COBRAR NUNCA SE BLOQUEA', () {
    // Si alguien agrega aquí "ventas", "cobro", "caja" o "ticket", esta prueba
    // truena y obliga a leer el porqué: un punto de venta que deja de cobrar
    // destruye la reputación del proveedor en el pueblo mucho más rápido de lo
    // que cuesta un cliente moroso. La degradación tiene que doler lo
    // suficiente para que paguen, no dejar a un negocio parado un sábado.
    const prohibidas = ['venta', 'cobr', 'caja', 'ticket', 'impri', 'corte'];

    for (final funcion in FuncionLicenciada.values) {
      final nombre = funcion.name.toLowerCase();
      for (final palabra in prohibidas) {
        expect(
          nombre.contains(palabra),
          isFalse,
          reason: 'FuncionLicenciada.${funcion.name} suena a una función de '
              'cobro. Vender, cobrar, imprimir el ticket y cerrar caja deben '
              'seguir funcionando SIEMPRE, con licencia o sin ella.',
        );
      }
    }
  });
}
