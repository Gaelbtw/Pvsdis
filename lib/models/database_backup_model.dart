class DatabaseBackup {
  final String backupFileName;
  final String path;
  final DateTime modifiedAt;
  final int size;

  DatabaseBackup({
    required this.backupFileName,
    required this.path,
    required this.modifiedAt,
    required this.size,
  });
}
