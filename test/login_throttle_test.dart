// Pruebas del LoginThrottle. Hasta ahora no tenía ninguna, pese a ser la
// única defensa contra fuerza bruta sobre un PIN de 4 dígitos (10.000
// combinaciones).
//
// El foco está en la persistencia: sin ella el contador vivía solo en memoria
// y cerrar y reabrir el proceso lo ponía a cero, así que la escalada de espera
// no frenaba a nadie que pudiera reiniciar la app.
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/core/security/login_throttle.dart';

/// Persistencia en memoria: permite probar el ciclo guardar/leer sin tocar
/// disco ni depender de `path_provider` (que no funciona en `flutter test`).
class _StoreFalso implements ThrottlePersistencia {
  Map<String, EstadoThrottle>? contenido;
  int escrituras = 0;

  @override
  Future<Map<String, EstadoThrottle>?> leer() async => contenido;

  @override
  Future<void> guardar(Map<String, EstadoThrottle> estado) async {
    escrituras++;
    contenido = Map.of(estado);
  }
}

void main() {
  final throttle = LoginThrottle.instancia;

  setUp(() => throttle.reiniciar());
  tearDown(() => throttle.reiniciar());

  group('escalada en memoria', () {
    test('los primeros intentos no cuestan espera', () {
      for (var i = 0; i < LoginThrottle.intentosAntesDeEspera; i++) {
        throttle.registrarFallo('ana');
      }

      expect(throttle.esperaRestante('ana'), isNull);
      expect(() => throttle.verificarPuedeIntentar('ana'), returnsNormally);
    });

    test('pasado el margen empieza a exigir espera y se duplica', () {
      var reloj = DateTime(2026, 8, 8, 12);
      throttle.ahora = () => reloj;

      for (var i = 0; i < LoginThrottle.intentosAntesDeEspera + 1; i++) {
        throttle.registrarFallo('ana');
      }
      expect(throttle.esperaRestante('ana'), const Duration(seconds: 1));

      throttle.registrarFallo('ana');
      expect(throttle.esperaRestante('ana'), const Duration(seconds: 2));

      throttle.registrarFallo('ana');
      expect(throttle.esperaRestante('ana'), const Duration(seconds: 4));
    });

    test('la espera tiene tope', () {
      var reloj = DateTime(2026, 8, 8, 12);
      throttle.ahora = () => reloj;

      for (var i = 0; i < 40; i++) {
        throttle.registrarFallo('ana');
      }

      expect(throttle.esperaRestante('ana'), LoginThrottle.esperaMaxima);
    });

    test('un acierto limpia el historial', () {
      for (var i = 0; i < 10; i++) {
        throttle.registrarFallo('ana');
      }
      throttle.registrarExito('ana');

      expect(throttle.esperaRestante('ana'), isNull);
    });

    test('las claves son independientes entre usuarios', () {
      for (var i = 0; i < 10; i++) {
        throttle.registrarFallo('ana');
      }

      expect(throttle.esperaRestante('beto'), isNull);
    });

    test('la clave del PIN no colisiona con ningún nombre de usuario', () {
      // clavePin empieza con NUL justamente para esto: claveUsuario solo
      // recorta espacios y pasa a minúsculas, nunca puede producir un NUL.
      expect(LoginThrottle.claveUsuario('pin'), isNot(LoginThrottle.clavePin));
      expect(LoginThrottle.claveUsuario(' pin '), isNot(LoginThrottle.clavePin));
      expect(LoginThrottle.claveUsuario('PIN'), isNot(LoginThrottle.clavePin));
    });
  });

  group('persistencia', () {
    test('sin almacén no se intenta guardar nada', () {
      // Comportamiento por defecto: idéntico al de antes, sin tocar disco.
      throttle.registrarFallo('ana');
      expect(throttle.persistencia, isNull);
    });

    test('el bloqueo sobrevive a un reinicio del proceso', () async {
      final store = _StoreFalso();
      var reloj = DateTime(2026, 8, 8, 12);

      throttle.ahora = () => reloj;
      await throttle.cargar(store);

      for (var i = 0; i < LoginThrottle.intentosAntesDeEspera + 3; i++) {
        throttle.registrarFallo(LoginThrottle.clavePin);
      }
      expect(throttle.esperaRestante(LoginThrottle.clavePin), isNotNull);

      // `_persistir` es fire-and-forget: se cede el turno del event loop para
      // asegurar que la escritura terminó antes de simular el reinicio.
      await Future<void>.delayed(Duration.zero);

      // Simula cerrar y reabrir la app: estado en memoria a cero, mismo
      // archivo. Antes de este cambio, aquí el atacante volvía a empezar
      // limpio.
      throttle.reiniciar();
      throttle.ahora = () => reloj;
      await throttle.cargar(store);

      expect(throttle.esperaRestante(LoginThrottle.clavePin), isNotNull,
          reason: 'reiniciar el proceso no debe borrar el bloqueo');
    });

    test('un bloqueo ya vencido no se restaura', () async {
      final store = _StoreFalso();
      var reloj = DateTime(2026, 8, 8, 12);

      throttle.ahora = () => reloj;
      await throttle.cargar(store);
      for (var i = 0; i < LoginThrottle.intentosAntesDeEspera + 1; i++) {
        throttle.registrarFallo('ana');
      }

      await Future<void>.delayed(Duration.zero);

      // Pasan 10 minutos: más que la espera de 1 s, pero menos que la ventana
      // de caducidad del contador.
      reloj = reloj.add(const Duration(minutes: 10));

      throttle.reiniciar();
      throttle.ahora = () => reloj;
      await throttle.cargar(store);

      expect(throttle.esperaRestante('ana'), isNull,
          reason: 'tras un corte de luz la caja no puede quedar bloqueada');
    });

    test('los contadores caducan pasada la ventana', () async {
      final store = _StoreFalso();
      var reloj = DateTime(2026, 8, 8, 12);

      throttle.ahora = () => reloj;
      await throttle.cargar(store);
      for (var i = 0; i < 10; i++) {
        throttle.registrarFallo('ana');
      }

      await Future<void>.delayed(Duration.zero);

      // Al día siguiente: los fallos de ayer no deben sumarse a los de hoy.
      reloj = reloj.add(LoginThrottle.ventanaFallos + const Duration(minutes: 1));

      throttle.reiniciar();
      throttle.ahora = () => reloj;
      await throttle.cargar(store);

      throttle.registrarFallo('ana');
      expect(throttle.esperaRestante('ana'), isNull,
          reason: 'el historial viejo debe descartarse, no acumularse');
    });

    test('un acierto borra también lo persistido', () async {
      final store = _StoreFalso();
      await throttle.cargar(store);

      for (var i = 0; i < 5; i++) {
        throttle.registrarFallo('ana');
      }
      throttle.registrarExito('ana');

      // `_persistir` no se espera (es fire-and-forget), así que se cede el
      // turno del event loop antes de mirar el resultado.
      await Future<void>.delayed(Duration.zero);

      expect(store.contenido, isEmpty);
    });

    test('un almacén corrupto o vacío no rompe el arranque', () async {
      final store = _StoreFalso()..contenido = null;

      await throttle.cargar(store);

      expect(throttle.esperaRestante('ana'), isNull);
      expect(() => throttle.verificarPuedeIntentar('ana'), returnsNormally);
    });
  });

  group('mensaje de espera', () {
    test('lanza con el tiempo restante en segundos', () {
      var reloj = DateTime(2026, 8, 8, 12);
      throttle.ahora = () => reloj;

      for (var i = 0; i < LoginThrottle.intentosAntesDeEspera + 1; i++) {
        throttle.registrarFallo('ana');
      }

      expect(
        () => throttle.verificarPuedeIntentar('ana'),
        throwsA(predicate((e) => e.toString().contains('segundo'))),
      );
    });
  });
}
