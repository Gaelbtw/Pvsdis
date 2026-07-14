import '../models/configuracion_model.dart';
import '../core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';
class ConfiguracionService {

  Future<Configuracion> obtener() async {
    final db = await DatabaseHelper().database;

    final res = await db.query("configuracion");

    print("FILAS CONFIG: $res"); // 👈 DEBUG

    if (res.isEmpty) {
      // 🔥 crear config por defecto
      final defaultConfig = Configuracion(
        horaInicioMatutino: "07:00",
        horaFinMatutino: "14:00",
        horaInicioVespertino: "14:00",
        horaFinVespertino: "21:00",
        stockMinimo: 5,
        fondoCaja: 500,
      );

      await db.insert("configuracion", {
        ...defaultConfig.toMap(),
        "id": 1,
      });

      return defaultConfig;
    }

    // 🔥 SIEMPRE AGARRA LA PRIMERA
    return Configuracion.fromMap(res.first);
  }

  Future<void> guardar(Configuracion config) async {
    final db = await DatabaseHelper().database;

    // 🔥 REEMPLAZAR SIEMPRE
    await db.insert(
      "configuracion",
      {
        ...config.toMap(),
        "id": 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print("CONFIG GUARDADA");
  }
}