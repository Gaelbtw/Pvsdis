import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/database_helper.dart';
import 'clave_publica.dart';
import 'huella_equipo.dart';
import 'licencia.dart';

/// En qué situación está la licencia de este equipo.
enum SituacionLicencia {
  /// No hay archivo de licencia. **Todo funciona sin restricción.**
  ///
  /// Es el estado de los primeros clientes, instalados presencialmente y con
  /// contrato en papel. También es el estado de cualquier compilación sin
  /// clave pública ([LicenciaService.activo] en `false`).
  sinLicencia,

  vigente,

  /// Vence pronto: aviso al abrir, nada bloqueado.
  porVencer,

  /// Venció hace poco: banner permanente, nada bloqueado. Existe para que un
  /// pago que se atrasó unos días no le complique la vida a nadie.
  enGracia,

  /// Venció hace tiempo: se restringen funciones administrativas.
  vencida,

  /// La firma no corresponde: el archivo fue alterado, o lo emitió alguien más.
  invalida,

  /// La firma es buena, pero la licencia es de otro equipo.
  otroEquipo,
}

/// Funciones que se apagan cuando la licencia lleva demasiado tiempo vencida.
///
/// **Vender, cobrar, imprimir el ticket y cerrar caja NO están en esta lista, y
/// no deben estarlo nunca.** Un punto de venta que deja de cobrar destruye la
/// reputación del proveedor en el pueblo mucho más rápido de lo que cuesta un
/// cliente moroso. El objetivo de la degradación es que duela lo suficiente
/// para que paguen, no dejar a un negocio sin poder trabajar un sábado.
enum FuncionLicenciada {
  reportes,
  exportacion,
  altaProductos,
  configuracion,
}

/// Resultado de evaluar la licencia: situación, datos y qué se puede hacer.
@immutable
class EstadoLicencia {
  const EstadoLicencia({
    required this.situacion,
    this.licencia,
    this.detalle,
    this.relojSospechoso = false,
  });

  final SituacionLicencia situacion;

  /// La licencia leída, si se pudo verificar. `null` en [SituacionLicencia
  /// .sinLicencia] y en [SituacionLicencia.invalida].
  final Licencia? licencia;

  /// Explicación para mostrar en pantalla cuando algo no está bien.
  final String? detalle;

  /// El reloj del sistema retrocedió respecto al último día visto.
  ///
  /// **No bloquea nada por sí solo**, y es a propósito: una pila de BIOS muerta
  /// o un cambio de zona horaria producen exactamente la misma señal que un
  /// intento de estirar una licencia vencida. Bloquear por esto castigaría a
  /// diez clientes honestos por cada uno que hace trampa.
  final bool relojSospechoso;

  bool get estaDegradada =>
      situacion == SituacionLicencia.vencida ||
      situacion == SituacionLicencia.invalida ||
      situacion == SituacionLicencia.otroEquipo;

  /// Si hay que mostrar un banner permanente en la barra superior.
  bool get requiereBanner =>
      estaDegradada || situacion == SituacionLicencia.enGracia;

  /// Si hay que avisar una vez al abrir la app.
  bool get requiereAvisoAlAbrir =>
      requiereBanner || situacion == SituacionLicencia.porVencer;

  /// Edición contratada. `null` = sin licencia, que hoy significa **todas las
  /// funciones**, no la edición básica.
  Edicion? get edicion => licencia?.edicion;

  /// Hoy la degradación es todo-o-nada: o se apagan las cuatro funciones o
  /// ninguna. El parámetro existe igual porque los puntos de uso deben decir
  /// QUÉ están pidiendo permiso para hacer; el día que una edición habilite
  /// unas funciones y otras no, la regla cambia aquí y no en veinte llamadas.
  bool permite(FuncionLicenciada funcion) => !estaDegradada;

  /// Mensaje corto para el banner y el aviso, en lenguaje de negocio.
  String get mensaje {
    switch (situacion) {
      case SituacionLicencia.sinLicencia:
        return 'Sin licencia registrada.';
      case SituacionLicencia.vigente:
        return 'Licencia vigente hasta el ${_fecha(licencia!.expira)}.';
      case SituacionLicencia.porVencer:
        final dias = licencia!.diasParaVencer();
        return 'Tu licencia vence en $dias día${dias == 1 ? '' : 's'} '
            '(${_fecha(licencia!.expira)}).';
      case SituacionLicencia.enGracia:
        return 'Tu licencia venció el ${_fecha(licencia!.expira)}. '
            'Todo sigue funcionando, pero conviene renovarla.';
      case SituacionLicencia.vencida:
        return 'Tu licencia venció el ${_fecha(licencia!.expira)}. '
            'Puedes seguir vendiendo y cobrando con normalidad, pero los '
            'reportes, las exportaciones, el alta de productos y la '
            'configuración están bloqueados hasta renovarla.';
      case SituacionLicencia.otroEquipo:
        return 'Esta licencia fue emitida para otra computadora. Puedes seguir '
            'vendiendo y cobrando; para reactivar, manda tu código de '
            'instalación.';
      case SituacionLicencia.invalida:
        return detalle ??
            'El archivo de licencia no es válido. Puedes seguir vendiendo y '
            'cobrando mientras se resuelve.';
    }
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Carga, verifica y guarda la licencia de este equipo.
///
/// Verificación **totalmente offline**, coherente con un producto que funciona
/// sin internet: la app trae la clave pública Ed25519 compilada y solo
/// comprueba la firma. No hay servidor que consultar ni que pueda estar caído
/// cuando el negocio abre.
///
/// El día que haya activación en línea (`POST /api/licencias/activar` contra
/// `EsqPos.API`, ver `docs/distribucion.md`), lo único que cambia es de dónde
/// llega el archivo: la verificación es la misma y este código no se toca.
class LicenciaService {
  LicenciaService._();

  static final LicenciaService instancia = LicenciaService._();

  /// Días antes de vencer en que empieza el aviso.
  static const diasAvisoPrevio = 15;

  /// Días de gracia después de vencer antes de degradar.
  static const diasDeGracia = 30;

  static const nombreArchivo = 'licencia.lic';

  /// Clave con la que se verifica. Sale de [clavePublicaLicencias]; las
  /// pruebas la sustituyen con [configurarClavePublica] para poder ejercer el
  /// camino real de verificación --incluido el rechazo de una firma alterada--
  /// sin necesidad de que exista una llave de producción.
  List<int> _clavePublica = clavePublicaLicencias;

  /// `true` si esta compilación verifica licencias. Con la clave vacía, la app
  /// se comporta exactamente como antes de que existiera este módulo.
  bool get activo => _clavePublica.length == 32;

  @visibleForTesting
  void configurarClavePublica(List<int> clave) => _clavePublica = clave;

  /// Devuelve el servicio a su estado inicial. Solo para pruebas: es un
  /// singleton y una prueba no debe contaminar a la siguiente.
  @visibleForTesting
  void reiniciarParaPruebas() {
    _clavePublica = clavePublicaLicencias;
    estadoNotificador.value =
        const EstadoLicencia(situacion: SituacionLicencia.sinLicencia);
  }

  /// Observable para que el banner de la barra superior se redibuje solo al
  /// importar o renovar una licencia. Sin esto habría que acordarse de
  /// refrescar la barra desde cada pantalla que toque la licencia, y tarde o
  /// temprano alguien no lo haría.
  final ValueNotifier<EstadoLicencia> estadoNotificador = ValueNotifier(
    const EstadoLicencia(situacion: SituacionLicencia.sinLicencia),
  );

  EstadoLicencia get estado => estadoNotificador.value;

  /// Atajo para los puntos de uso: `if (!LicenciaService.permiteAhora(...))`.
  static bool permiteAhora(FuncionLicenciada f) => instancia.estado.permite(f);

  /// Evalúa la licencia y deja el resultado en [estado]. Se llama al arrancar
  /// y después de importar un archivo nuevo.
  ///
  /// **Nunca lanza.** Cualquier fallo inesperado se resuelve como
  /// `sinLicencia`, es decir, a favor del cliente. Si esta función tumbara el
  /// arranque, un error aquí dejaría al negocio sin poder cobrar — que es
  /// exactamente lo que todo este módulo trata de evitar.
  Future<EstadoLicencia> cargar() async {
    try {
      estadoNotificador.value = await _evaluar();
    } catch (e) {
      debugPrint('Licencia: fallo inesperado al evaluar ($e). Se continúa sin '
          'restricciones.');
      estadoNotificador.value =
          const EstadoLicencia(situacion: SituacionLicencia.sinLicencia);
    }
    return estado;
  }

  /// Traduce una licencia verificada a una situación, según qué tan lejos
  /// esté de su fecha de vencimiento.
  ///
  /// Pura y estática a propósito: es la regla de negocio que más importa de
  /// todo el módulo —cuándo se degrada y cuándo no— y separarla del disco y de
  /// la base permite probarla contra fechas exactas, sin montar un entorno.
  static EstadoLicencia evaluarVigencia(
    Licencia licencia, {
    DateTime? ahora,
    bool relojSospechoso = false,
    bool mismoEquipo = true,
  }) {
    if (!mismoEquipo) {
      return EstadoLicencia(
        situacion: SituacionLicencia.otroEquipo,
        licencia: licencia,
        relojSospechoso: relojSospechoso,
      );
    }

    final dias = licencia.diasParaVencer(ahora: ahora);

    final SituacionLicencia situacion;
    if (dias < -diasDeGracia) {
      situacion = SituacionLicencia.vencida;
    } else if (dias < 0) {
      situacion = SituacionLicencia.enGracia;
    } else if (dias <= diasAvisoPrevio) {
      situacion = SituacionLicencia.porVencer;
    } else {
      situacion = SituacionLicencia.vigente;
    }

    return EstadoLicencia(
      situacion: situacion,
      licencia: licencia,
      relojSospechoso: relojSospechoso,
    );
  }

  Future<EstadoLicencia> _evaluar() async {
    if (!activo) {
      // Compilación sin clave pública: el licenciamiento no existe todavía.
      return const EstadoLicencia(situacion: SituacionLicencia.sinLicencia);
    }

    final archivo = File(await rutaArchivo());
    final hashGuardado = await _leerHashGuardado();

    if (!await archivo.exists()) {
      if (hashGuardado != null && hashGuardado.isNotEmpty) {
        // Hubo una licencia y el archivo ya no está. Puede ser un borrado
        // accidental o un intento de "resetear" la prueba; la app no puede
        // distinguirlos, así que lo dice sin acusar a nadie.
        return const EstadoLicencia(
          situacion: SituacionLicencia.invalida,
          detalle: 'No se encuentra el archivo de licencia, pero este equipo '
              'sí tuvo una registrada. Vuelve a importar tu archivo .lic.',
        );
      }
      return const EstadoLicencia(situacion: SituacionLicencia.sinLicencia);
    }

    final Licencia licencia;
    try {
      licencia = await verificarContenido(await archivo.readAsString());
    } on LicenciaInvalidaException catch (e) {
      return EstadoLicencia(
        situacion: SituacionLicencia.invalida,
        detalle: e.motivo,
      );
    }

    return evaluarVigencia(
      licencia,
      mismoEquipo: HuellaEquipo.esMismoEquipo(licencia.huella, await codigoEquipo()),
      relojSospechoso: await _revisarReloj(),
    );
  }

  /// Código de instalación de este equipo, reusando la caché de señales
  /// guardada en `configuracion.equipo_codigo`.
  ///
  /// Evita lanzar `powershell.exe` en cada apertura de la app --entre 300 y
  /// 800 ms en una PC de gama baja-- sin debilitar la verificación: la caché
  /// solo cubre el UUID de SMBIOS y se descarta sola si el MachineGuid cambió.
  /// Ver [HuellaEquipo.senales].
  Future<String> codigoEquipo() async {
    final cache = await _leerColumna('equipo_codigo');
    final senales = await HuellaEquipo.senales(cache: cache);

    final nueva = HuellaEquipo.cacheDe(senales);
    if (nueva.isNotEmpty && nueva != cache) {
      await _guardarColumna('equipo_codigo', nueva);
    }

    return HuellaEquipo.codigoDesde(senales);
  }

  /// Verifica la firma Ed25519 y devuelve la licencia. Público para que el
  /// CLI emisor pueda comprobar lo que acaba de emitir con el mismo código que
  /// corre en el cliente — si emisor y verificador divergen, el error aparece
  /// en la tienda, no en tu máquina.
  Future<Licencia> verificarContenido(String contenido) async {
    if (!activo) {
      throw const LicenciaInvalidaException(
        'Esta compilación no tiene configurada la verificación de licencias.',
      );
    }

    final partes = Licencia.partirArchivo(contenido);

    final valida = await Ed25519().verify(
      partes.payload,
      signature: Signature(
        partes.firma,
        publicKey: SimplePublicKey(
          _clavePublica,
          type: KeyPairType.ed25519,
        ),
      ),
    );

    if (!valida) {
      throw const LicenciaInvalidaException(
        'Esta licencia no es auténtica o fue modificada. Pide el archivo .lic '
        'original a quien te vendió el sistema.',
      );
    }

    final json = jsonDecode(utf8.decode(partes.payload));
    if (json is! Map<String, dynamic>) {
      throw const LicenciaInvalidaException(
        'El contenido de la licencia no es legible.',
      );
    }
    return Licencia.desdeJson(json);
  }

  /// Importa un `.lic` que el cliente recibió: lo verifica, comprueba que sea
  /// de este equipo, lo guarda y recalcula el estado.
  ///
  /// Se verifica **antes** de escribir: importar un archivo malo no debe
  /// sobrescribir la licencia buena que ya estaba.
  Future<EstadoLicencia> importar(String contenido) async {
    final licencia = await verificarContenido(contenido);

    final codigoActual = await codigoEquipo();
    if (!HuellaEquipo.esMismoEquipo(licencia.huella, codigoActual)) {
      throw LicenciaInvalidaException(
        'Esta licencia fue emitida para otra computadora.\n\n'
        'Licencia: ${licencia.huella}\n'
        'Este equipo: $codigoActual\n\n'
        'Manda el código de este equipo a quien te vendió el sistema para que '
        'te emita el archivo correcto.',
      );
    }

    final archivo = File(await rutaArchivo());
    await archivo.writeAsString(contenido.trim());
    await _guardarEnBaseDeDatos(licencia, contenido);

    return cargar();
  }

  /// Ruta del `.lic`, **junto a `pos.db`** y no dentro de la carpeta del
  /// programa: así reinstalar o actualizar Pv Control no la borra, igual que
  /// no borra los datos del negocio.
  Future<String> rutaArchivo() async => p.join(
        p.dirname(await DatabaseHelper().getDatabasePath()),
        nombreArchivo,
      );

  // ------------------------------------------------------ estado en la BD

  /// Guarda en `configuracion` el hash de la licencia y sus datos legibles.
  ///
  /// El hash es la contraparte del archivo: si el `.lic` desaparece pero el
  /// hash sigue ahí, la app sabe que este equipo sí tuvo licencia. Borrar la
  /// base de datos para evadirlo significa perder todas las ventas, el
  /// inventario y los clientes — un precio que nadie paga por saltarse una
  /// mensualidad.
  Future<void> _guardarEnBaseDeDatos(Licencia licencia, String contenido) async {
    try {
      final db = await DatabaseHelper().database;
      final hash = sha256.convert(utf8.encode(contenido.trim())).toString();

      final existe = (await db.query('configuracion', limit: 1)).isNotEmpty;
      final valores = {
        'licencia_hash': hash,
        'edicion': licencia.edicion.clave,
        'licencia_expira': Licencia.soloFecha(licencia.expira),
      };

      if (existe) {
        await db.update('configuracion', valores);
      } else {
        await db.insert('configuracion', {'id': 1, ...valores});
      }
    } catch (e) {
      // Que no se pueda guardar el respaldo del hash no invalida la licencia
      // recién importada: el archivo ya quedó escrito y es la fuente principal.
      debugPrint('Licencia: no se pudo guardar el hash en la base ($e).');
    }
  }

  Future<String?> _leerHashGuardado() => _leerColumna('licencia_hash');

  Future<String?> _leerColumna(String columna) async {
    try {
      final db = await DatabaseHelper().database;
      final filas =
          await db.query('configuracion', columns: [columna], limit: 1);
      if (filas.isEmpty) return null;
      return filas.first[columna] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardarColumna(String columna, String valor) async {
    try {
      final db = await DatabaseHelper().database;
      final existe = (await db.query('configuracion', limit: 1)).isNotEmpty;
      if (existe) {
        await db.update('configuracion', {columna: valor});
      } else {
        await db.insert('configuracion', {'id': 1, columna: valor});
      }
    } catch (_) {
      // Que no se pueda guardar la caché solo cuesta una lectura de más en el
      // próximo arranque. No es motivo para fallar nada.
    }
  }

  /// Guarda el día más avanzado que se ha visto y avisa si el reloj retrocedió.
  ///
  /// Se compara por día y con una tolerancia de dos: un ajuste de zona horaria
  /// o el desfase normal de un reloj sin sincronizar no deben levantar sospecha.
  Future<bool> _revisarReloj() async {
    try {
      final db = await DatabaseHelper().database;
      final filas = await db.query(
        'configuracion',
        columns: ['licencia_reloj'],
        limit: 1,
      );

      final hoy = DateTime.now();
      final guardado = filas.isEmpty
          ? null
          : DateTime.tryParse('${filas.first['licencia_reloj']}');

      final retrocedio =
          guardado != null && hoy.difference(guardado).inDays < -2;

      if (guardado == null || hoy.isAfter(guardado)) {
        if (filas.isEmpty) {
          await db.insert('configuracion', {
            'id': 1,
            'licencia_reloj': hoy.toIso8601String(),
          });
        } else {
          await db.update(
            'configuracion',
            {'licencia_reloj': hoy.toIso8601String()},
          );
        }
      }

      return retrocedio;
    } catch (_) {
      return false;
    }
  }
}
