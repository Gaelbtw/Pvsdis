import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../controllers/database_backup_controller.dart';
import '../core/config/app_config.dart';
import '../core/config/app_info.dart';
import '../core/database/database_helper.dart';
import '../core/sync/network/sync_prefs_store.dart';
import '../core/sync/outbox/sync_outbox_deadletter.dart';

/// Genera el reporte de diagnóstico que el cliente manda por WhatsApp cuando
/// algo no funciona.
///
/// Sustituye media hora de "¿y qué te dice exactamente?" por una llamada. A
/// escala de varios negocios instalados es la mejora de soporte con mejor
/// retorno que se puede construir: sin esto, cada incidencia empieza pidiéndole
/// a alguien que no es técnico que describa por teléfono un estado que no sabe
/// leer.
///
/// **Qué NO lleva, a propósito:** ni un solo dato de clientes, productos,
/// precios o ventas. Solo conteos, rutas, versiones y estado del sistema. El
/// cliente tiene que poder mandarlo sin pensárselo dos veces, y el archivo
/// acaba en un chat de WhatsApp que no controla nadie.
///
/// Se genera como .txt y no como ZIP a propósito: se puede leer en el mismo
/// chat, sin descargar ni descomprimir nada, y no obliga a sumar una
/// dependencia de compresión.
class SoporteService {
  final _dbHelper = DatabaseHelper();
  final _backups = DatabaseBackupController();

  /// Escribe el reporte en la carpeta de exportaciones y devuelve su ruta.
  Future<String> generar() async {
    final texto = await construirTexto();

    final dir = Directory(await _dbHelper.getExportDirectoryPath());
    if (!await dir.exists()) await dir.create(recursive: true);

    final ahora = DateTime.now();
    final marca = '${ahora.year}'
        '${_dosDigitos(ahora.month)}${_dosDigitos(ahora.day)}_'
        '${_dosDigitos(ahora.hour)}${_dosDigitos(ahora.minute)}';
    final ruta = p.join(dir.path, 'soporte_$marca.txt');

    await File(ruta).writeAsString(texto);
    return ruta;
  }

  /// Arma el contenido del reporte. Separado de [generar] para poder probarlo
  /// sin escribir en disco.
  ///
  /// Cada bloque va en su propio try/catch: que el outbox no se pueda leer no
  /// es razón para quedarse sin el resto del diagnóstico. Un reporte parcial
  /// sirve; uno que revienta a la mitad, no.
  Future<String> construirTexto() async {
    final b = StringBuffer();

    b.writeln('=' * 68);
    b.writeln('  PV CONTROL - REPORTE DE SOPORTE');
    b.writeln('  Generado: ${_fecha(DateTime.now())}');
    b.writeln('=' * 68);
    b.writeln();
    b.writeln('Este archivo NO contiene datos de clientes, productos ni ventas.');
    b.writeln('Solo versiones, rutas, conteos y estado del sistema.');
    b.writeln();

    await _bloque(b, 'NEGOCIO Y VERSIÓN', () async {
      final cfg = AppConfig.actual;
      b.writeln('Negocio          : ${cfg.nombreNegocio}');
      b.writeln('Versión de la app: ${AppInfo.versionCompleta}');
      b.writeln('Esquema de datos : v${AppInfo.versionEsquema}');
      b.writeln('Sistema          : ${Platform.operatingSystemVersion}');
      b.writeln('Equipo           : ${Platform.localHostname}');
    });

    await _bloque(b, 'BASE DE DATOS', () async {
      final ruta = await _dbHelper.getDatabasePath();
      final archivo = File(ruta);
      b.writeln('Ruta   : $ruta');
      if (await archivo.exists()) {
        final stat = await archivo.stat();
        b.writeln('Tamaño : ${_mb(stat.size)}');
        b.writeln('Modificada: ${_fecha(stat.modified)}');
      } else {
        b.writeln('Tamaño : EL ARCHIVO NO EXISTE');
      }

      final db = await _dbHelper.database;
      b.writeln('Versión del archivo: v${await db.getVersion()}');
      if (await db.getVersion() != AppInfo.versionEsquema) {
        b.writeln('  >> ATENCIÓN: no coincide con el esquema de la app.');
      }
    });

    await _bloque(b, 'RESPALDOS', () async {
      final locales = await _backups.obtenerBackups();
      b.writeln('Respaldos locales : ${locales.length}');
      if (locales.isNotEmpty) {
        final ultimo = locales.first;
        b.writeln('  Más reciente    : ${ultimo.backupFileName}');
        b.writeln('  Fecha           : ${_fecha(ultimo.modifiedAt)}'
            ' (hace ${_diasDesde(ultimo.modifiedAt)})');
        b.writeln('  Tamaño          : ${_mb(ultimo.size)}');
      }

      final externo = await _backups.ultimoRespaldoExterno();
      if (externo == null) {
        b.writeln('Respaldo externo  : NUNCA SE HA EJECUTADO');
        b.writeln('  >> El respaldo automático a USB no está configurado, o');
        b.writeln('     nunca ha corrido correctamente.');
      } else {
        b.writeln('Respaldo externo  : ${_fecha(externo.fecha)}'
            ' (hace ${_diasDesde(externo.fecha)})');
        b.writeln('  Destino         : ${externo.destino}');
        if (externo.estaAtrasado) {
          b.writeln('  >> ATENCIÓN: lleva más de'
              ' ${DatabaseBackupController.diasParaAvisoRespaldo} días sin correr.');
          b.writeln('     Probablemente la unidad externa está desconectada.');
        }
      }
    });

    await _bloque(b, 'SINCRONIZACIÓN', () async {
      final url = await SyncPrefsStore().leerUrlBackend();
      if (url == null) {
        b.writeln('No configurada. El equipo trabaja 100% local (es lo normal');
        b.writeln('en una instalación de una sola sucursal).');
        return;
      }

      b.writeln('Servidor : $url');

      final db = await _dbHelper.database;
      const dl = SyncOutboxDeadLetter.intentosFallidaPermanente;

      final pendientes = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM Sync_Outbox WHERE intentos > ?',
            [dl],
          )) ??
          0;
      final fallidas = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM Sync_Outbox WHERE intentos = ?',
            [dl],
          )) ??
          0;

      b.writeln('Cambios por subir     : $pendientes');
      b.writeln('Cambios rechazados    : $fallidas');

      if (fallidas > 0) {
        b.writeln();
        b.writeln('Detalle de los rechazados (sin el contenido del cambio):');
        final filas = await db.query(
          'Sync_Outbox',
          columns: ['entidad', 'operacion', 'intentos', 'ultimo_error'],
          where: 'intentos = ?',
          whereArgs: [dl],
          orderBy: 'id ASC',
          limit: 15,
        );
        for (final f in filas) {
          final error = (f['ultimo_error'] as String?) ?? 'sin mensaje';
          b.writeln('  - ${f['entidad']} / ${f['operacion']}'
              ' -> ${_recortar(error, 110)}');
        }
      }
    });

    await _bloque(b, 'CONFIGURACIÓN DE OPERACIÓN', () async {
      final c = AppConfig.actual;
      b.writeln('Papel del ticket     : ${c.tamanoPapel}');
      b.writeln('Impresora            : ${c.impresoraNombre ?? "ninguna seleccionada"}');
      b.writeln('Impresión directa    : ${_siNo(c.autoImprimirTicket)}');
      b.writeln('Abrir cajón          : ${_siNo(c.abrirCajonEfectivo)}'
          '${c.abrirCajonEfectivo ? " (puerto: ${c.cajonPuerto ?? "por impresora"})" : ""}');
      b.writeln('Moneda               : ${c.simboloMoneda}');
      b.writeln('IVA                  : ${c.tasaImpuestoPorcentaje}%'
          ' (desglosado: ${_siNo(c.mostrarIvaDesglosado)})');
    });

    await _bloque(b, 'VOLUMEN DE DATOS (solo conteos)', () async {
      final db = await _dbHelper.database;
      const tablas = {
        'Productos': 'Producto',
        'Categorías': 'Categorias',
        'Clientes': 'Clientes',
        'Proveedores': 'Proveedores',
        'Usuarios': 'Usuarios',
        'Ventas': 'Ventas',
        'Cajas': 'Cajas',
        'Devoluciones': 'Devoluciones',
        'Apartados': 'Apartados',
        'Registros de actividad': 'Auditorias',
      };

      for (final entry in tablas.entries) {
        b.writeln('${entry.key.padRight(23)}: ${await _contar(db, entry.value)}');
      }

      final hace30 = DateTime.now().subtract(const Duration(days: 30));
      final recientes = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM Ventas WHERE fecha >= ?',
            [hace30.toIso8601String()],
          )) ??
          0;
      b.writeln('${"Ventas últimos 30 días".padRight(23)}: $recientes');
    });

    b.writeln();
    b.writeln('=' * 68);
    b.writeln('  Fin del reporte');
    b.writeln('=' * 68);

    return b.toString();
  }

  // ------------------------------------------------------------- utilidades

  /// Escribe un bloque con encabezado. Si el contenido revienta, lo anota y
  /// sigue con el siguiente en vez de tumbar el reporte entero.
  Future<void> _bloque(
    StringBuffer b,
    String titulo,
    Future<void> Function() contenido,
  ) async {
    b.writeln('-' * 68);
    b.writeln('  $titulo');
    b.writeln('-' * 68);
    try {
      await contenido();
    } catch (e) {
      b.writeln('No se pudo leer esta sección: $e');
    }
    b.writeln();
  }

  Future<String> _contar(DatabaseExecutor db, String tabla) async {
    try {
      final n = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tabla'),
      );
      return '${n ?? 0}';
    } catch (_) {
      // La tabla puede no existir en una instalación vieja a medio migrar,
      // que es justo el caso que este reporte tiene que poder describir.
      return 'tabla no disponible';
    }
  }

  static String _dosDigitos(int n) => n.toString().padLeft(2, '0');

  static String _fecha(DateTime d) =>
      '${d.year}-${_dosDigitos(d.month)}-${_dosDigitos(d.day)} '
      '${_dosDigitos(d.hour)}:${_dosDigitos(d.minute)}';

  static String _diasDesde(DateTime d) {
    final dias = DateTime.now().difference(d).inDays;
    if (dias == 0) return 'hoy';
    if (dias == 1) return '1 día';
    return '$dias días';
  }

  static String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

  static String _siNo(bool v) => v ? 'sí' : 'no';

  static String _recortar(String s, int max) {
    final limpio = s.replaceAll('\n', ' ').trim();
    return limpio.length <= max ? limpio : '${limpio.substring(0, max)}...';
  }
}
