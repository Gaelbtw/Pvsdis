import '../core/database/database_helper.dart';
import '../models/categoria_model.dart';

class CategoriaController {

  Future<int> insertar(Categoria categoria) async {
    final db = await DatabaseHelper().database;
    return await db.insert('Categorias', categoria.toMap());
  }

  Future<List<Categoria>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query(
      'Categorias',
      orderBy: 'nombre ASC', 
      );

    return result.map((e) => Categoria.fromMap(e)).toList();
  }

  Future<Categoria?> obtenerPorId(int id) async {
    final db = await DatabaseHelper().database;

    final result = await db.query (
      'Categorias',
      whereArgs: [id], 
    );

    if(result.isNotEmpty) {
      return Categoria.fromMap(result.first);
    }
    return null; 
  }

  Future<List<Categoria>> buscar (String query) async {
    final db = await DatabaseHelper().database;

    final result = await db.query (
      'Categorias',
      where: 'nombre Like ?',
      whereArgs: ['%$query%'],
    );

    return result.map((e) => Categoria.fromMap(e)).toList();
  }

  Future<int> actualizar(Categoria categoria) async {
    final db = await DatabaseHelper().database;

    return await db.update(
      'Categorias',
      categoria.toMap(),
      where: 'id_categoria = ?',
      whereArgs: [categoria.idCategoria],
    );
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;

    return await db.delete(
      'Categorias',
      where: 'id_categoria = ?',
      whereArgs: [id],
    );
  }
}
