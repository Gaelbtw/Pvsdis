import 'dart:async';
import 'dart:math' as math;

/// Limita los intentos de inicio de sesión fallidos.
///
/// Sin esto no había ningún control: ni contador, ni espera, ni bloqueo. Un
/// PIN de 4 dígitos son 10.000 combinaciones, al alcance de cualquiera que se
/// quede un rato a solas con la terminal. El coste de bcrypt actuaba como
/// freno accidental, no como una medida.
///
/// El bloqueo es en memoria y por proceso: se pierde al reiniciar la app.
/// Es una decisión consciente y no un descuido — persistirlo en la base
/// permitiría a un atacante con acceso al archivo borrar el contador de todos
/// modos, y dejaría a un negocio con la caja bloqueada tras un corte de luz.
/// Lo que sí consigue es que el ataque no pueda automatizarse contra la app
/// en marcha.
///
/// Política: tras [intentosAntesDeEspera] fallos consecutivos sobre la misma
/// clave, cada intento adicional debe esperar un tiempo que se duplica
/// (1s, 2s, 4s…) hasta [esperaMaxima]. Un acierto limpia el contador.
class LoginThrottle {
  LoginThrottle._();
  static final LoginThrottle instancia = LoginThrottle._();

  /// Fallos consecutivos permitidos antes de empezar a exigir espera. Los
  /// primeros son gratis: un cajero que se equivoca de tecla no debe pagar
  /// por ello.
  static const int intentosAntesDeEspera = 3;

  static const Duration esperaBase = Duration(seconds: 1);
  static const Duration esperaMaxima = Duration(minutes: 5);

  final Map<String, int> _fallos = {};
  final Map<String, DateTime> _bloqueadoHasta = {};

  /// Reloj inyectable para poder probar la escalada sin esperas reales.
  DateTime Function() ahora = DateTime.now;

  /// Clave con la que se agrupan los intentos. El login por PIN no identifica
  /// a nadie de antemano (se prueba contra todos los usuarios), así que
  /// comparte una única clave.
  ///
  /// Empieza con un NUL para que ningún nombre de usuario pueda producir esta
  /// misma clave y acabar compartiendo el contador del PIN: [claveUsuario]
  /// solo recorta espacios y pasa a minúsculas, y un NUL no se recorta.
  ///
  /// Antes ese carácter estaba escrito como un byte NUL LITERAL dentro del
  /// archivo fuente. Funcionaba, pero hacía que `grep` tratara el archivo como
  /// binario y que cualquier editor que limpie caracteres de control rompiera
  /// la garantía en silencio. Como escape es el mismo valor y sobrevive a
  /// cualquier herramienta.
  static const String clavePin = '\u0000pin';

  static String claveUsuario(String nombre) => nombre.trim().toLowerCase();

  /// Tiempo que falta para poder reintentar, o `null` si se puede ahora.
  Duration? esperaRestante(String clave) {
    final hasta = _bloqueadoHasta[clave];
    if (hasta == null) return null;

    final restante = hasta.difference(ahora());
    if (restante <= Duration.zero) {
      _bloqueadoHasta.remove(clave);
      return null;
    }
    return restante;
  }

  /// Lanza si [clave] todavía está en espera. Se llama antes de verificar
  /// credenciales, para no gastar un bcrypt en un intento que igual se
  /// rechazaría.
  void verificarPuedeIntentar(String clave) {
    final restante = esperaRestante(clave);
    if (restante == null) return;

    final segundos = restante.inSeconds + 1;
    final texto = segundos < 60
        ? '$segundos segundo${segundos == 1 ? '' : 's'}'
        : '${(segundos / 60).ceil()} minuto${(segundos / 60).ceil() == 1 ? '' : 's'}';
    throw Exception('Demasiados intentos fallidos. Espera $texto antes de volver a intentar.');
  }

  /// Registra un intento fallido y, pasado el margen, programa la espera.
  void registrarFallo(String clave) {
    final fallos = (_fallos[clave] ?? 0) + 1;
    _fallos[clave] = fallos;
    _ultimoFallo[clave] = ahora();

    final excedente = fallos - intentosAntesDeEspera;
    if (excedente <= 0) {
      _persistir();
      return;
    }

    // 1s, 2s, 4s, 8s… con tope. El `min` sobre el exponente evita desbordar
    // el int antes de aplicar el tope sobre la duración.
    final factor = math.pow(2, math.min(excedente - 1, 20)).toInt();
    final espera = Duration(
      milliseconds: math.min(
        esperaBase.inMilliseconds * factor,
        esperaMaxima.inMilliseconds,
      ),
    );
    _bloqueadoHasta[clave] = ahora().add(espera);
    _persistir();
  }

  /// Un acierto borra el historial de esa clave.
  void registrarExito(String clave) {
    _fallos.remove(clave);
    _bloqueadoHasta.remove(clave);
    _ultimoFallo.remove(clave);
    _persistir();
  }

  /// Solo para pruebas: deja el throttle como recién creado.
  void reiniciar() {
    _fallos.clear();
    _bloqueadoHasta.clear();
    _ultimoFallo.clear();
    ahora = DateTime.now;
    persistencia = null;
  }

  // ---------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------

  /// Momento del último fallo por clave, para poder caducar contadores viejos
  /// al recargar (ver [ventanaFallos]).
  final Map<String, DateTime> _ultimoFallo = {};

  /// Dónde se guarda el estado entre reinicios. `null` = solo en memoria.
  ///
  /// Se deja sin asignar por defecto a propósito: las pruebas y cualquier
  /// código que no llame a [cargar] siguen comportándose exactamente como
  /// antes, sin tocar disco.
  ThrottlePersistencia? persistencia;

  /// Un contador de fallos caduca si no hubo actividad en este tiempo.
  ///
  /// Es lo que evita el escenario que hacía descartar la persistencia: sin
  /// caducidad, los 3 fallos de un cajero despistado el lunes se sumarían a
  /// los del martes y acabarían bloqueando la caja por algo que no fue un
  /// ataque. Con ventana, el historial viejo simplemente desaparece.
  static const Duration ventanaFallos = Duration(minutes: 15);

  /// Carga el estado guardado, descartando lo que ya caducó. Se llama una vez
  /// al arrancar la app.
  ///
  /// Sin esto el throttle vivía solo en memoria y bastaba con cerrar y volver
  /// a abrir el .exe para poner el contador a cero -- un ataque por fuerza
  /// bruta contra un PIN de 4 dígitos solo tenía que reiniciar el proceso cada
  /// 3 intentos.
  Future<void> cargar(ThrottlePersistencia almacen) async {
    persistencia = almacen;

    final estado = await almacen.leer();
    if (estado == null) return;

    final ahoraMismo = ahora();

    estado.forEach((clave, datos) {
      final ultimo = datos.ultimoFallo;
      if (ahoraMismo.difference(ultimo) > ventanaFallos) return;

      _fallos[clave] = datos.fallos;
      _ultimoFallo[clave] = ultimo;

      // Un bloqueo ya vencido no se restaura: la espera máxima son 5 minutos,
      // así que tras un corte de luz largo la caja abre sin castigo.
      final hasta = datos.bloqueadoHasta;
      if (hasta != null && hasta.isAfter(ahoraMismo)) {
        _bloqueadoHasta[clave] = hasta;
      }
    });
  }

  /// Guarda el estado actual. Deliberadamente sin `await`: bloquear un login
  /// por una escritura de disco sería peor que perder el último contador si la
  /// app muere en ese instante exacto.
  void _persistir() {
    final almacen = persistencia;
    if (almacen == null) return;

    final estado = <String, EstadoThrottle>{};
    for (final entrada in _fallos.entries) {
      final ultimo = _ultimoFallo[entrada.key];
      if (ultimo == null) continue;
      estado[entrada.key] = EstadoThrottle(
        fallos: entrada.value,
        ultimoFallo: ultimo,
        bloqueadoHasta: _bloqueadoHasta[entrada.key],
      );
    }

    unawaited(almacen.guardar(estado));
  }
}

/// Estado persistido de una clave del throttle.
class EstadoThrottle {
  const EstadoThrottle({
    required this.fallos,
    required this.ultimoFallo,
    this.bloqueadoHasta,
  });

  final int fallos;
  final DateTime ultimoFallo;
  final DateTime? bloqueadoHasta;

  Map<String, dynamic> aMapa() => {
        'fallos': fallos,
        'ultimoFallo': ultimoFallo.toIso8601String(),
        if (bloqueadoHasta != null) 'bloqueadoHasta': bloqueadoHasta!.toIso8601String(),
      };

  static EstadoThrottle? desdeMapa(Object? valor) {
    if (valor is! Map) return null;

    final fallos = valor['fallos'];
    final ultimo = DateTime.tryParse(valor['ultimoFallo']?.toString() ?? '');
    if (fallos is! int || ultimo == null) return null;

    return EstadoThrottle(
      fallos: fallos,
      ultimoFallo: ultimo,
      bloqueadoHasta: DateTime.tryParse(valor['bloqueadoHasta']?.toString() ?? ''),
    );
  }
}

/// Almacén del estado del throttle. Interfaz aparte para que [LoginThrottle]
/// no dependa de `dart:io` ni de `path_provider` y siga siendo probable sin
/// tocar disco.
abstract class ThrottlePersistencia {
  Future<Map<String, EstadoThrottle>?> leer();
  Future<void> guardar(Map<String, EstadoThrottle> estado);
}
