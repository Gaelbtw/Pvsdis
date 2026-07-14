import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../models/database_backup_model.dart';
import 'auditoria_controller.dart';

class DatabaseBackupController {
  final _databaseHelper = DatabaseHelper();
  final _auditoriaController = AuditoriaController();

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
