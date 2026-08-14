// Pruebas de la clave interna (SKU), el IVA por producto y el margen.
//
// El SKU se comporta como el código de barras (opcional, único, normalizado)
// pero es una columna distinta: son dos identificadores con dueños distintos
// —el fabricante y el negocio— y confundirlos era justo el problema.
//
// El IVA por producto usa `null` para decir "usa la tasa general", así que lo
// importante a verificar es que ese null NO se confunda con 0% (exento).
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
    tempDir = Directory.systemTemp.createTempSync('pvapp_sku_iva_test');
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

  group('normalización', () {
    test('SKU vacío o de solo espacios se guarda como null', () {
      expect(Producto.normalizarSku(''), isNull);
      expect(Producto.normalizarSku('   '), isNull);
      expect(Producto.normalizarSku(null), isNull);
      expect(Producto.normalizarSku('  ABC-1  '), 'ABC-1');
    });

    test('SKU conserva mayúsculas y minúsculas tal como se capturaron', () {
      expect(Producto.normalizarSku('a-100'), 'a-100');
      expect(Producto.normalizarSku('A-100'), 'A-100');
    });

    test('IVA acepta porcentaje con o sin signo, y descarta lo inválido', () {
      expect(Producto.normalizarIvaTasa('16'), 16);
      expect(Producto.normalizarIvaTasa('16%'), 16);
      expect(Producto.normalizarIvaTasa(' 8.5 '), 8.5);
      expect(Producto.normalizarIvaTasa('0'), 0);
      expect(Producto.normalizarIvaTasa(''), isNull);
      expect(Producto.normalizarIvaTasa('abc'), isNull);
      expect(Producto.normalizarIvaTasa('-5'), isNull);
      expect(Producto.normalizarIvaTasa('120'), isNull);
    });
  });

  group('IVA efectivo', () {
    test('sin tasa propia usa la general', () {
      const p = Producto(nombre: 'A', descripcion: '', precio: 10);
      expect(p.ivaEfectivo(16), 16);
    });

    test('una tasa propia de 0% NO cae a la general: es un producto exento', () {
      const p = Producto(nombre: 'Leche', descripcion: '', precio: 10, ivaTasa: 0);
      expect(p.ivaEfectivo(16), 0);
    });

    test('la tasa propia gana sobre la general', () {
      const p = Producto(nombre: 'A', descripcion: '', precio: 10, ivaTasa: 8);
      expect(p.ivaEfectivo(16), 8);
    });
  });

  group('margen', () {
    test('se calcula sobre el precio de venta', () {
      const p = Producto(nombre: 'A', descripcion: '', precio: 100, precioCompra: 60);
      expect(p.margenPorcentaje, 40);
    });

    test('sin precio de compra no hay margen (null, no cero)', () {
      const p = Producto(nombre: 'A', descripcion: '', precio: 100);
      expect(p.margenPorcentaje, isNull);
    });

    test('precioParaMargen es la operación inversa', () {
      final precio = Producto.precioParaMargen(costo: 60, margen: 40);
      expect(precio, closeTo(100, 0.0001));

      final p = Producto(nombre: 'A', descripcion: '', precio: precio!, precioCompra: 60);
      expect(p.margenPorcentaje, closeTo(40, 0.0001));
    });

    test('un margen de 100% o más no es alcanzable', () {
      expect(Producto.precioParaMargen(costo: 60, margen: 100), isNull);
      expect(Producto.precioParaMargen(costo: 60, margen: 150), isNull);
    });
  });

  group('persistencia y unicidad', () {
    test('guarda y recupera SKU e IVA por producto', () async {
      await controller.insertar(
        const Producto(
          nombre: 'Refresco',
          descripcion: '',
          precio: 18.5,
          sku: 'REF-001',
          ivaTasa: 16,
        ),
        10,
      );

      final encontrado = await controller.buscarPorSku('REF-001');
      expect(encontrado, isNotNull);
      expect(encontrado!.nombre, 'Refresco');
      expect(encontrado.ivaTasa, 16);
    });

    test('rechaza dos productos con el mismo SKU', () async {
      await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, sku: 'X1'),
        5,
      );

      expect(
        () => controller.insertar(
          const Producto(nombre: 'B', descripcion: '', precio: 10, sku: 'X1'),
          5,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'mensaje', contains('SKU'))),
      );
    });

    test('permite varios productos sin SKU', () async {
      await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10),
        5,
      );
      await controller.insertar(
        const Producto(nombre: 'B', descripcion: '', precio: 10, sku: ''),
        5,
      );

      final todos = await controller.obtenerTodos();
      expect(todos, hasLength(2));
      expect(todos.every((p) => p.sku == null), isTrue);
    });

    test('existeSku excluye el propio producto al editar', () async {
      final id = await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, sku: 'Z9'),
        5,
      );

      expect(await controller.existeSku('Z9'), isTrue);
      expect(await controller.existeSku('Z9', excluirId: id), isFalse);
      expect(await controller.existeSku('OTRO'), isFalse);
    });

    test('obtenerConStock trae SKU e IVA para el punto de venta', () async {
      await controller.insertar(
        const Producto(
          nombre: 'Pan',
          descripcion: '',
          precio: 12,
          sku: 'PAN-1',
          ivaTasa: 0,
        ),
        7,
      );

      final filas = await controller.obtenerConStock();
      expect(filas.first['sku'], 'PAN-1');
      expect(filas.first['iva_tasa'], 0);
    });

    test('editar un producto sin tocar el SKU no lo borra', () async {
      final id = await controller.insertar(
        const Producto(nombre: 'A', descripcion: '', precio: 10, sku: 'K-1', ivaTasa: 16),
        5,
      );

      final actual = (await controller.obtenerTodos()).first;
      await controller.actualizar(
        Producto(
          idProducto: id,
          nombre: 'A editado',
          descripcion: '',
          precio: 12,
          sku: actual.sku,
          ivaTasa: actual.ivaTasa,
        ),
      );

      final despues = (await controller.obtenerTodos()).first;
      expect(despues.nombre, 'A editado');
      expect(despues.sku, 'K-1');
      expect(despues.ivaTasa, 16);
    });
  });
}
