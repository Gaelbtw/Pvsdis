import '../core/database/database_helper.dart';
import '../core/database/db_exceptions.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/outbox/sync_outbox_writer.dart';
import '../models/cliente_model.dart';
import 'auditoria_controller.dart';

class ClienteController {
  final _auditoriaController = AuditoriaController();
  final _outboxWriter = SyncOutboxWriter(authService: AuthService.instancia);

  Future<int> insertar(Cliente cliente) async {
    final db = await DatabaseHelper().database;
    final id = await _outboxWriter.crear(db, entidad: 'Cliente', tabla: 'Clientes', values: cliente.toMap());

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
      if (cliente.idCliente != null) {
        await _outboxWriter.actualizar(db, entidad: 'Cliente', tabla: 'Clientes', idLocal: cliente.idCliente!);
      }
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

    final rows = await ejecutarConMensajeDeIntegridad(
      () => db.delete(
        'Clientes',
        where: 'id_cliente = ?',
        whereArgs: [id],
      ),
      'No se puede eliminar: el cliente tiene ventas o pedidos registrados.',
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
