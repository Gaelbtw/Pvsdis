import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/database/db_exceptions.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/outbox/sync_outbox_writer.dart';
import '../models/proveedores_model.dart';
import 'auditoria_controller.dart';

class ProveedorController {
  final _auditoriaController = AuditoriaController();
  final _outboxWriter = SyncOutboxWriter(authService: AuthService.instancia);

  Future<int> insertar(Proveedores proveedor) async {
    final db = await DatabaseHelper().database;

    final data = proveedor.toMap();

    // 🔥 QUITAR ID SI ES NULL (CLAVE)
    data.remove('id_proveedor');

    final result = await _outboxWriter.crear(
      db,
      entidad: 'Proveedor',
      tabla: 'Proveedores',
      values: data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _auditoriaController.registrar(
      tabla: 'Proveedores',
      accion: 'CREATE',
      idRegistro: result,
      descripcion: 'Proveedor ${proveedor.nombre} creado',
    );

    return result;
  }

  Future<List<Proveedores>> obtenerTodos() async {
    final db = await DatabaseHelper().database;
    final result = await db.query('Proveedores');

    return result.map((e) => Proveedores.fromMap(e)).toList();
  }

  Future<int> actualizar(Proveedores proveedor) async {
    final db = await DatabaseHelper().database;

    final rows = await db.update(
      'Proveedores',
      proveedor.toMap(),
      where: 'id_proveedor = ?',
      whereArgs: [proveedor.idProveedor],
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Proveedores',
        accion: 'EDIT',
        idRegistro: proveedor.idProveedor,
        descripcion: 'Proveedor ${proveedor.nombre} actualizado',
      );
      if (proveedor.idProveedor != null) {
        await _outboxWriter.actualizar(db, entidad: 'Proveedor', tabla: 'Proveedores', idLocal: proveedor.idProveedor!);
      }
    }

    return rows;
  }

  Future<int> eliminar(int id) async {
    final db = await DatabaseHelper().database;
    final proveedor = await db.query(
      'Proveedores',
      columns: ['nombre'],
      where: 'id_proveedor = ?',
      whereArgs: [id],
      limit: 1,
    );

    final rows = await ejecutarConMensajeDeIntegridad(
      () => db.delete(
        'Proveedores',
        where: 'id_proveedor = ?',
        whereArgs: [id],
      ),
      'No se puede eliminar: el proveedor tiene compras registradas.',
    );

    if (rows > 0) {
      await _auditoriaController.registrar(
        tabla: 'Proveedores',
        accion: 'DELETE',
        idRegistro: id,
        descripcion: proveedor.isNotEmpty
            ? 'Proveedor ${proveedor.first["nombre"]} eliminado'
            : 'Proveedor eliminado',
      );
    }

    return rows;
  }
}
