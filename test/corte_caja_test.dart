// Pruebas del corte de caja rediseñado: el conteo por denominación, que la
// cuenta del efectivo cierre a la vista, que el arqueo a ciegas no filtre
// ninguno de los sumandos del esperado, y la migración v27 que guarda el
// desglose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/controllers/caja_controller.dart';
import 'package:pvapp/controllers/ventas_controller.dart';
import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/security/password_hasher.dart';
import 'package:pvapp/core/session/session_manager.dart';
import 'package:pvapp/core/utils/money.dart';
import 'package:pvapp/models/configuracion_model.dart';
import 'package:pvapp/models/conteo_denominaciones.dart';
import 'package:pvapp/models/vista_corte.dart';

/// Suma los renglones respetando su signo. Es la cuenta que hace de cabeza
/// quien mira la pantalla o el ticket.
double _sumaDeRenglones(ResumenCaja r) {
  var total = 0.0;
  for (final renglon in r.renglonesEfectivo) {
    total += renglon.suma ? renglon.importe : -renglon.importe;
  }
  return redondearMoneda(total);
}

/// Un resumen con TODOS los términos presentes y con valores distintos entre
/// sí, para que ninguna comprobación pase por coincidencia.
ResumenCaja _resumenCompleto() {
  const fondo = 1000.0;
  const ventasEfectivo = 3355.0;
  const anticiposEfectivo = 500.0;
  const entradas = 300.0;
  const cambio = 412.0;
  const cambioAnticipos = 33.0;
  const devoluciones = 118.0;
  const pagosProveedores = 250.0;
  const salidas = 450.0;

  return ResumenCaja(
    fondoInicial: fondo,
    ventasEfectivo: ventasEfectivo,
    ventasTarjeta: 5077.50,
    ventasTransferencia: 890.0,
    cambioEntregado: cambio,
    devoluciones: devoluciones,
    efectivoEsperado: redondearMoneda(fondo +
        ventasEfectivo +
        anticiposEfectivo +
        entradas -
        cambio -
        cambioAnticipos -
        devoluciones -
        pagosProveedores -
        salidas),
    anticiposEfectivo: anticiposEfectivo,
    anticiposTarjeta: 200.0,
    anticiposTransferencia: 77.0,
    cambioAnticipos: cambioAnticipos,
    pagosProveedoresEfectivo: pagosProveedores,
    entradasEfectivo: entradas,
    salidasEfectivo: salidas,
    ticketsCerrados: 63,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ------------------------------------------------- conteo por denominación

  group('ConteoDenominaciones', () {
    test('suma billetes y monedas', () {
      const conteo = ConteoDenominaciones(
        billetes: {1000: 2, 500: 3, 200: 1, 100: 1, 50: 1, 20: 2},
        monedas: 10,
      );

      expect(conteo.totalBilletes, 3890.0);
      expect(conteo.total, 3900.0);
      expect(conteo.piezasBilletes, 10);
      expect(conteo.sinCapturar, isFalse);
    });

    test('un conteo vacío no es lo mismo que un cajón en ceros', () {
      expect(ConteoDenominaciones.vacio.sinCapturar, isTrue);
      expect(const ConteoDenominaciones(monedas: 0.5).sinCapturar, isFalse);
      expect(const ConteoDenominaciones(billetes: {20: 0}).total, 0.0);
    });

    test('poner cero quita la denominación en vez de guardarla', () {
      final conteo =
          ConteoDenominaciones.vacio.conBillete(500, 3).conBillete(500, 0);
      expect(conteo.billetes.containsKey(500), isFalse);
      expect(conteo.total, 0.0);
    });

    test('sobrevive a guardarse y volverse a leer', () {
      const original = ConteoDenominaciones(
        billetes: {1000: 2, 500: 3, 20: 2},
        monedas: 10.25,
      );

      final recuperado = ConteoDenominaciones.desdeJson(original.aJson())!;

      expect(recuperado.billetes, original.billetes);
      expect(recuperado.monedas, original.monedas);
      expect(recuperado.total, original.total);
    });

    test('un cierre viejo sin desglose no truena: devuelve null', () {
      // Las cajas cerradas antes de la v27 no tienen la columna llena, y eso
      // no es un error -- en ellas ese desglose nunca existió.
      expect(ConteoDenominaciones.desdeJson(null), isNull);
      expect(ConteoDenominaciones.desdeJson(''), isNull);
      expect(ConteoDenominaciones.desdeJson('no soy json'), isNull);
      expect(ConteoDenominaciones.desdeJson('[1,2,3]'), isNull);
    });

    test('los renglones van del billete mayor al menor y omiten los ceros', () {
      const conteo = ConteoDenominaciones(
        billetes: {20: 2, 1000: 1, 100: 0},
        monedas: 5,
      );

      expect(
        conteo.renglones.map((r) => r.etiqueta).toList(),
        ['1 x \$1000', '2 x \$20', 'Monedas'],
      );
      expect(conteo.renglones.map((r) => r.importe).toList(), [1000.0, 40.0, 5.0]);
    });
  });

  // ------------------------------------------------ la cuenta cierra a la vista

  group('LA CUENTA DEL EFECTIVO CIERRA', () {
    test('los renglones suman exactamente el efectivo esperado', () {
      final r = _resumenCompleto();
      expect(_sumaDeRenglones(r), r.efectivoEsperado);
    });

    test('incluye los dos sumandos que la pantalla vieja no mostraba', () {
      // Anticipos de apartados y pagos a proveedores en efectivo SÍ entran en
      // `efectivoEsperado`, pero antes no tenían tarjeta en pantalla: en un
      // negocio con apartados el esperado no se podía reconstruir sumando lo
      // que se veía, y quien revisaba concluía que el sistema se equivocó.
      final etiquetas = _resumenCompleto().renglonesEfectivo.map((r) => r.etiqueta);

      expect(etiquetas, contains('Anticipos de apartados'));
      expect(etiquetas, contains('Pagos a proveedores'));
    });

    test('el primer renglón es el fondo inicial, que es la base de la cuenta', () {
      final renglones = _resumenCompleto().renglonesEfectivo;
      expect(renglones.first.etiqueta, 'Fondo inicial');
      expect(renglones.first.suma, isTrue);
    });

    test('un turno sin movimientos deja solo fondo y ventas en efectivo', () {
      const r = ResumenCaja(
        fondoInicial: 500,
        ventasEfectivo: 0,
        ventasTarjeta: 0,
        ventasTransferencia: 0,
        cambioEntregado: 0,
        devoluciones: 0,
        efectivoEsperado: 500,
      );

      expect(r.renglonesEfectivo.length, 2);
      expect(_sumaDeRenglones(r), 500.0);
    });

    test('el no-efectivo no toca la cuenta del cajón', () {
      final r = _resumenCompleto();
      expect(r.totalNoEfectivo, 5077.50 + 890.0 + 200.0 + 77.0);

      final etiquetas = r.renglonesEfectivo.map((e) => e.etiqueta).join(' ');
      expect(etiquetas.contains('Tarjeta'), isFalse);
      expect(etiquetas.contains('Transferencia'), isFalse);
    });
  });

  // ------------------------------------------------------- arqueo a ciegas

  group('arqueo a ciegas', () {
    test('NINGUN SUMANDO DEL ESPERADO SE FILTRA', () {
      // Esta es la prueba que sostiene toda la regla. Si alguien agrega más
      // adelante un dato de efectivo a la pantalla del cajero y olvida el
      // criterio, esto truena aquí y no en la tienda de un cliente.
      final vista = VistaCorte(resumen: _resumenCompleto(), aCiegas: true);

      for (final sumando in vista.sumandosDelEsperado) {
        expect(
          vista.montosVisibles,
          isNot(contains(sumando)),
          reason: 'El monto $sumando es sumando del efectivo esperado y no debe '
              'verse antes de cerrar: con él a la vista, el esperado se despeja.',
        );
      }

      expect(vista.efectivoEsperado, isNull);
      expect(vista.renglonesEfectivo, isEmpty);
    });

    test('el total vendido también se oculta, porque se despeja', () {
      // vendido - tarjeta - transferencia = ventas en efectivo, que sí es
      // sumando. Ocultar el esperado y mostrar el vendido no serviría de nada.
      final vista = VistaCorte(resumen: _resumenCompleto(), aCiegas: true);
      expect(vista.totalVendido, isNull);
    });

    test('tarjeta, transferencia y tickets sí se ven: no entran al cajón', () {
      final vista = VistaCorte(resumen: _resumenCompleto(), aCiegas: true);

      expect(vista.ventasTarjeta, 5077.50);
      expect(vista.ventasTransferencia, 890.0);
      expect(vista.anticiposTarjeta, 200.0);
      expect(vista.tickets, 63);
    });

    test('quien audita ve la cuenta completa', () {
      final r = _resumenCompleto();
      final vista = VistaCorte(resumen: r, aCiegas: false);

      expect(vista.efectivoEsperado, r.efectivoEsperado);
      expect(vista.totalVendido, r.totalVentas);
      expect(vista.renglonesEfectivo.length, r.renglonesEfectivo.length);

      for (final sumando in vista.sumandosDelEsperado) {
        if (sumando > 0) {
          expect(vista.montosVisibles, contains(sumando));
        }
      }
    });
  });

  // ------------------------------------------------- contra la base de datos

  group('cierre con desglose', () {
    late Directory tempDir;
    late Database db;
    late CajaController caja;
    late VentasController ventas;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pvapp_corte_caja_test');
      db = await DatabaseHelper().abrirEnRuta(join(tempDir.path, 'test.db'));
      DatabaseHelper.setTestDatabase(db);
      caja = CajaController();
      ventas = VentasController();

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
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<int> crearProducto({double precio = 10, int stock = 100}) async {
      final id = await db.insert('Producto', {
        'nombre': 'Producto de prueba',
        'descripcion': '',
        'precio': precio,
        'stock_minimo': 0,
        'estado': 'Activo',
      });
      await db.insert('Inventario', {'id_producto': id, 'cantidad': stock});
      return id;
    }

    test('guarda el desglose y se puede releer tal cual se capturó', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 1000);
      const conteo = ConteoDenominaciones(billetes: {500: 2}, monedas: 3.50);

      await caja.cerrarCaja(
        idCaja: idCaja,
        efectivoContado: conteo.total,
        conteo: conteo,
      );

      final cerrada = (await caja.obtenerHistorial()).single;
      expect(cerrada.conteo, isNotNull);
      expect(cerrada.conteo!.billetes, {500: 2});
      expect(cerrada.conteo!.monedas, 3.50);
      expect(cerrada.conteo!.total, 1003.50);
      expect(cerrada.efectivoContado, 1003.50);
    });

    test('un desglose que no cuadra con el total no se guarda', () async {
      // Sería un error de programación, no del usuario: el ticket imprimiría
      // un desglose que no suma el número con el que se calculó la diferencia,
      // y ese papel es justo la evidencia que se saca cuando alguien reclama.
      final idCaja = await caja.abrirCaja(fondoInicial: 1000);

      await expectLater(
        caja.cerrarCaja(
          idCaja: idCaja,
          efectivoContado: 999,
          conteo: const ConteoDenominaciones(billetes: {500: 2}),
        ),
        throwsA(isA<Exception>()),
      );

      final sigueAbierta = (await caja.obtenerHistorial()).single;
      expect(sigueAbierta.estaAbierta, isTrue);
    });

    test('cerrar sin desglose sigue funcionando y deja la columna vacía', () async {
      // Compatibilidad: nada obliga a capturar denominaciones para cerrar.
      final idCaja = await caja.abrirCaja(fondoInicial: 100);
      await caja.cerrarCaja(idCaja: idCaja, efectivoContado: 100);

      final cerrada = (await caja.obtenerHistorial()).single;
      expect(cerrada.conteo, isNull);
      expect(cerrada.estaAbierta, isFalse);
    });

    test('los renglones cierran también con datos reales del controlador', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 500);

      final idProducto = await crearProducto(precio: 850);
      await ventas.insertarVentaCompleta(
        carrito: [
          {'id_producto': idProducto, 'nombre': 'Producto', 'precio': 850.0, 'cantidad': 1},
        ],
        pagos: const [
          {'metodo_pago': 'Efectivo', 'monto': 1000.0},
        ],
      );

      await caja.registrarMovimientoEfectivo(
          esEntrada: true, monto: 300, concepto: 'Más cambio');
      await caja.registrarMovimientoEfectivo(
          esEntrada: false, monto: 120, concepto: 'Pago de garrafón');

      final resumen = await caja.calcularResumenCaja(idCaja);

      expect(_sumaDeRenglones(resumen), resumen.efectivoEsperado);
      expect(resumen.entradasEfectivo, 300.0);
      expect(resumen.salidasEfectivo, 120.0);
    });

    test('cuenta los tickets del turno sin contar los cancelados', () async {
      final idCaja = await caja.abrirCaja(fondoInicial: 0);
      final idProducto = await crearProducto(precio: 10, stock: 500);

      Future<int> vender() => ventas.insertarVentaCompleta(
            carrito: [
              {'id_producto': idProducto, 'nombre': 'P', 'precio': 10.0, 'cantidad': 1},
            ],
            pagos: const [
              {'metodo_pago': 'Efectivo', 'monto': 10.0},
            ],
          );

      await vender();
      await vender();
      final idVenta = await vender();

      expect((await caja.calcularResumenCaja(idCaja)).ticketsCerrados, 3);

      await db.update('Ventas', {'estado': 'Cancelada'},
          where: 'id_venta = ?', whereArgs: [idVenta]);

      // Una venta cancelada ya no es una operación: contarla haría que el
      // corte no cuadrara contra el reporte del día, que la excluye igual.
      expect((await caja.calcularResumenCaja(idCaja)).ticketsCerrados, 2);
    });
  });

  // --------------------------------------------------------- migración v27

  group('migración v27', () {
    late Directory tempDir;
    late String path;
    Database? abierta;

    Future<Database> abrir() async {
      abierta = await DatabaseHelper().abrirEnRuta(path);
      return abierta!;
    }

    Future<Set<String?>> columnas(Database db) async {
      final info = await db.rawQuery('PRAGMA table_info(Cajas)');
      return info.map((c) => c['name']?.toString()).toSet();
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pvapp_corte_v27');
      path = join(tempDir.path, 'test.db');
    });

    tearDown(() async {
      await abierta?.close();
      abierta = null;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('agrega la columna sin tocar la caja que ya estaba cerrada', () async {
      var db = await abrir();

      await db.insert('Usuarios', {
        'nombre': 'Ana',
        'contra': PasswordHasher.hash('x'),
        'rol': 'Cajero',
      });
      await db.insert('Cajas', {
        'id_usuario': 1,
        'fecha_apertura': '2026-08-14T08:04:00.000',
        'fecha_cierre': '2026-08-14T14:12:00.000',
        'fondo_inicial': 1000.0,
        'efectivo_esperado': 3925.0,
        'efectivo_contado': 3900.0,
        'diferencia': -25.0,
        'estado': 'Cerrada',
      });

      await db.execute('ALTER TABLE Cajas DROP COLUMN conteo_denominaciones');
      await db.execute('PRAGMA user_version = 26');
      await db.close();

      db = await abrir();

      expect(await columnas(db), contains('conteo_denominaciones'));

      final fila = (await db.query('Cajas', where: 'id_caja = 1')).single;
      expect(fila['efectivo_esperado'], 3925.0);
      expect(fila['efectivo_contado'], 3900.0);
      expect(fila['diferencia'], -25.0);
      expect(fila['estado'], 'Cerrada');

      // Nace vacía: en ese cierre nunca hubo desglose, y fingir uno sería
      // inventar evidencia.
      expect(fila['conteo_denominaciones'], isNull);
    });

    test('una instalación nueva nace con la columna', () async {
      final db = await abrir();
      expect(await columnas(db), contains('conteo_denominaciones'));
      expect(await db.getVersion(), DatabaseHelper.versionEsquema);
    });

    test('reabrir no vuelve a migrar', () async {
      var db = await abrir();
      await db.execute('ALTER TABLE Cajas DROP COLUMN conteo_denominaciones');
      await db.execute('PRAGMA user_version = 26');
      await db.close();

      db = await abrir();
      await db.close();
      db = await abrir();

      expect(await columnas(db), contains('conteo_denominaciones'));
      expect(await db.getVersion(), DatabaseHelper.versionEsquema);
    });
  });
}
