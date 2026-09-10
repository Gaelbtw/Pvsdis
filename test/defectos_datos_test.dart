// Pruebas de los defectos de datos encontrados en la auditoría de septiembre.
//
// Los cinco perdían o corrompían información en silencio: no había error, no
// había aviso, y el dato correcto ya no existía en ninguna parte. Cada grupo
// de aquí reproduce el escenario exacto en que fallaba.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/compras_controller.dart';
import 'package:pvapp/controllers/devoluciones_controller.dart';
import 'package:pvapp/controllers/producto_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/descuento_utils.dart';
import 'package:pvapp/core/sync/auth_service.dart';
import 'package:pvapp/core/sync/models/sync_auth_models.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/producto_model.dart';

SesionSync _sesionDePrueba() => SesionSync(
      usuarioId: '22222222-2222-2222-2222-222222222222',
      email: 'a@b.com',
      nombreCompleto: 'Persona Uno',
      roles: const ['Admin'],
      sucursalId: null,
      accessToken: 'access-1',
      accessTokenExpiraEn: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      refreshToken: 'refresh-1',
      tenantId: '11111111-1111-1111-1111-111111111111',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late ProductoController productos;
  late ComprasController compras;
  late VentasController ventas;
  late DevolucionesController devoluciones;
  late CajaController caja;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_defectos_datos_test');
    db = await DatabaseHelper().abrirEnRuta(join(tempDir.path, 'test.db'));
    DatabaseHelper.setTestDatabase(db);

    productos = ProductoController();
    compras = ComprasController();
    ventas = VentasController();
    devoluciones = DevolucionesController();
    caja = CajaController();

    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    SessionManager.setUser(id: 1, nombre: 'Sistema', rol: 'Admin');

    await db.insert('Usuarios', {
      'nombre': 'Sistema',
      'contra': PasswordHasher.hash('x'),
      'rol': 'Admin',
    });
  });

  tearDown(() async {
    await DatabaseHelper().closeDatabase();
    DatabaseHelper.setTestDatabase(null);
    AppConfig.actualizar(Configuracion.porDefecto());
    SessionManager.clear();
    AuthService.setSesionDePrueba(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<int> crearProveedor() => db.insert('Proveedores', {'nombre': 'Distribuidora'});

  Future<Map<String, dynamic>> filaProducto(int id) async =>
      (await db.query('Producto', where: 'id_producto = ?', whereArgs: [id])).single;

  // ------------------------------------------------------------------ 01

  group('EDITAR UN PRODUCTO NO BORRA LO QUE NO SE EDITÓ', () {
    late int idProducto;

    setUp(() async {
      idProducto = await productos.insertar(
        const Producto(
          nombre: 'Refresco 600ml',
          descripcion: 'Retornable, caja de 12',
          precio: 20,
          precioCompra: 12.50,
          stockMinimo: 24,
          codigoBarras: '7501055300013',
          sku: 'REF-600',
          ivaTasa: 8,
        ),
        40,
      );
    });

    test('corregir el precio conserva costo, descripción y stock mínimo', () async {
      // Esta es la ruta exacta del diálogo de edición rápida de Inventario:
      // toma la fila que muestra la tabla y solo cambia nombre y precio.
      final fila = (await productos.obtenerConStock())
          .firstWhere((p) => p['id_producto'] == idProducto);

      await productos.actualizar(
        Producto.fromMap(fila).copyWith(nombre: 'Refresco 600 ml', precio: 21),
      );

      final despues = await filaProducto(idProducto);

      expect(despues['nombre'], 'Refresco 600 ml');
      expect(despues['precio'], 21);

      // Lo que NO se editó tiene que seguir exactamente igual. Antes de este
      // arreglo, el costo quedaba en NULL, la descripción vacía y el stock
      // mínimo se pisaba con el global de Configuración -- en silencio, y sin
      // forma de recuperar los valores anteriores.
      expect(despues['precio_compra'], 12.50,
          reason: 'El costo de compra se perdió al editar el precio.');
      expect(despues['descripcion'], 'Retornable, caja de 12',
          reason: 'La descripción se borró al editar el precio.');
      expect(despues['stock_minimo'], 24,
          reason: 'El stock mínimo propio se pisó con el global.');
      expect(despues['codigo_barras'], '7501055300013');
      expect(despues['sku'], 'REF-600');
      expect(despues['iva_tasa'], 8);
    });

    test('la consulta de inventario trae lo que el diálogo debe conservar', () async {
      // Sin estas dos columnas en la fila, el diálogo no tiene con qué
      // devolverlas y el arreglo de arriba sería imposible.
      final fila = (await productos.obtenerConStock())
          .firstWhere((p) => p['id_producto'] == idProducto);

      expect(fila.containsKey('precio_compra'), isTrue);
      expect(fila.containsKey('descripcion'), isTrue);
    });

    test('copyWith no toca lo que no se nombra', () {
      const original = Producto(
        nombre: 'A',
        descripcion: 'texto',
        precio: 10,
        precioCompra: 6,
        stockMinimo: 3,
        sku: 'X-1',
      );

      final copia = original.copyWith(precio: 11);

      expect(copia.precio, 11);
      expect(copia.descripcion, 'texto');
      expect(copia.precioCompra, 6);
      expect(copia.stockMinimo, 3);
      expect(copia.sku, 'X-1');
    });
  });

  // ------------------------------------------------------------------ 02

  group('COMPRAR ACTUALIZA EL COSTO DEL PRODUCTO', () {
    test('el producto queda con el costo de la última compra', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Aceite', descripcion: '', precio: 40, precioCompra: 12),
        10,
      );
      final idProveedor = await crearProveedor();

      await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 200, 'precio_compra': 18.0},
        ],
        3600,
        idProveedor,
      );

      // Antes esto seguía diciendo 12: el costo solo se escribía al dar de
      // alta o editar el producto a mano. El reporte de utilidad mostraba un
      // margen de $28 cuando el real era $22, y sin marcarlo como dudoso.
      expect((await filaProducto(idProducto))['precio_compra'], 18.0);
    });

    test('una compra sin precio no borra el costo que ya se conocía', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Servilletas', descripcion: '', precio: 30, precioCompra: 14),
        5,
      );
      final idProveedor = await crearProveedor();

      await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 10, 'precio_compra': 0},
        ],
        0,
        idProveedor,
      );

      expect((await filaProducto(idProducto))['precio_compra'], 14.0);
    });

    test('la venta posterior congela el costo nuevo, no el del alta', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Jabón', descripcion: '', precio: 25, precioCompra: 10),
        50,
      );
      final idProveedor = await crearProveedor();
      await caja.abrirCaja(fondoInicial: 0);

      await compras.insertarCompraCompleta(
        [
          {'id_producto': idProducto, 'cantidad': 20, 'precio_compra': 16.0},
        ],
        320,
        idProveedor,
      );

      final idVenta = await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Jabón', 'precio': 25.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 25.0},
        ],
      );

      final linea = (await db.query('Detalle_Venta',
              where: 'id_venta = ?', whereArgs: [idVenta]))
          .single;
      expect(linea['costo_unitario'], 16.0);
    });
  });

  // ------------------------------------------------------------------ 03

  group('AJUSTAR EL STOCK NO BORRA UNA VENTA EN PARALELO', () {
    test('aplica la diferencia que quiso el usuario, no el número absoluto', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Galletas', descripcion: '', precio: 15),
        8,
      );
      await caja.abrirCaja(fondoInicial: 0);

      // El admin abre el diálogo y ve 8.
      const stockQueVioElAdmin = 8;

      // Mientras lo tiene abierto, se venden 3: quedan 5.
      await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Galletas', 'precio': 15.0, 'cantidad': 3},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 45.0},
        ],
      );

      // El admin corrige a 10 y guarda: quiso sumar 2, no fijar 10.
      await productos.actualizarStock(idProducto, 10, stockVisto: stockQueVioElAdmin);

      final stock = (await db.query('Inventario',
              where: 'id_producto = ?', whereArgs: [idProducto]))
          .single['cantidad'];

      // Antes escribía 10 y la venta desaparecía del inventario.
      expect(stock, 7, reason: 'La venta hecha en paralelo se borró del inventario.');
    });

    test('sin stockVisto sigue fijando el valor, como antes', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Atún', descripcion: '', precio: 20),
        30,
      );

      await productos.actualizarStock(idProducto, 25);

      final stock = (await db.query('Inventario',
              where: 'id_producto = ?', whereArgs: [idProducto]))
          .single['cantidad'];
      expect(stock, 25);
    });

    test('no deja la existencia por debajo de lo apartado', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Licuadora', descripcion: '', precio: 900),
        6,
      );
      await db.update('Inventario', {'cantidad_reservada': 5},
          where: 'id_producto = ?', whereArgs: [idProducto]);

      // Las 5 apartadas siguen físicamente en la tienda: dejar el stock en 2
      // manda el disponible a -3 y revienta al liquidar el apartado.
      await expectLater(
        productos.actualizarStock(idProducto, 2),
        throwsA(isA<Exception>()),
      );

      final stock = (await db.query('Inventario',
              where: 'id_producto = ?', whereArgs: [idProducto]))
          .single['cantidad'];
      expect(stock, 6, reason: 'La transacción debió revertirse completa.');
    });
  });

  // ------------------------------------------------------------------ 04

  group('DEVOLVER EN EFECTIVO EXIGE AUTORIZACIÓN SI NO SE SABE CÓMO SE PAGÓ', () {
    Future<int> ventaSinPagosRegistrados({String? metodoPago}) async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Mochila', descripcion: '', precio: 500),
        10,
      );
      final idCaja = await caja.abrirCaja(fondoInicial: 1000);

      final idVenta = await db.insert('Ventas', {
        'fecha': DateTime.now().toIso8601String(),
        'total': 500.0,
        'metodo_pago': metodoPago,
        'estado': 'Activa',
        'id_caja': idCaja,
      });
      await db.insert('Detalle_Venta', {
        'id_venta': idVenta,
        'id_producto': idProducto,
        'cantidad': 1,
        'precio': 500.0,
      });
      return idVenta;
    }

    test('sin método determinable, un cajero no puede reembolsar', () async {
      // Es el caso de las ventas nacidas de liquidar un apartado: no tienen
      // filas en Venta_Pagos. Antes se colaban por el hueco del `null` y
      // salían miles de pesos en efectivo sin firma de nadie.
      final idVenta = await ventaSinPagosRegistrados();

      await expectLater(
        devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Prueba'),
        throwsA(isA<Exception>()),
      );

      final estado = (await db.query('Ventas',
              where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['estado'];
      expect(estado, 'Activa', reason: 'La venta no debió cancelarse.');
    });

    test('con autorización de administrador sí procede', () async {
      final idVenta = await ventaSinPagosRegistrados();

      await devoluciones.cancelarVenta(
        idVenta: idVenta,
        motivo: 'Prueba',
        autorizadoPor: 1,
      );

      final estado = (await db.query('Ventas',
              where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['estado'];
      expect(estado, 'Cancelada');
    });

    test('una venta de efectivo conocida no pide autorización', () async {
      // El resumen de `Ventas.metodo_pago` alcanza para las ventas viejas,
      // anteriores a que existiera Venta_Pagos.
      final idVenta = await ventaSinPagosRegistrados(metodoPago: 'Efectivo');

      await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Prueba');

      final estado = (await db.query('Ventas',
              where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['estado'];
      expect(estado, 'Cancelada');
    });
  });

  // ------------------------------------------------------------------ 05

  group('CANCELAR UNA VENTA SE LE AVISA AL BACKEND', () {
    test('el cambio de estado queda encolado en el outbox', () async {
      AuthService.setSesionDePrueba(_sesionDePrueba());

      final idProducto = await productos.insertar(
        const Producto(nombre: 'Termo', descripcion: '', precio: 300),
        10,
      );
      await caja.abrirCaja(fondoInicial: 500);

      final idVenta = await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Termo', 'precio': 300.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 300.0},
        ],
      );

      final guid = (await db.query('Ventas',
              columns: ['guid_sync'], where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['guid_sync'] as String;

      await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Prueba');

      // Sin esto, el backend seguía contando la venta como completada, y al
      // reiniciar el cursor de sync la traía de vuelta como activa: revivía
      // una venta cancelada, con el stock ya reintegrado y el dinero devuelto.
      final encoladas = await db.query(
        'Sync_Outbox',
        where: 'entidad = ? AND guid_registro = ? AND operacion = ?',
        whereArgs: ['Venta', guid, 'ACTUALIZAR'],
      );
      expect(encoladas, isNotEmpty,
          reason: 'La cancelación no se encoló para el backend.');
    });
  });

  // ------------------------------------------------------------------ 14

  group('DEVOLVER NO REGALA CENTAVOS', () {
    test('cancelar una venta con descuento devuelve exactamente lo cobrado', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Cuaderno', descripcion: '', precio: 10),
        20,
      );
      await caja.abrirCaja(fondoInicial: 500);

      // Tres piezas de $10 con $1 de descuento en la línea. El neto por
      // unidad es 9.666..., que se guarda redondeado en 9.67.
      final idVenta = await ventas.insertarVentaCompleta(
        carrito: [
          {
            'id_producto': idProducto,
            'nombre': 'Cuaderno',
            'precio': 10.0,
            'cantidad': 3,
            'descuento_tipo': TipoDescuento.fijo,
            'descuento_valor': 1.0,
          },
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 29.0},
        ],
      );

      final cobrado = (await db.query('Ventas',
              columns: ['total'], where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['total'] as num;

      await devoluciones.cancelarVenta(idVenta: idVenta, motivo: 'Prueba');

      final devuelto = (await db.query('Devoluciones',
              columns: ['importe'], where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['importe'] as num;

      // Antes se devolvía 9.67 x 3 = $29.01 contra $29.00 cobrados: un
      // centavo de sobrante en el corte, cada vez.
      expect(devuelto.toDouble(), cobrado.toDouble(),
          reason: 'Se devolvió un importe distinto al que se cobró.');
    });

    test('devolver de a una pieza suma exactamente el total, sin arrastre', () async {
      final idProducto = await productos.insertar(
        const Producto(nombre: 'Pluma', descripcion: '', precio: 10),
        20,
      );
      await caja.abrirCaja(fondoInicial: 500);

      final idVenta = await ventas.insertarVentaCompleta(
        carrito: [
          {
            'id_producto': idProducto,
            'nombre': 'Pluma',
            'precio': 10.0,
            'cantidad': 3,
            'descuento_tipo': TipoDescuento.fijo,
            'descuento_valor': 1.0,
          },
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 29.0},
        ],
      );

      for (var i = 0; i < 3; i++) {
        await devoluciones.devolverParcial(
          idVenta: idVenta,
          motivo: 'Prueba $i',
          items: [
            {'id_producto': idProducto, 'cantidad': 1},
          ],
        );
      }

      final filas = await db.query('Devoluciones',
          columns: ['importe'], where: 'id_venta = ?', whereArgs: [idVenta]);
      final sumaDevuelta = filas.fold<double>(
        0,
        (a, f) => a + (f['importe'] as num).toDouble(),
      );

      final cobrado = (await db.query('Ventas',
              columns: ['total'], where: 'id_venta = ?', whereArgs: [idVenta]))
          .single['total'] as num;

      // El cálculo por acumulado existe justamente para esto: tres
      // devoluciones de $9.67 darían $29.01.
      expect(sumaDevuelta, cobrado.toDouble());
    });
  });
}
