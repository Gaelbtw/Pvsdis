import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../models/configuracion_model.dart';

class ConfiguracionService {
  Future<Configuracion> obtener() async {
    final db = await DatabaseHelper().database;

    final res = await db.query("configuracion");

    if (res.isEmpty) {
      final defaultConfig = Configuracion.porDefecto();

      await db.insert("configuracion", {
        ...defaultConfig.toMap(),
        "id": 1,
      });

      return defaultConfig;
    }

    return Configuracion.fromMap(res.first);
  }

  Future<void> guardar(Configuracion config) async {
    final db = await DatabaseHelper().database;

    await db.insert(
      "configuracion",
      {
        ...config.toMap(),
        "id": 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
