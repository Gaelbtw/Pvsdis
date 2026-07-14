import '../core/database/database_helper.dart';
import '../models/inventario_model.dart';

class InventarioController {

  Future<int> insertar(Inventario inventario) async {
    final db = await DatabaseHelper().database;
    return await db.insert('Inventario', inventario.toMap());
  }

  Future<List<Inventario>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query('Inventario');

    return result.map((e) => Inventario.fromMap(e)).toList();
  }

  Future<int> actualizar(Inventario inventario) async {
    final db = await DatabaseHelper().database;

    return await db.update(
      'Inventario',
      inventario.toMap(),
      where: 'id_inventario = ?',
      whereArgs: [inventario.idInventario],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;

    return await db.delete(
      'Inventario',
      where: 'id_inventario = ?',
      whereArgs: [id],
    );
  }
}
