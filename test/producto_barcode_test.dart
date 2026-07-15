// Pruebas de duplicados, búsqueda y normalización de código de barras,
// ejercitando ProductoController tal como lo usan las vistas reales
// (redirigiendo el singleton de DatabaseHelper hacia una base temporal).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/producto_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/models/producto_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late ProductoController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_barcode_test');
    final path = join(tempDir.path, 'test.db');
    final db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = ProductoController();
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('normalización de código de barras', () {
    test('cadena vacía y solo espacios se normalizan a null', () {
      expect(Producto.normalizarCodigoBarras(''), isNull);
      expect(Producto.normalizarCodigoBarras('   '), isNull);
      expect(Producto.normalizarCodigoBarras(null), isNull);
    });

    test('recorta espacios alrededor de un código válido', () {
      expect(Producto.normalizarCodigoBarras('  7501234567890  '), '7501234567890');
    });
  });

  group('unicidad', () {
    test('permite insertar varios productos sin código de barras', () async {
      await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, codigoBarras: ''),
        5,
      );
      await controller.insertar(
        const Producto(nombre: 'B', descripcion: '', precio: 10, codigoBarras: null),
        5,
      );

      final todos = await controller.obtenerTodos();
      expect(todos, hasLength(2));
      expect(todos.every((p) => p.codigoBarras == null), isTrue);
    });

    test('rechaza un código de barras duplicado con mensaje claro', () async {
      await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, codigoBarras: '111'),
        5,
      );

      expect(
        () => controller.insertar(
          const Producto(nombre: 'B', descripcion: '', precio: 10, codigoBarras: '111'),
          5,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensaje',
            contains('código de barras'),
          ),
        ),
      );
    });

    test('existeCodigoBarras excluye el propio producto al editar', () async {
      final id = await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, codigoBarras: '222'),
        5,
      );

      expect(await controller.existeCodigoBarras('222'), isTrue);
      expect(await controller.existeCodigoBarras('222', excluirId: id), isFalse);
      expect(await controller.existeCodigoBarras('999'), isFalse);
    });

    test('actualizar con el código de otro producto lanza mensaje de duplicado', () async {
      await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, codigoBarras: '333'),
        5,
      );
      final idB = await controller.insertar(
        const Producto(nombre: 'B', descripcion: '', precio: 10, codigoBarras: '444'),
        5,
      );

      expect(
        () => controller.actualizar(
          Producto(idProducto: idB, nombre: 'B', descripcion: '', precio: 10, codigoBarras: '333'),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensaje',
            contains('código de barras'),
          ),
        ),
      );
    });
  });

  group('búsqueda por código de barras', () {
    test('buscarPorCodigoBarras encuentra coincidencia exacta', () async {
      await controller.insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 18.5, codigoBarras: '7501234567890'),
        20,
      );

      final encontrado = await controller.buscarPorCodigoBarras('7501234567890');
      expect(encontrado, isNotNull);
      expect(encontrado!.nombre, 'Refresco');
    });

    test('buscarPorCodigoBarras devuelve null si no hay coincidencia', () async {
      final encontrado = await controller.buscarPorCodigoBarras('no-existe');
      expect(encontrado, isNull);
    });

    test('obtenerConStock incluye el código de barras', () async {
      await controller.insertar(
        const Producto(nombre: 'Refresco', descripcion: '', precio: 18.5, codigoBarras: '555'),
        20,
      );

      final filas = await controller.obtenerConStock();
      expect(filas.first['codigo_barras'], '555');
    });
  });
}
