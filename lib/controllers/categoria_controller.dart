import '../core/database/database_helper.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/outbox/sync_outbox_writer.dart';
import '../models/categoria_model.dart';

class CategoriaController {
  final _outboxWriter = SyncOutboxWriter(authService: AuthService.instancia);

  Future<int> insertar(Categoria categoria) async {
    final db = await DatabaseHelper().database;
    return await _outboxWriter.crear(db, entidad: 'CategoriaProducto', tabla: 'Categorias', values: categoria.toMap());
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

    final rows = await db.update(
      'Categorias',
      categoria.toMap(),
      where: 'id_categoria = ?',
      whereArgs: [categoria.idCategoria],
    );

    if (rows > 0 && categoria.idCategoria != null) {
      await _outboxWriter.actualizar(db, entidad: 'CategoriaProducto', tabla: 'Categorias', idLocal: categoria.idCategoria!);
    }

    return rows;
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
