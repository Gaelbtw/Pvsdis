import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../models/database_backup_model.dart';
import 'auditoria_controller.dart';

/// Última corrida exitosa del respaldo automático a unidad externa, según el
/// marcador que deja `windows/installer/usb/respaldo.ps1`.
///
/// La app no puede comprobar por sí sola si el respaldo externo corrió: la
/// tarea programada vive en Windows, escribe en una unidad que puede estar
/// desconectada, y no hay forma de saber desde aquí a qué carpeta apunta. Por
/// eso el script deja un archivito junto a `pos.db` cada vez que termina bien,
/// y la app solo lo lee.
class RespaldoExterno {
  const RespaldoExterno({required this.fecha, required this.destino});

  final DateTime fecha;
  final String destino;

  int get diasDesde => DateTime.now().difference(fecha).inDays;

  bool get estaAtrasado =>
      diasDesde > DatabaseBackupController.diasParaAvisoRespaldo;
}

class DatabaseBackupController {
  final _databaseHelper = DatabaseHelper();
  final _auditoriaController = AuditoriaController();

  /// A partir de cuántos días sin respaldo externo se avisa en pantalla.
  ///
  /// Tres y no siete: lo que falla en la práctica no es el script, es que
  /// alguien desconectó la USB para pasar fotos y no la volvió a conectar. A
  /// los siete días ya se perdió una semana de ventas si el disco muere. Un
  /// respaldo que falla en silencio es peor que no tener respaldo, porque
  /// quita la preocupación sin quitar el riesgo.
  static const int diasParaAvisoRespaldo = 3;

  /// Marcador que escribe `respaldo.ps1` al terminar bien. Vive junto a
  /// `pos.db` (no dentro de `backups/`) para que un borrado de respaldos
  /// locales no lo arrastre.
  static const _archivoMarcadorExterno = 'ultimo_respaldo_externo.txt';

  Future<List<DatabaseBackup>> obtenerBackups() async {
    final backupDir = Directory(await _databaseHelper.getBackupDirectoryPath());

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
      return [];
    }

    final files = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.db'))
        .toList()
      ..sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

    return files.map((file) {
      final stat = file.statSync();
      return DatabaseBackup(
        backupFileName: path.basename(file.path),
        path: file.path,
        modifiedAt: stat.modified,
        size: stat.size,
      );
    }).toList();
  }

  /// Lee el marcador del respaldo automático a unidad externa. Devuelve `null`
  /// si nunca ha corrido (o si el archivo está ilegible, que para el usuario
  /// significa lo mismo: no hay evidencia de que exista un respaldo fuera del
  /// equipo).
  Future<RespaldoExterno?> ultimoRespaldoExterno() async {
    try {
      final carpeta = path.dirname(await _databaseHelper.getDatabasePath());
      final marcador = File(path.join(carpeta, _archivoMarcadorExterno));
      if (!await marcador.exists()) return null;

      DateTime? fecha;
      var destino = 'desconocido';

      // `Set-Content -Encoding UTF8` de Windows PowerShell 5.1 escribe BOM.
      // Sin quitarlo, la primera clave se leería como '\uFEFFfecha' y el
      // marcador se ignoraría en silencio -- justo el fallo mudo que este
      // aviso existe para evitar.
      final contenido =
          (await marcador.readAsString()).replaceFirst('\uFEFF', '');

      for (final linea in const LineSplitter().convert(contenido)) {
        final corte = linea.indexOf('=');
        if (corte <= 0) continue;
        final clave = linea.substring(0, corte).trim().toLowerCase();
        final valor = linea.substring(corte + 1).trim();
        if (clave == 'fecha') fecha = DateTime.tryParse(valor);
        if (clave == 'destino' && valor.isNotEmpty) destino = valor;
      }

      if (fecha == null) return null;
      return RespaldoExterno(fecha: fecha, destino: destino);
    } catch (_) {
      return null;
    }
  }

  Future<DatabaseBackup> crearBackup() async {
    final databasePath = await _databaseHelper.getDatabasePath();
    final backupDir = Directory(await _databaseHelper.getBackupDirectoryPath());

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    await _databaseHelper.closeDatabase();

    final timestamp = _timestamp(DateTime.now());
    final backupPath = path.join(backupDir.path, '${timestamp}_Backup.db');
    final backupFile = await File(databasePath).copy(backupPath);

    await _databaseHelper.database;

    await _auditoriaController.registrar(
      tabla: 'Base de datos',
      accion: 'CREATE',
      descripcion: 'Backup generado: ${path.basename(backupPath)}',
      usuario: SessionManager.currentUserName,
    );

    final stat = await backupFile.stat();
    return DatabaseBackup(
      backupFileName: path.basename(backupPath),
      path: backupPath,
      modifiedAt: stat.modified,
      size: stat.size,
    );
  }

  /// Copia [backup] a [carpetaDestino] (una memoria USB, un disco externo o
  /// una carpeta de red) y devuelve la ruta del archivo copiado.
  ///
  /// Existe porque un respaldo guardado en el mismo disco que la base de datos
  /// no protege del caso que más se lleva negocios por delante: que ese disco
  /// (o el equipo entero) se pierda. Sacar la copia del equipo es lo que
  /// convierte el respaldo en respaldo de verdad.
  ///
  /// Si en el destino ya existe un archivo con ese nombre se le agrega un
  /// sufijo en vez de sobrescribirlo: quien conecta el USB no siempre sabe qué
  /// hay dentro, y perder un respaldo anterior por una copia nueva sería el
  /// tipo de error que este método existe para evitar.
  Future<String> copiarBackupA(DatabaseBackup backup, String carpetaDestino) async {
    final origen = File(backup.path);
    if (!await origen.exists()) {
      throw Exception('El archivo del respaldo ya no existe.');
    }

    final destinoDir = Directory(carpetaDestino);
    if (!await destinoDir.exists()) {
      throw Exception('La carpeta de destino no está disponible. Revisa que la memoria siga conectada.');
    }

    var destino = path.join(carpetaDestino, backup.backupFileName);
    var intento = 1;
    while (await File(destino).exists()) {
      final sinExtension = path.basenameWithoutExtension(backup.backupFileName);
      final extension = path.extension(backup.backupFileName);
      destino = path.join(carpetaDestino, '$sinExtension($intento)$extension');
      intento++;
    }

    await origen.copy(destino);

    await _auditoriaController.registrar(
      tabla: 'Base de datos',
      accion: 'CREATE',
      descripcion: 'Respaldo copiado a almacenamiento externo: $destino',
      usuario: SessionManager.currentUserName,
    );

    return destino;
  }

  Future<void> restaurarBackup(DatabaseBackup backup) async {
    final databasePath = await _databaseHelper.getDatabasePath();

    await _databaseHelper.closeDatabase();

    // Eliminar archivos WAL/SHM para que SQLite no aplique el journal
    // de la BD anterior sobre el backup recién copiado
    final walFile = File('$databasePath-wal');
    final shmFile = File('$databasePath-shm');
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();

    await File(backup.path).copy(databasePath);
    await _databaseHelper.database;

    await _auditoriaController.registrar(
      tabla: 'Base de datos',
      accion: 'EDIT',
      descripcion: 'Restore aplicado desde ${backup.backupFileName}',
      usuario: SessionManager.currentUserName,
    );
  }

  String _timestamp(DateTime value) {
    final year = value.year.toString();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');

    return '$year$month$day$hour$minute$second';
  }
}
