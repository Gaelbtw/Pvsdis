// Pruebas de PromocionesController: CRUD, validaciones por tipo, vigencia
// por fecha, activar/desactivar y auditoría.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/promociones_controller.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/models/promocion_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late PromocionesController controller;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_promociones_controller_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    DatabaseHelper.setTestDatabase(db);
    controller = PromocionesController();
    SessionManager.clear();
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    SessionManager.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<int> crearProducto({String nombre = 'Producto'}) async {
    final id = await db.insert('Producto', {
      'nombre': nombre,
      'descripcion': '',
      'precio': 10.0,
      'stock_minimo': 0,
      'estado': 'Activo',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': 100});
    return id;
  }

  Future<int> crearCategoria({String nombre = 'Categoria'}) async {
    return db.insert('Categorias', {'nombre': nombre});
  }

  group('crear / obtenerTodas / obtenerPorId', () {
    test('crea una promoción de porcentaje con productos participantes', () async {
      final idProducto = await crearProducto();

      final id = await controller.crear(Promocion(
        nombre: '10% en producto',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
      ));

      final guardada = await controller.obtenerPorId(id);
      expect(guardada, isNotNull);
      expect(guardada!.nombre, '10% en producto');
      expect(guardada.tipo, TipoPromocion.porcentajeProducto);
      expect(guardada.productosIds, [idProducto]);
      expect(guardada.activo, isTrue);

      final auditorias = await db.query('Auditorias', where: "tabla = 'Promociones' AND accion = 'CREATE'");
      expect(auditorias, hasLength(1));
    });

    test('crea un combo con sus items', () async {
      final idA = await crearProducto(nombre: 'A');
      final idB = await crearProducto(nombre: 'B');

      final id = await controller.crear(Promocion(
        nombre: 'Combo AB',
        tipo: TipoPromocion.combo,
        precioCombo: 15,
        comboItems: [
          ComboItem(idProducto: idA, cantidad: 1),
          ComboItem(idProducto: idB, cantidad: 2),
        ],
      ));

      final guardada = await controller.obtenerPorId(id);
      expect(guardada!.comboItems, hasLength(2));
      expect(guardada.comboItems.firstWhere((i) => i.idProducto == idB).cantidad, 2);
    });

    test('crea una promoción con categorías participantes', () async {
      final idCategoria = await crearCategoria();

      final id = await controller.crear(Promocion(
        nombre: 'Promo por categoría',
        tipo: TipoPromocion.montoFijoProducto,
        valor: 5,
        categoriasIds: [idCategoria],
      ));

      final guardada = await controller.obtenerPorId(id);
      expect(guardada!.categoriasIds, [idCategoria]);
    });

    test('obtenerTodas devuelve todas ordenadas por prioridad', () async {
      final idProducto = await crearProducto();
      await controller.crear(Promocion(
        nombre: 'Baja',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 5,
        prioridad: 1,
        productosIds: [idProducto],
      ));
      await controller.crear(Promocion(
        nombre: 'Alta',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 5,
        prioridad: 10,
        productosIds: [idProducto],
      ));

      final todas = await controller.obtenerTodas();
      expect(todas, hasLength(2));
      expect(todas.first.nombre, 'Alta');
    });
  });

  group('actualizar', () {
    test('reemplaza los participantes por completo', () async {
      final idA = await crearProducto(nombre: 'A');
      final idB = await crearProducto(nombre: 'B');

      final id = await controller.crear(Promocion(
        nombre: 'Promo',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idA],
      ));

      final actual = await controller.obtenerPorId(id);
      await controller.actualizar(actual!.copyWith(nombre: 'Promo editada', productosIds: [idB]));

      final editada = await controller.obtenerPorId(id);
      expect(editada!.nombre, 'Promo editada');
      expect(editada.productosIds, [idB]);

      final auditorias = await db.query('Auditorias', where: "tabla = 'Promociones' AND accion = 'EDIT'");
      expect(auditorias, hasLength(1));
    });
  });

  group('activar / desactivar / eliminar', () {
    test('desactivar y activar cambian el estado y registran auditoría', () async {
      final idProducto = await crearProducto();
      final id = await controller.crear(Promocion(
        nombre: 'Promo',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
      ));

      await controller.desactivar(id);
      expect((await controller.obtenerPorId(id))!.activo, isFalse);

      await controller.activar(id);
      expect((await controller.obtenerPorId(id))!.activo, isTrue);

      final auditorias = await db.query('Auditorias', where: "tabla = 'Promociones'");
      expect(auditorias.map((a) => a['accion']), containsAll(['CREATE', 'DESACTIVAR', 'ACTIVAR']));
    });

    test('eliminar borra la promoción pero no rompe la base', () async {
      final idProducto = await crearProducto();
      final id = await controller.crear(Promocion(
        nombre: 'Promo',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
      ));

      await controller.eliminar(id);
      expect(await controller.obtenerPorId(id), isNull);
    });
  });

  group('validaciones', () {
    test('rechaza nombre vacío', () async {
      expect(
        () => controller.crear(Promocion(nombre: '  ', tipo: TipoPromocion.porcentajeProducto, valor: 10)),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza porcentaje fuera de 0-100', () async {
      final idProducto = await crearProducto();
      expect(
        () => controller.crear(Promocion(
          nombre: 'Promo',
          tipo: TipoPromocion.porcentajeProducto,
          valor: 150,
          productosIds: [idProducto],
        )),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza NXY donde Y >= X', () async {
      final idProducto = await crearProducto();
      expect(
        () => controller.crear(Promocion(
          nombre: 'Promo',
          tipo: TipoPromocion.nxy,
          nxLleva: 2,
          nxPaga: 2,
          productosIds: [idProducto],
        )),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza combo con menos de 2 productos', () async {
      final idProducto = await crearProducto();
      expect(
        () => controller.crear(Promocion(
          nombre: 'Combo',
          tipo: TipoPromocion.combo,
          precioCombo: 10,
          comboItems: [ComboItem(idProducto: idProducto, cantidad: 1)],
        )),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza promoción sin productos ni categorías participantes (salvo combo)', () async {
      expect(
        () => controller.crear(Promocion(nombre: 'Promo', tipo: TipoPromocion.porcentajeProducto, valor: 10)),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza fecha fin anterior a fecha inicio', () async {
      final idProducto = await crearProducto();
      expect(
        () => controller.crear(Promocion(
          nombre: 'Promo',
          tipo: TipoPromocion.porcentajeProducto,
          valor: 10,
          productosIds: [idProducto],
          fechaInicio: DateTime(2026, 6, 1),
          fechaFin: DateTime(2026, 1, 1),
        )),
        throwsA(isA<Exception>()),
      );
    });

    test('rechaza descuento por cantidad con cantidad mínima inválida', () async {
      final idProducto = await crearProducto();
      expect(
        () => controller.crear(Promocion(
          nombre: 'Promo',
          tipo: TipoPromocion.descuentoCantidad,
          cantidadMinima: 0,
          tipoValor: TipoDescuento.porcentaje,
          valor: 10,
          productosIds: [idProducto],
        )),
        throwsA(isA<Exception>()),
      );
    });

    test('ninguna promoción inválida queda persistida', () async {
      try {
        await controller.crear(Promocion(nombre: '', tipo: TipoPromocion.porcentajeProducto, valor: 10));
      } catch (_) {}
      expect(await controller.obtenerTodas(), isEmpty);
    });
  });

  group('obtenerActivasVigentes', () {
    test('excluye promociones inactivas', () async {
      final idProducto = await crearProducto();
      final id = await controller.crear(Promocion(
        nombre: 'Promo',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
      ));
      await controller.desactivar(id);

      expect(await controller.obtenerActivasVigentes(), isEmpty);
    });

    test('excluye promociones fuera de su rango de fechas', () async {
      final idProducto = await crearProducto();
      final fecha = DateTime(2026, 6, 15);

      await controller.crear(Promocion(
        nombre: 'Vencida',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
        fechaInicio: DateTime(2026, 1, 1),
        fechaFin: DateTime(2026, 3, 1),
      ));
      await controller.crear(Promocion(
        nombre: 'Futura',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
        fechaInicio: DateTime(2026, 9, 1),
      ));
      await controller.crear(Promocion(
        nombre: 'Vigente',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
        fechaInicio: DateTime(2026, 6, 1),
        fechaFin: DateTime(2026, 6, 30),
      ));
      await controller.crear(Promocion(
        nombre: 'Sin límite de fechas',
        tipo: TipoPromocion.porcentajeProducto,
        valor: 10,
        productosIds: [idProducto],
      ));

      final vigentes = await controller.obtenerActivasVigentes(fecha: fecha);
      expect(vigentes.map((p) => p.nombre).toSet(), {'Vigente', 'Sin límite de fechas'});
    });
  });
}
