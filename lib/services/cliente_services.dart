import '../core/database/database_helper.dart';
import '../models/cliente_model.dart';

class ClienteService {

  final dbHelper = DatabaseHelper();

  Future<List<Cliente>> obtenerTodos() async {

    final db = await dbHelper.database;

    final res = await db.query(
      'Clientes',
      orderBy: 'nombre ASC',
    );

    return res.map((e) => Cliente.fromMap(e)).toList();
  }
}