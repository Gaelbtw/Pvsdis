// Pruebas del motivo en los ajustes manuales de inventario.
//
// Antes todo ajuste manual quedaba con el texto fijo "Ajuste manual de stock",
// así que en la bitácora una merma y un error de captura eran indistinguibles.
// Lo que se verifica aquí es que el motivo elegido llegue a las DOS bitácoras
// (movimientos de inventario y auditoría), porque cada una responde una
// pregunta distinta y las dos se consultan.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/producto_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/motivo_ajuste_inventario.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late ProductoController controller;
  late int idProducto;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_motivo_ajuste_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = ProductoController();

    SessionManager.setUser(id: 1, nombre: 'Sistema', rol: 'Admin');

    idProducto = await controller.insertar(
      const Producto(nombre: 'Vaso', descripcion: '', precio: 25, sku: 'VAS-1'),
      10,
    );
  });

  tearDown(() async {
    SessionManager.clear();
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<List<Map<String, Object?>>> movimientosDeAjuste() => db.query(
        'Movimiento_Inventario',
        where: "tipo_movimiento IN ('AjustePositivo','AjusteNegativo') AND motivo != ?",
        whereArgs: ['Alta de producto'],
        orderBy: 'id_movimiento',
      );

  test('bajar la existencia por merma queda registrado como merma', () async {
    await controller.actualizarStock(
      idProducto,
      7,
      motivo: MotivoAjusteInventario.merma,
    );

    final movimiento = (await movimientosDeAjuste()).single;
    expect(movimiento['tipo_movimiento'], 'AjusteNegativo');
    expect(movimiento['cantidad'], 3);
    expect(movimiento['cantidad_anterior'], 10);
    expect(movimiento['cantidad_nueva'], 7);
    expect(movimiento['motivo'], MotivoAjusteInventario.merma.etiqueta);

    final auditoria = (await db.query(
      'Auditorias',
      where: 'tabla = ?',
      whereArgs: ['Inventario'],
      orderBy: 'id_auditoria DESC',
    ))
        .first;
    expect(auditoria['descripcion'].toString(), contains('Merma'));
  });

  test('el motivo por defecto de un ajuste es el conteo físico', () async {
    await controller.actualizarStock(idProducto, 12);

    final movimiento = (await movimientosDeAjuste()).single;
    expect(movimiento['motivo'], MotivoAjusteInventario.conteoFisico.etiqueta);
  });

  test('una entrada rápida se registra como entrada de mercancía', () async {
    await controller.agregarStock(idProducto, 5);

    final movimiento = (await movimientosDeAjuste()).single;
    expect(movimiento['tipo_movimiento'], 'AjustePositivo');
    expect(movimiento['cantidad'], 5);
    expect(movimiento['motivo'], MotivoAjusteInventario.entradaMercancia.etiqueta);
  });

  test('una entrada puede registrarse con otro motivo, como una cortesía', () async {
    await controller.agregarStock(
      idProducto,
      2,
      motivo: MotivoAjusteInventario.regalo,
    );

    final movimiento = (await movimientosDeAjuste()).single;
    expect(movimiento['motivo'], MotivoAjusteInventario.regalo.etiqueta);
  });

  test('fijar la misma cantidad no inventa un movimiento', () async {
    await controller.actualizarStock(idProducto, 10);

    expect(await movimientosDeAjuste(), isEmpty);
  });

  test('las etiquetas se pueden resolver de vuelta desde la bitácora', () {
    expect(
      MotivoAjusteInventario.porEtiqueta(MotivoAjusteInventario.merma.etiqueta),
      MotivoAjusteInventario.merma,
    );
    expect(MotivoAjusteInventario.porEtiqueta('Ajuste manual de stock'), isNull);
    expect(MotivoAjusteInventario.porEtiqueta(null), isNull);
  });
}
