import '../core/database/database_helper.dart';
import '../models/cliente_model.dart';
import 'auditoria_controller.dart';

class ClienteController {
  final _auditoriaController = AuditoriaController();

  Future<int> insertar(Cliente cliente) async {
    final db = await DatabaseHelper().database;
    final id = await db.insert('Clientes', cliente.toMap());

    await _auditoriaController.registrar(
      tabla: 'Clientes',
      accion: 'CREATE',
      idRegistro: id,
      descripcion: 'Cliente ${cliente.nombre} creado',
    );

    return id;
  }

  Future<List<Cliente>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query(
      'Clientes',
      orderBy: 'nombre ASC',
    );

    return result.map((e) => Cliente.fromMap(e)).toList();
  }

  Future<Cliente?> obtenerPorId(int id) async {
    final db = await DatabaseHelper().database;

    final result = await db.query(
      'Clientes',
      where: 'id_cliente = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) {
      return Cliente.fromMap(result.first);
    }
    return null;
  }

  Future<List<Cliente>> buscar(String query) async {
    final db = await DatabaseHelper().database;

    final result = await db.query(
      'Clientes',
      where: 'nombre Like ?',
      whereArgs: ['%$query%'],
    );

    return result.map((e) => Cliente.fromMap(e)).toList();
  }

  Future<int> actualizar(Cliente cliente) async {
    final db = await DatabaseHelper().database;

    final rows = await db.update(
      'Clientes',
      cliente.toMap(),
      where: 'id_cliente = ?',
      whereArgs: [cliente.idCliente],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Clientes',
        accion: 'EDIT',
        idRegistro: cliente.idCliente,
        descripcion: 'Cliente ${cliente.nombre} actualizado',
      );
    }

    return rows;
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;
    final cliente = await db.query(
      'Clientes',
      columns: ['nombre'],
      where: 'id_cliente = ?',
      whereArgs: [id],
      limit: 1,
    );

    final rows = await db.delete(
      'Clientes',
      where: 'id_cliente = ?',
      whereArgs: [id],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Clientes',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: cliente.isNotEmpty
            ? 'Cliente ${cliente.first["nombre"]} eliminado'
            : 'Cliente eliminado',
      );
    }

    return rows;
  }
}
