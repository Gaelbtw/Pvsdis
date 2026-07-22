// Sub-fase 3c del motor de sincronización: mappers de Producto/Stock,
// Promocion, Venta+Detalle+Pago+Promocion, CajaSesion+Movimiento*+CorteCaja.
// Mismo patrón que entity_mapper_test.dart (3b): DB sqflite real en
// memoria, sin fakes -- lo que se prueba ES la traducción contra el
// esquema SQL real.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pvapp/core/config/app_config.dart';
import 'package:pvapp/core/database/database_helper.dart';
import 'package:pvapp/core/sync/entities/caja_sesion_mapper.dart';
import 'package:pvapp/core/sync/entities/corte_caja_mapper.dart';
import 'package:pvapp/core/sync/entities/entity_mapper.dart';
import 'package:pvapp/core/sync/entities/entity_mapper_registry.dart';
import 'package:pvapp/core/sync/entities/movimiento_caja_mapper.dart';
import 'package:pvapp/core/sync/entities/movimiento_inventario_mapper.dart';
import 'package:pvapp/core/sync/entities/producto_mapper.dart';
import 'package:pvapp/core/sync/entities/promocion_mapper.dart';
import 'package:pvapp/core/sync/entities/stock_mapper.dart';
import 'package:pvapp/core/sync/entities/venta_detalle_mapper.dart';
import 'package:pvapp/core/sync/entities/venta_mapper.dart';
import 'package:pvapp/core/sync/entities/venta_pago_mapper.dart';
import 'package:pvapp/core/sync/entities/venta_promocion_mapper.dart';
import 'package:pvapp/models/configuracion_model.dart';

const _tenantId = '11111111-1111-1111-1111-111111111111';
const _usuarioIdSync = '22222222-2222-2222-2222-222222222222';
const _sucursalId = '33333333-3333-3333-3333-333333333333';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late Database db;
  late FkResolver resolver;

  Future<int> crearCategoria() => DatabaseHelper.insertarConGuidSync(db, 'Categorias', {'nombre': 'Bebidas'});

  Future<int> crearProducto({int? idCategoria, double precio = 20.0, double? precioCompra}) async {
    final id = await DatabaseHelper.insertarConGuidSync(db, 'Producto', {
      'nombre': 'Refresco',
      'precio': precio,
      'precio_compra': precioCompra,
      'id_categoria': idCategoria,
      'codigo_barras': 'COD123',
    });
    await db.insert('Inventario', {'id_producto': id, 'cantidad': 10});
    return id;
  }

  Future<int> crearUsuarioLocal() => db.insert('Usuarios', {'nombre': 'Cajero', 'contra': 'hash', 'rol': 'Cajero'});

  Future<int> crearCaja(int idUsuario) => DatabaseHelper.insertarConGuidSync(db, 'Cajas', {
        'id_usuario': idUsuario,
        'fecha_apertura': '2026-01-01T08:00:00Z',
        'fondo_inicial': 500.0,
      });

  Future<int> crearCliente() => DatabaseHelper.insertarConGuidSync(db, 'Clientes', {'nombre': 'Cliente Uno'});

  Future<void> configurarSucursal() async {
    await db.insert('Sync_Config', {'id': 1, 'sucursal_id': _sucursalId, 'sucursal_nombre': 'Principal'});
  }

  Future<Map<String, dynamic>> filaDe(String tabla, String columnaId, int id) async {
    return (await db.query(tabla, where: '$columnaId = ?', whereArgs: [id])).first;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pvapp_entity_mapper_3c_test');
    final path = join(tempDir.path, 'test.db');
    db = await DatabaseHelper().abrirEnRuta(path);
    resolver = FkResolver(db);
    AppConfig.actualizar(Configuracion.porDefecto());
  });

  tearDown(() async {
    await db.close();
    AppConfig.actualizar(Configuracion.porDefecto());
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProductoMapper', () {
    test('aBackend calcula IVA a partir de la tasa global cuando aplica', () async {
      AppConfig.actualizar(Configuracion.porDefecto().copyWith(tasaImpuestoPorcentaje: 16));
      final idCategoria = await crearCategoria();
      final idProducto = await crearProducto(idCategoria: idCategoria, precio: 116.0, precioCompra: 80.0);
      final filaLocal = await filaDe('Producto', 'id_producto', idProducto);

      final payload = await ProductoMapper().aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );

      expect(payload['aplicaIva'], isTrue);
      expect(payload['tasaIva'], closeTo(0.16, 0.0001));
      expect(payload['precioBase'], closeTo(100.0, 0.01));
      expect(payload['precioVenta'], 116.0);
      expect(payload['costoPromedio'], 80.0);
      expect(payload['categoriaId'], isNotNull);
      expect(payload['codigo'], 'COD123');
    });

    test('aBackend no aplica IVA cuando la tasa global es 0', () async {
      final idCategoria = await crearCategoria();
      final idProducto = await crearProducto(idCategoria: idCategoria, precio: 50.0);
      final filaLocal = await filaDe('Producto', 'id_producto', idProducto);

      final payload = await ProductoMapper().aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );

      expect(payload['aplicaIva'], isFalse);
      expect(payload['precioBase'], 50.0);
    });

    test('aBackend usa un código de barras sintético cuando no hay uno local', () async {
      final idCategoria = await crearCategoria();
      final idProducto = await DatabaseHelper.insertarConGuidSync(db, 'Producto', {
        'nombre': 'Sin código',
        'precio': 10.0,
        'id_categoria': idCategoria,
      });
      final filaLocal = await filaDe('Producto', 'id_producto', idProducto);

      final payload = await ProductoMapper().aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );

      expect(payload['codigo'], 'SIN-CODIGO-$idProducto');
    });

    test('aBackend lanza StateError si el producto no tiene categoría resuelta', () async {
      final idProducto = await crearProducto();
      final filaLocal = await filaDe('Producto', 'id_producto', idProducto);

      expect(
        () => ProductoMapper().aBackend(
          filaLocal: filaLocal,
          tenantId: _tenantId,
          usuarioIdSync: _usuarioIdSync,
          resolver: resolver,
        ),
        throwsStateError,
      );
    });

    test('upsertLocal inserta el producto Y su fila Inventario en cantidad 0', () async {
      final idCategoriaLocal = await crearCategoria();
      final categoriaGuid = (await filaDe('Categorias', 'id_categoria', idCategoriaLocal))['guid_sync'] as String;

      await ProductoMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-producto-1',
          'nombre': 'Producto Backend',
          'descripcion': null,
          'categoriaId': categoriaGuid,
          'precioVenta': 99.0,
          'costoPromedio': 60.0,
          'codigo': 'ABC',
          'stockMinimo': 5,
          'activo': true,
          'isDeleted': false,
        },
        resolver: resolver,
      );

      final productos = await db.query('Producto', where: 'guid_sync = ?', whereArgs: ['guid-producto-1']);
      expect(productos, hasLength(1));
      final idProducto = productos.first['id_producto'] as int;

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario, hasLength(1));
      expect(inventario.first['cantidad'], 0);
    });
  });

  group('StockMapper', () {
    test('upsertLocal ignora el elemento si no hay sucursal configurada localmente', () async {
      final idProducto = await crearProducto();
      final productoGuid = (await filaDe('Producto', 'id_producto', idProducto))['guid_sync'] as String;

      await StockMapper().upsertLocal(
        db: db,
        elementoBackend: {'id': 'guid-stock-1', 'productoId': productoGuid, 'sucursalId': _sucursalId, 'cantidadDisponible': 99},
        resolver: resolver,
      );

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario.first['cantidad'], 10); // sin cambios, se ignoró
    });

    test('upsertLocal ignora el elemento si la sucursal no coincide con la configurada', () async {
      await configurarSucursal();
      final idProducto = await crearProducto();
      final productoGuid = (await filaDe('Producto', 'id_producto', idProducto))['guid_sync'] as String;

      await StockMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-stock-1',
          'productoId': productoGuid,
          'sucursalId': 'otra-sucursal-distinta',
          'cantidadDisponible': 99,
        },
        resolver: resolver,
      );

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario.first['cantidad'], 10);
    });

    test('upsertLocal actualiza la cantidad cuando la sucursal coincide y el producto ya existe', () async {
      await configurarSucursal();
      final idProducto = await crearProducto();
      final productoGuid = (await filaDe('Producto', 'id_producto', idProducto))['guid_sync'] as String;

      await StockMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-stock-1',
          'productoId': productoGuid,
          'sucursalId': _sucursalId,
          'cantidadDisponible': 77,
        },
        resolver: resolver,
      );

      final inventario = await db.query('Inventario', where: 'id_producto = ?', whereArgs: [idProducto]);
      expect(inventario.first['cantidad'], 77);
    });

    test('aBackend lanza UnsupportedError (pull-only)', () {
      expect(
        () => StockMapper().aBackend(filaLocal: const {}, tenantId: _tenantId, usuarioIdSync: _usuarioIdSync, resolver: resolver),
        throwsUnsupportedError,
      );
    });
  });

  group('PromocionMapper', () {
    test('aBackend traduce el tipo local (SCREAMING_SNAKE) al enum del backend', () async {
      final idPromocion = await DatabaseHelper.insertarConGuidSync(db, 'Promociones', {
        'nombre': '2x1 Refrescos',
        'tipo': 'NXY',
        'activo': 1,
        'prioridad': 1,
        'combinable': 0,
        'nx_lleva': 2,
        'nx_paga': 1,
        'fecha_creacion': '2026-01-01T00:00:00Z',
      });
      final filaLocal = await filaDe('Promociones', 'id_promocion', idPromocion);

      final payload = await PromocionMapper().aBackend(
        filaLocal: filaLocal,
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );

      expect(payload['tipo'], 'NxY');
      expect(payload['nxLleva'], 2);
      expect(payload['nxPaga'], 1);
    });

    test('upsertLocal hace round-trip completo del tipo backend -> local', () async {
      await PromocionMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-promo-1',
          'nombre': 'Descuento combo',
          'tipo': 'Combo',
          'activo': true,
          'prioridad': 0,
          'combinable': false,
          'precioCombo': 199.0,
          'fechaInicio': '2026-01-01T00:00:00Z',
          'fechaFin': null,
          'isDeleted': false,
        },
        resolver: resolver,
      );

      final promos = await db.query('Promociones', where: 'guid_sync = ?', whereArgs: ['guid-promo-1']);
      expect(promos.first['tipo'], 'COMBO');
      expect(promos.first['precio_combo'], 199.0);
    });
  });

  group('Cadena Venta -> Detalle -> Pago -> Promocion', () {
    test('cada mapper resuelve sus FKs correctamente al armar el payload de push', () async {
      await configurarSucursal();
      final idUsuarioLocal = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuarioLocal);
      final idCliente = await crearCliente();
      final idCategoria = await crearCategoria();
      final idProducto = await crearProducto(idCategoria: idCategoria);

      final idVenta = await DatabaseHelper.insertarConGuidSync(db, 'Ventas', {
        'id_cliente': idCliente,
        'id_caja': idCaja,
        'fecha': '2026-01-01T10:00:00Z',
        'total': 116.0,
        'metodo_pago': 'efectivo',
        'estado': 'Activa',
        'subtotal': 116.0,
        'descuento_total': 0,
        'cambio': 4.0,
      });

      final ventaPayload = await VentaMapper().aBackend(
        filaLocal: await filaDe('Ventas', 'id_venta', idVenta),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(ventaPayload['sucursalId'], _sucursalId);
      expect(ventaPayload['usuarioId'], _usuarioIdSync);
      expect(ventaPayload['cajaSesionId'], isNotNull);
      expect(ventaPayload['clienteId'], isNotNull);
      expect(ventaPayload['estado'], 'Completada');
      expect(ventaPayload['metodoPago'], 'Efectivo');
      expect(ventaPayload['montoRecibido'], 120.0); // total + cambio

      final idDetalle = await DatabaseHelper.insertarConGuidSync(db, 'Detalle_Venta', {
        'id_venta': idVenta,
        'id_producto': idProducto,
        'cantidad': 1,
        'precio': 116.0,
        'precio_neto': 116.0,
      });
      final detallePayload = await VentaDetalleMapper().aBackend(
        filaLocal: await filaDe('Detalle_Venta', 'id_detalleV', idDetalle),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(detallePayload['ventaId'], ventaPayload['id']);
      expect(detallePayload['productoId'], isNotNull);
      expect(detallePayload['subtotal'], 116.0);

      final idPago = await DatabaseHelper.insertarConGuidSync(db, 'Venta_Pagos', {
        'id_venta': idVenta,
        'metodo_pago': 'efectivo',
        'monto': 116.0,
      });
      final pagoPayload = await VentaPagoMapper().aBackend(
        filaLocal: await filaDe('Venta_Pagos', 'id', idPago),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(pagoPayload['ventaId'], ventaPayload['id']);
      expect(pagoPayload['metodoPago'], 'Efectivo');

      final idVentaPromocion = await DatabaseHelper.insertarConGuidSync(db, 'Venta_Promociones', {
        'id_venta': idVenta,
        'id_promocion': null,
        'nombre_snapshot': 'Promo borrada',
        'tipo_snapshot': 'PORCENTAJE_PRODUCTO',
        'ahorro_total': 10.0,
      });
      final promoPayload = await VentaPromocionMapper().aBackend(
        filaLocal: await filaDe('Venta_Promociones', 'id_venta_promocion', idVentaPromocion),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(promoPayload['ventaId'], ventaPayload['id']);
      expect(promoPayload['promocionId'], isNull);
      expect(promoPayload['tipo'], 'PorcentajeProducto');
    });

    test('VentaMapper.aBackend lanza StateError sin sucursal configurada', () async {
      final idUsuarioLocal = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuarioLocal);
      final idVenta = await DatabaseHelper.insertarConGuidSync(db, 'Ventas', {
        'id_caja': idCaja,
        'fecha': '2026-01-01T10:00:00Z',
        'total': 100.0,
        'metodo_pago': 'efectivo',
      });

      final filaLocal = await filaDe('Ventas', 'id_venta', idVenta);
      expect(
        () => VentaMapper().aBackend(
          filaLocal: filaLocal,
          tenantId: _tenantId,
          usuarioIdSync: _usuarioIdSync,
          resolver: resolver,
        ),
        throwsStateError,
      );
    });

    test('VentaDetalleMapper.upsertLocal aplaza el elemento si su Venta todavía no llegó por pull', () async {
      await VentaDetalleMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-detalle-huerfano',
          'ventaId': 'guid-venta-inexistente',
          'productoId': 'guid-producto-inexistente',
          'cantidad': 1,
          'precioUnitario': 10.0,
          'subtotal': 10.0,
        },
        resolver: resolver,
      );

      final filas = await db.query('Detalle_Venta', where: 'guid_sync = ?', whereArgs: ['guid-detalle-huerfano']);
      expect(filas, isEmpty);
    });
  });

  group('CajaSesionMapper', () {
    test('upsertLocal ignora una sesión nueva que este dispositivo no abrió (gap de identidad documentado)', () async {
      await CajaSesionMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-caja-remota',
          'fechaApertura': '2026-01-01T08:00:00Z',
          'montoApertura': 500.0,
          'estado': 'Abierta',
        },
        resolver: resolver,
      );

      final filas = await db.query('Cajas', where: 'guid_sync = ?', whereArgs: ['guid-caja-remota']);
      expect(filas, isEmpty);
    });

    test('upsertLocal SÍ actualiza una sesión que este dispositivo ya conoce', () async {
      final idUsuario = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuario);
      final guid = (await filaDe('Cajas', 'id_caja', idCaja))['guid_sync'] as String;

      await CajaSesionMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': guid,
          'fechaApertura': '2026-01-01T08:00:00Z',
          'montoApertura': 500.0,
          'fechaCierre': '2026-01-01T20:00:00Z',
          'montoCierreDeclarado': 950.0,
          'montoCierreSistema': 940.0,
          'diferencia': 10.0,
          'estado': 'Cerrada',
        },
        resolver: resolver,
      );

      final caja = await filaDe('Cajas', 'id_caja', idCaja);
      expect(caja['estado'], 'Cerrada');
      expect(caja['efectivo_contado'], 950.0);
    });

    test('aBackend arma el payload con sucursal y usuario de sync', () async {
      await configurarSucursal();
      final idUsuario = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuario);

      final payload = await CajaSesionMapper().aBackend(
        filaLocal: await filaDe('Cajas', 'id_caja', idCaja),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );

      expect(payload['sucursalId'], _sucursalId);
      expect(payload['usuarioId'], _usuarioIdSync);
      expect(payload['estado'], 'Abierta');
      expect(payload['montoApertura'], 500.0);
    });
  });

  group('Bitácoras: MovimientoCaja, CorteCaja, MovimientoInventario', () {
    test('MovimientoCajaMapper hace round-trip completo', () async {
      await configurarSucursal();
      final idUsuario = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuario);
      final cajaGuid = (await filaDe('Cajas', 'id_caja', idCaja))['guid_sync'] as String;

      final idMovimiento = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Caja', {
        'id_caja': idCaja,
        'tipo_movimiento': 'VentaEfectivo',
        'monto': 116.0,
        'fecha': '2026-01-01T10:05:00Z',
      });

      final payload = await MovimientoCajaMapper().aBackend(
        filaLocal: await filaDe('Movimiento_Caja', 'id_movimiento_caja', idMovimiento),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(payload['cajaSesionId'], cajaGuid);
      expect(payload['tipoMovimiento'], 'VentaEfectivo');
      expect(payload['usuarioId'], _usuarioIdSync);

      await MovimientoCajaMapper().upsertLocal(
        db: db,
        elementoBackend: {
          'id': 'guid-mov-caja-pull',
          'cajaSesionId': cajaGuid,
          'tipoMovimiento': 'SalidaManual',
          'monto': 50.0,
          'fecha': '2026-01-01T11:00:00Z',
        },
        resolver: resolver,
      );
      final pulled = await db.query('Movimiento_Caja', where: 'guid_sync = ?', whereArgs: ['guid-mov-caja-pull']);
      expect(pulled.first['id_caja'], idCaja);
    });

    test('CorteCajaMapper hace round-trip completo', () async {
      final idUsuario = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuario);
      final cajaGuid = (await filaDe('Cajas', 'id_caja', idCaja))['guid_sync'] as String;

      final idCorte = await DatabaseHelper.insertarConGuidSync(db, 'Corte_Caja', {
        'id_caja': idCaja,
        'total_efectivo_sistema': 500.0,
        'total_tarjeta_sistema': 0.0,
        'total_transferencia_sistema': 0.0,
        'total_efectivo_contado': 495.0,
        'diferencia': -5.0,
        'fecha_corte': '2026-01-01T20:00:00Z',
      });

      final payload = await CorteCajaMapper().aBackend(
        filaLocal: await filaDe('Corte_Caja', 'id_corte', idCorte),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(payload['cajaSesionId'], cajaGuid);
      expect(payload['diferencia'], -5.0);
    });

    test('MovimientoInventarioMapper resuelve referenciaId solo cuando referencia_tipo es Venta', () async {
      await configurarSucursal();
      final idCategoria = await crearCategoria();
      final idProducto = await crearProducto(idCategoria: idCategoria);
      final idUsuario = await crearUsuarioLocal();
      final idCaja = await crearCaja(idUsuario);
      final idVenta = await DatabaseHelper.insertarConGuidSync(db, 'Ventas', {
        'id_caja': idCaja,
        'fecha': '2026-01-01T10:00:00Z',
        'total': 20.0,
        'metodo_pago': 'efectivo',
      });

      final idMovConVenta = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Inventario', {
        'id_producto': idProducto,
        'tipo_movimiento': 'SalidaVenta',
        'cantidad': 1,
        'cantidad_anterior': 10,
        'cantidad_nueva': 9,
        'referencia_tipo': 'Venta',
        'referencia_id': idVenta,
        'fecha': '2026-01-01T10:00:00Z',
      });
      final payloadConVenta = await MovimientoInventarioMapper().aBackend(
        filaLocal: await filaDe('Movimiento_Inventario', 'id_movimiento', idMovConVenta),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(payloadConVenta['referenciaId'], isNotNull);

      final idMovConCompra = await DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Inventario', {
        'id_producto': idProducto,
        'tipo_movimiento': 'EntradaCompra',
        'cantidad': 5,
        'cantidad_anterior': 9,
        'cantidad_nueva': 14,
        'referencia_tipo': 'Compra',
        'referencia_id': 1,
        'fecha': '2026-01-01T11:00:00Z',
      });
      final payloadConCompra = await MovimientoInventarioMapper().aBackend(
        filaLocal: await filaDe('Movimiento_Inventario', 'id_movimiento', idMovConCompra),
        tenantId: _tenantId,
        usuarioIdSync: _usuarioIdSync,
        resolver: resolver,
      );
      expect(payloadConCompra['referenciaId'], isNull); // Compra no es sincronizable
      expect(payloadConCompra['referenciaTipo'], 'Compra');
    });
  });

  group('EntityMapperRegistry (completo tras 3c)', () {
    test('las 14 entidades de esta fase tienen mapper registrado', () {
      const entidades = [
        'CategoriaProducto', 'Producto', 'Cliente', 'Proveedor', 'Stock', 'Promocion',
        'CajaSesion', 'Venta', 'VentaDetalle', 'VentaPago', 'VentaPromocion',
        'MovimientoInventario', 'MovimientoCaja', 'CorteCaja',
      ];
      for (final entidad in entidades) {
        expect(EntityMapperRegistry.tieneMapper(entidad), isTrue, reason: 'falta mapper para $entidad');
      }
      expect(EntityMapperRegistry.ordenPull, unorderedEquals(entidades));
    });

    test('ordenPull respeta padre-antes-que-hijo para la cadena de Venta', () {
      final orden = EntityMapperRegistry.ordenPull;
      expect(orden.indexOf('CajaSesion'), lessThan(orden.indexOf('Venta')));
      expect(orden.indexOf('Venta'), lessThan(orden.indexOf('VentaDetalle')));
      expect(orden.indexOf('Venta'), lessThan(orden.indexOf('VentaPago')));
      expect(orden.indexOf('Producto'), lessThan(orden.indexOf('Stock')));
      expect(orden.indexOf('CategoriaProducto'), lessThan(orden.indexOf('Producto')));
    });
  });
}
