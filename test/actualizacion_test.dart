// Aviso de actualización: comparación de versiones y decisión de avisar.
//
// La prueba que justifica todo este archivo es la de '1.10.0 vs 1.9.0'.
// Comparar versiones como texto es el error clásico, y aquí se traduce en algo
// concreto y caro: avisarle a un cliente que "actualice" a una versión más
// vieja que la suya. Desde la v1.0.0 la app se defiende y no abre esa base,
// así que el negocio se queda sin poder cobrar hasta que llegue el instalador
// correcto.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/actualizacion/actualizacion_service.dart';
import 'package:pvapp/core/actualizacion/version_app.dart';

Map<String, dynamic> _manifiesto({
  String version = '2.0.0',
  String url = 'https://ejemplo.com/PvControl-Setup-2.0.0.exe',
  String? sha,
  bool obligatoria = false,
  String notas = 'El corte X ahora incluye las devoluciones del turno.',
}) =>
    {
      'version': version,
      'url': url,
      'sha256': sha ?? ('a' * 64),
      'obligatoria': obligatoria,
      'notas': notas,
    };

void main() {
  group('Lectura de versiones', () {
    test('lee el formato normal', () {
      expect(VersionApp.parsear('1.2.3'), const VersionApp(1, 2, 3));
    });

    test('tolera la v inicial, los espacios y el número de compilación', () {
      expect(VersionApp.parsear('  v1.2.3  '), const VersionApp(1, 2, 3));
      expect(VersionApp.parsear('1.2.3+45'), const VersionApp(1, 2, 3));
    });

    test('devuelve null en vez de adivinar', () {
      for (final basura in ['', '1.2', '1.2.3.4', 'uno.dos.tres', 'latest', null]) {
        expect(VersionApp.parsear(basura), isNull, reason: 'entrada: $basura');
      }
    });
  });

  group('Orden de versiones', () {
    test('1.10.0 es más nueva que 1.9.0 (no es comparación de texto)', () {
      final diez = VersionApp.parsear('1.10.0')!;
      final nueve = VersionApp.parsear('1.9.0')!;

      expect(diez.esMasNuevaQue(nueve), isTrue);
      expect(nueve.esMasNuevaQue(diez), isFalse);
      // Y para que quede claro por qué hace falta esta clase:
      expect('1.10.0'.compareTo('1.9.0') > 0, isFalse);
    });

    test('compara en orden mayor, menor, parche', () {
      expect(VersionApp.parsear('2.0.0')!.esMasNuevaQue(VersionApp.parsear('1.99.99')!), isTrue);
      expect(VersionApp.parsear('1.3.0')!.esMasNuevaQue(VersionApp.parsear('1.2.99')!), isTrue);
      expect(VersionApp.parsear('1.2.10')!.esMasNuevaQue(VersionApp.parsear('1.2.9')!), isTrue);
    });

    test('la misma versión no es más nueva', () {
      expect(VersionApp.parsear('1.2.3')!.esMasNuevaQue(VersionApp.parsear('1.2.3')!), isFalse);
    });

    test('el número de compilación no cuenta como versión nueva', () {
      // Recompilar sin cambiar nada para el cliente no debe generar un aviso.
      expect(
        VersionApp.parsear('1.2.3+9')!.esMasNuevaQue(VersionApp.parsear('1.2.3+1')!),
        isFalse,
      );
    });

    test('detecta si la actualización va a tocar la base de datos', () {
      // Regla del proyecto: toda migración sube al menos MENOR.
      final base = VersionApp.parsear('1.2.3')!;
      expect(VersionApp.parsear('1.2.9')!.cambiaEsquemaRespectoA(base), isFalse);
      expect(VersionApp.parsear('1.3.0')!.cambiaEsquemaRespectoA(base), isTrue);
      expect(VersionApp.parsear('2.0.0')!.cambiaEsquemaRespectoA(base), isTrue);
    });
  });

  group('Decisión de avisar', () {
    Actualizacion? decidir(String instalada, Map<String, dynamic> m) =>
        ActualizacionService.decidir(versionInstalada: instalada, manifiesto: m);

    test('avisa cuando hay algo más nuevo', () {
      final a = decidir('1.0.0', _manifiesto(version: '1.1.0'));
      expect(a, isNotNull);
      expect(a!.version.toString(), '1.1.0');
      expect(a.notas, contains('corte X'));
      expect(a.cambiaEsquema, isTrue);
    });

    test('no avisa si ya está al día', () {
      expect(decidir('2.0.0', _manifiesto(version: '2.0.0')), isNull);
    });

    test('NO avisa si el manifiesto trae una versión más vieja', () {
      // El caso que de verdad importa: publicar por error un manifiesto viejo
      // no debe empujar a nadie a instalar hacia atrás.
      expect(decidir('2.0.0', _manifiesto(version: '1.9.0')), isNull);
    });

    test('un manifiesto ilegible es silencio, no una alarma', () {
      expect(decidir('1.0.0', _manifiesto(version: 'latest')), isNull);
      expect(decidir('1.0.0', {'notas': 'sin nada más'}), isNull);
      expect(decidir('desconocida', _manifiesto(version: '9.9.9')), isNull);
    });

    test('rechaza un manifiesto sin URL o con hash incompleto', () {
      // Sin hash verificable no hay descarga automática que valga: sería
      // ejecutar en la caja del cliente lo que devuelva la red.
      expect(decidir('1.0.0', _manifiesto(url: '')), isNull);
      expect(decidir('1.0.0', _manifiesto(sha: 'abc123')), isNull);
      expect(decidir('1.0.0', _manifiesto(sha: '')), isNull);
    });

    test('acepta el hash en mayúsculas y lo normaliza', () {
      final a = decidir('1.0.0', _manifiesto(sha: 'A' * 64));
      expect(a, isNotNull);
      expect(a!.sha256, 'a' * 64);
    });

    test('lee la marca de obligatoria', () {
      expect(decidir('1.0.0', _manifiesto(obligatoria: true))!.obligatoria, isTrue);
      expect(decidir('1.0.0', _manifiesto())!.obligatoria, isFalse);
    });
  });

  test('la revisión viene apagada mientras no haya dónde publicar', () {
    expect(ActualizacionService.activo, isFalse);
  });
}
