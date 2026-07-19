import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/utils/pagos_mixtos.dart';
import 'cuentas_por_pagar_controller.dart';

/// Resumen de ventas para un rango de fechas: totales + top productos +
/// listado reciente. Mismas columnas que ya consumía `reporte_view.dart`.
class ReporteVentasResumen {
  final int totalVentas;
  final double ingresosTotales;
  final List<Map<String, dynamic>> productosVendidos;
  final List<Map<String, dynamic>> ventasRecientes;

  const ReporteVentasResumen({
    required this.totalVentas,
    required this.ingresosTotales,
    required this.productosVendidos,
    required this.ventasRecientes,
  });
}

/// Resumen de compras para un rango de fechas, análogo a
/// [ReporteVentasResumen].
class ReporteComprasResumen {
  final int totalCompras;
  final double gastoTotal;
  final List<Map<String, dynamic>> productosComprados;
  final List<Map<String, dynamic>> comprasRecientes;

  const ReporteComprasResumen({
    required this.totalCompras,
    required this.gastoTotal,
    required this.productosComprados,
    required this.comprasRecientes,
  });
}

/// Resumen de ahorro por promociones automáticas en un rango de fechas,
/// agrupado por promoción (usando el nombre/tipo snapshot guardado en cada
/// venta, no la definición actual de `Promociones` — así una promoción ya
/// editada o borrada sigue apareciendo con los datos que tenía cuando se
/// aplicó).
class ReportePromocionesResumen {
  final double ahorroTotal;
  final List<Map<String, dynamic>> porPromocion;

  const ReportePromocionesResumen({
    required this.ahorroTotal,
    required this.porPromocion,
  });
}

/// Resumen de Apartados: conteo por estado dentro de un rango de creación,
/// más el monto reservado y el saldo pendiente *actuales* (sin filtrar por
/// fecha — un apartado `Pendiente` creado el mes pasado sigue comprometiendo
/// dinero/stock hoy, independientemente de cuándo se creó).
class ReporteApartadosResumen {
  final int totalApartados;
  final int pendientes;
  final int liquidados;
  final int cancelados;
  final int vencidos;
  final double montoReservado;
  final double saldoPendienteTotal;
  final List<Map<String, dynamic>> apartadosRecientes;

  const ReporteApartadosResumen({
    required this.totalApartados,
    required this.pendientes,
    required this.liquidados,
    required this.cancelados,
    required this.vencidos,
    required this.montoReservado,
    required this.saldoPendienteTotal,
    required this.apartadosRecientes,
  });
}

/// Resumen de cuentas por pagar a proveedores: deuda total/por proveedor,
/// compras pendientes/vencidas, pagos hechos en el rango, próximos
/// vencimientos y cuánto de esos pagos salió en efectivo de alguna caja.
/// El saldo/estado de cada compra siempre se calcula en vivo (ver
/// [CuentasPorPagarController]), nunca se guarda como campo editable.
class ReporteCuentasPorPagarResumen {
  final double deudaTotal;
  final List<Map<String, dynamic>> deudaPorProveedor;
  final List<Map<String, dynamic>> comprasPendientes;
  final List<Map<String, dynamic>> comprasVencidas;
  final List<Map<String, dynamic>> pagosRealizados;
  final List<Map<String, dynamic>> proximosVencimientos;
  final double salidasCajaEfectivo;

  const ReporteCuentasPorPagarResumen({
    required this.deudaTotal,
    required this.deudaPorProveedor,
    required this.comprasPendientes,
    required this.comprasVencidas,
    required this.pagosRealizados,
    required this.proximosVencimientos,
    required this.salidasCajaEfectivo,
  });
}

/// Consultas de reportes (ventas/compras por rango, detalle para reimprimir
/// un ticket). Antes vivían como `rawQuery` directamente dentro de
/// `reporte_view.dart`.
class ReporteController {
  final _cuentasPorPagarController = CuentasPorPagarController();
  Future<ReporteVentasResumen> obtenerReporteVentas({
    required DateTime desde,
    required DateTime hasta,
    required bool filtrarPorUsuario,
    int? usuarioId,
  }) async {
    final db = await DatabaseHelper().database;

    final fechaInicio = desde.toIso8601String().substring(0, 10);
    final fechaFin = hasta.toIso8601String().substring(0, 10);

    final filtroUsuario = filtrarPorUsuario ? 'AND id_usuario = ?' : '';
    final params = filtrarPorUsuario
        ? [fechaInicio, fechaFin, usuarioId]
        : [fechaInicio, fechaFin];

    // El ingreso de cada venta descuenta lo que ya se le haya devuelto
    // (Detalle_Devolucion); las canceladas se excluyen por completo del
    // total y del conteo, pero no se borran ni dejan de listarse abajo.
    final summary = await db.rawQuery(
      '''
      SELECT
        COUNT(*) as ventas,
        IFNULL(SUM(
          Ventas.total - IFNULL((
            SELECT SUM(dd.cantidad * dd.precio)
            FROM Detalle_Devolucion dd
            INNER JOIN Devoluciones d ON d.id_devolucion = dd.id_devolucion
            WHERE d.id_venta = Ventas.id_venta
          ), 0)
        ), 0) as ingresos
      FROM Ventas
      WHERE date(fecha) BETWEEN date(?) AND date(?)
        AND IFNULL(estado, 'Activa') != 'Cancelada'
      $filtroUsuario
      ''',
      params,
    );

    final productos = await db.rawQuery(
      '''
      SELECT
        Producto.nombre,
        SUM(Detalle_Venta.cantidad) as total

      FROM Detalle_Venta

      INNER JOIN Ventas
        ON Ventas.id_venta = Detalle_Venta.id_venta

      INNER JOIN Producto
        ON Producto.id_producto = Detalle_Venta.id_producto

      WHERE date(Ventas.fecha)
        BETWEEN date(?) AND date(?)

      ${filtrarPorUsuario ? 'AND Ventas.id_usuario = ?' : ''}

      GROUP BY Producto.nombre
      ORDER BY total DESC
      LIMIT 10
      ''',
      params,
    );

    // El listado sí incluye ventas canceladas/parcialmente devueltas (con
    // su estado visible), a diferencia del resumen de arriba: aquí es
    // historial consultable, no el total de ingresos.
    final ventas = await db.rawQuery(
      '''
      SELECT
        Ventas.id_venta,
        Ventas.fecha,
        Ventas.total,
        Ventas.metodo_pago,
        IFNULL(Ventas.estado, 'Activa') as estado,
        Clientes.nombre as cliente,
        (Ventas.total - IFNULL((
          SELECT SUM(dd.cantidad * dd.precio)
          FROM Detalle_Devolucion dd
          INNER JOIN Devoluciones d ON d.id_devolucion = dd.id_devolucion
          WHERE d.id_venta = Ventas.id_venta
        ), 0)) as total_neto

      FROM Ventas

      LEFT JOIN Clientes
        ON Clientes.id_cliente = Ventas.id_cliente

      WHERE date(fecha)
        BETWEEN date(?) AND date(?)

      $filtroUsuario

      ORDER BY fecha DESC
      LIMIT 20
      ''',
      params,
    );

    return ReporteVentasResumen(
      totalVentas: summary.first['ventas'] as int? ?? 0,
      ingresosTotales: (summary.first['ingresos'] as num?)?.toDouble() ?? 0,
      productosVendidos: productos,
      ventasRecientes: ventas,
    );
  }

  Future<ReporteComprasResumen> obtenerReporteCompras({
    required DateTime desde,
    required DateTime hasta,
    required bool filtrarPorUsuario,
    int? usuarioId,
  }) async {
    final db = await DatabaseHelper().database;

    final fechaInicio = desde.toIso8601String().substring(0, 10);
    final fechaFin = hasta.toIso8601String().substring(0, 10);

    final params = filtrarPorUsuario
        ? [fechaInicio, fechaFin, usuarioId]
        : [fechaInicio, fechaFin];

    final summary = await db.rawQuery(
      '''
      SELECT
        COUNT(*) as compras,
        IFNULL(SUM(total), 0) as gasto
      FROM Compras
      WHERE date(fecha) BETWEEN date(?) AND date(?)
      ${filtrarPorUsuario ? 'AND id_usuario = ?' : ''}
      ''',
      params,
    );

    final productos = await db.rawQuery(
      '''
      SELECT
        Producto.nombre,
        SUM(IFNULL(Detalle_Compra.cantidad, 1)) as total
      FROM Detalle_Compra
      INNER JOIN Compras ON Compras.id_compra = Detalle_Compra.id_compra
      INNER JOIN Producto ON Producto.id_producto = Detalle_Compra.id_producto
      WHERE date(Compras.fecha) BETWEEN date(?) AND date(?)
      ${filtrarPorUsuario ? 'AND Compras.id_usuario = ?' : ''}
      GROUP BY Producto.nombre
      ORDER BY total DESC
      LIMIT 10
      ''',
      params,
    );

    final compras = await db.rawQuery(
      '''
      SELECT
        Compras.id_compra,
        Compras.fecha,
        Compras.total,
        Proveedores.nombre as proveedor
      FROM Compras
      LEFT JOIN Proveedores
        ON Proveedores.id_proveedor = Compras.id_proveedor
      WHERE date(Compras.fecha) BETWEEN date(?) AND date(?)
      ${filtrarPorUsuario ? 'AND Compras.id_usuario = ?' : ''}
      ORDER BY Compras.fecha DESC
      LIMIT 20
      ''',
      params,
    );

    return ReporteComprasResumen(
      totalCompras: summary.first['compras'] as int? ?? 0,
      gastoTotal: (summary.first['gasto'] as num?)?.toDouble() ?? 0,
      productosComprados: productos,
      comprasRecientes: compras,
    );
  }

  /// Ingresos netos por método de pago dentro de un rango de fechas, para el
  /// desglose de reportes. Se agrega sobre `Venta_Pagos` (no sobre
  /// `Ventas.metodo_pago`, que para ventas con pagos mixtos vale 'Mixto').
  /// Las devoluciones siempre se reembolsan en efectivo (ver
  /// `DevolucionesController`), así que se restan únicamente del bucket
  /// 'Efectivo', sin importar el método de la venta original.
  Future<Map<String, double>> obtenerTotalesPorMetodoPago({
    required DateTime desde,
    required DateTime hasta,
    required bool filtrarPorUsuario,
    int? usuarioId,
  }) async {
    final db = await DatabaseHelper().database;

    final fechaInicio = desde.toIso8601String().substring(0, 10);
    final fechaFin = hasta.toIso8601String().substring(0, 10);

    final filtroUsuario = filtrarPorUsuario ? 'AND Ventas.id_usuario = ?' : '';
    final params = filtrarPorUsuario
        ? [fechaInicio, fechaFin, usuarioId]
        : [fechaInicio, fechaFin];

    final rows = await db.rawQuery(
      '''
      SELECT Venta_Pagos.metodo_pago as metodo, IFNULL(SUM(Venta_Pagos.monto), 0) as total
      FROM Venta_Pagos
      INNER JOIN Ventas ON Ventas.id_venta = Venta_Pagos.id_venta
      WHERE date(Ventas.fecha) BETWEEN date(?) AND date(?)
        AND IFNULL(Ventas.estado, 'Activa') != 'Cancelada'
      $filtroUsuario
      GROUP BY Venta_Pagos.metodo_pago
      ''',
      params,
    );

    final totales = <String, double>{
      for (final row in rows) row['metodo'].toString(): (row['total'] as num).toDouble(),
    };

    // Anticipos/abonos de Apartados: dinero real recibido por método de
    // pago, aparte de Venta_Pagos (una venta que vino de liquidar un
    // apartado no tiene filas propias ahí — ver `ApartadosController._liquidar`).
    // Se reportan por su fecha real, no por la fecha de liquidación.
    final filtroUsuarioAnticipos = filtrarPorUsuario ? 'AND Apartado_Abonos.id_usuario = ?' : '';
    final anticiposRows = await db.rawQuery(
      '''
      SELECT Apartado_Abono_Pagos.metodo_pago as metodo, IFNULL(SUM(Apartado_Abono_Pagos.monto), 0) as total
      FROM Apartado_Abono_Pagos
      INNER JOIN Apartado_Abonos ON Apartado_Abonos.id_abono = Apartado_Abono_Pagos.id_abono
      WHERE date(Apartado_Abonos.fecha) BETWEEN date(?) AND date(?)
      $filtroUsuarioAnticipos
      GROUP BY Apartado_Abono_Pagos.metodo_pago
      ''',
      params,
    );
    for (final row in anticiposRows) {
      final metodo = row['metodo'].toString();
      totales[metodo] = (totales[metodo] ?? 0) + (row['total'] as num).toDouble();
    }

    final devolucionesRes = await db.rawQuery(
      '''
      SELECT IFNULL(SUM(Devoluciones.importe), 0) as total
      FROM Devoluciones
      WHERE date(Devoluciones.fecha_hora) BETWEEN date(?) AND date(?)
      ''',
      [fechaInicio, fechaFin],
    );
    final devoluciones = (devolucionesRes.first['total'] as num).toDouble();

    final claveEfectivo = totales.keys.firstWhere(
      esMetodoEfectivo,
      orElse: () => 'Efectivo',
    );
    totales[claveEfectivo] = (totales[claveEfectivo] ?? 0) - devoluciones;
    if (totales[claveEfectivo]! < 0) totales[claveEfectivo] = 0;

    return totales;
  }

  /// Desglose de pagos de una venta ya registrada, para reimprimir el
  /// ticket con la misma lista de métodos/montos que se cobró.
  ///
  /// Si la venta viene de liquidar un Apartado (`id_apartado` no nulo), no
  /// tiene filas propias en `Venta_Pagos` (ver `ApartadosController._liquidar`
  /// — evita contar ese dinero dos veces en Caja/Reportes): en ese caso se
  /// lee el historial completo de abonos del apartado en su lugar.
  Future<List<Map<String, dynamic>>> obtenerPagosVenta(int idVenta) async {
    final db = await DatabaseHelper().database;

    final idApartado = await _idApartadoDeVenta(db, idVenta);
    if (idApartado != null) {
      return db.rawQuery('''
        SELECT Apartado_Abono_Pagos.metodo_pago, Apartado_Abono_Pagos.monto
        FROM Apartado_Abono_Pagos
        INNER JOIN Apartado_Abonos ON Apartado_Abonos.id_abono = Apartado_Abono_Pagos.id_abono
        WHERE Apartado_Abonos.id_apartado = ?
      ''', [idApartado]);
    }

    return db.query(
      'Venta_Pagos',
      columns: ['metodo_pago', 'monto'],
      where: 'id_venta = ?',
      whereArgs: [idVenta],
    );
  }

  Future<int?> _idApartadoDeVenta(DatabaseExecutor db, int idVenta) async {
    final rows = await db.query('Ventas', columns: ['id_apartado'], where: 'id_venta = ?', whereArgs: [idVenta], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id_apartado'] as int?;
  }

  /// Detalle de una venta ya con la forma de "carrito" que espera
  /// [TicketService.generarTicket] para reimprimir el ticket.
  Future<List<Map<String, dynamic>>> obtenerDetalleVentaParaTicket(int idVenta) async {
    final db = await DatabaseHelper().database;

    final detalles = await db.rawQuery(
      '''
      SELECT Producto.nombre, Detalle_Venta.cantidad, Detalle_Venta.precio,
             Detalle_Venta.descuento_monto
      FROM Detalle_Venta
      INNER JOIN Producto ON Producto.id_producto = Detalle_Venta.id_producto
      WHERE Detalle_Venta.id_venta = ?
      ''',
      [idVenta],
    );

    return detalles.map((item) {
      return {
        'id_producto': null,
        'nombre': item['nombre'],
        'precio': item['precio'],
        'cantidad': item['cantidad'],
        'descuento_monto': item['descuento_monto'],
      };
    }).toList();
  }

  /// Subtotal/descuento/total/cambio de una venta ya registrada, para
  /// reimprimir el ticket con el mismo desglose que se mostró al momento de
  /// la venta.
  Future<({double subtotal, double descuentoTotal, double total, double cambio, String metodoPago})>
      obtenerTotalesVentaParaTicket(int idVenta) async {
    final db = await DatabaseHelper().database;

    final rows = await db.query(
      'Ventas',
      columns: ['subtotal', 'descuento_total', 'total', 'cambio', 'metodo_pago'],
      where: 'id_venta = ?',
      whereArgs: [idVenta],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('La venta no existe.');
    }

    final venta = rows.first;
    final total = (venta['total'] as num?)?.toDouble() ?? 0;

    return (
      subtotal: (venta['subtotal'] as num?)?.toDouble() ?? total,
      descuentoTotal: (venta['descuento_total'] as num?)?.toDouble() ?? 0,
      total: total,
      cambio: (venta['cambio'] as num?)?.toDouble() ?? 0,
      metodoPago: venta['metodo_pago']?.toString() ?? 'efectivo',
    );
  }

  /// Promociones aplicadas a una venta ya registrada (el snapshot guardado
  /// por `VentasController.insertarVentaCompleta`), para reimprimir el
  /// ticket con la misma sección de "Promociones aplicadas" que se mostró
  /// al momento de la venta. No vuelve a evaluar el motor.
  ///
  /// Si la venta viene de liquidar un Apartado, el snapshot de promociones
  /// no vive en `Venta_Promociones` sino en `Apartado_Promociones` (mismo
  /// motivo que en [obtenerPagosVenta]).
  Future<List<Map<String, dynamic>>> obtenerPromocionesVenta(int idVenta) async {
    final db = await DatabaseHelper().database;

    final idApartado = await _idApartadoDeVenta(db, idVenta);
    if (idApartado != null) {
      return db.query(
        'Apartado_Promociones',
        columns: ['nombre_snapshot', 'tipo_snapshot', 'ahorro_total'],
        where: 'id_apartado = ?',
        whereArgs: [idApartado],
      );
    }

    return db.query(
      'Venta_Promociones',
      columns: ['nombre_snapshot', 'tipo_snapshot', 'ahorro_total'],
      where: 'id_venta = ?',
      whereArgs: [idVenta],
    );
  }

  /// Ahorro total y desglose por promoción dentro de un rango de fechas,
  /// para el reporte de promociones. Ventas canceladas se excluyen, igual
  /// que en [obtenerReporteVentas].
  Future<ReportePromocionesResumen> obtenerReportePromocionesResumen({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final db = await DatabaseHelper().database;

    final fechaInicio = desde.toIso8601String().substring(0, 10);
    final fechaFin = hasta.toIso8601String().substring(0, 10);

    final filas = await db.rawQuery(
      '''
      SELECT
        vp.nombre_snapshot as nombre,
        vp.tipo_snapshot as tipo,
        COUNT(*) as veces_aplicada,
        IFNULL(SUM(vp.ahorro_total), 0) as ahorro
      FROM Venta_Promociones vp
      INNER JOIN Ventas v ON v.id_venta = vp.id_venta
      WHERE date(v.fecha) BETWEEN date(?) AND date(?)
        AND IFNULL(v.estado, 'Activa') != 'Cancelada'
      GROUP BY vp.nombre_snapshot, vp.tipo_snapshot
      ORDER BY ahorro DESC
      ''',
      [fechaInicio, fechaFin],
    );

    final ahorroTotal = filas.fold<double>(0, (s, f) => s + (f['ahorro'] as num).toDouble());

    return ReportePromocionesResumen(ahorroTotal: ahorroTotal, porPromocion: filas);
  }

  /// Resumen de Apartados creados en el rango [desde]/[hasta] (conteo por
  /// estado) más el monto reservado y saldo pendiente *actuales* de todo
  /// apartado todavía activo (`Pendiente`/`Vencido`), sin importar cuándo se
  /// creó.
  Future<ReporteApartadosResumen> obtenerReporteApartados({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final db = await DatabaseHelper().database;

    final fechaInicio = desde.toIso8601String().substring(0, 10);
    final fechaFin = hasta.toIso8601String().substring(0, 10);

    final conteoPorEstado = await db.rawQuery('''
      SELECT estado, COUNT(*) as total
      FROM Apartados
      WHERE date(fecha_creacion) BETWEEN date(?) AND date(?)
      GROUP BY estado
    ''', [fechaInicio, fechaFin]);

    int conteoDe(String estado) {
      for (final row in conteoPorEstado) {
        if (row['estado'] == estado) return row['total'] as int;
      }
      return 0;
    }

    final activosRes = await db.rawQuery('''
      SELECT
        IFNULL(SUM(Apartados.total), 0) as monto_reservado,
        IFNULL(SUM(Apartados.total - IFNULL((
          SELECT SUM(monto) FROM Apartado_Abonos WHERE Apartado_Abonos.id_apartado = Apartados.id_apartado
        ), 0)), 0) as saldo_pendiente
      FROM Apartados
      WHERE estado IN ('Pendiente', 'Vencido')
    ''');

    final recientes = await db.rawQuery('''
      SELECT Apartados.*, Clientes.nombre as cliente_nombre
      FROM Apartados
      LEFT JOIN Clientes ON Clientes.id_cliente = Apartados.id_cliente
      WHERE date(Apartados.fecha_creacion) BETWEEN date(?) AND date(?)
      ORDER BY Apartados.fecha_creacion DESC
      LIMIT 20
    ''', [fechaInicio, fechaFin]);

    return ReporteApartadosResumen(
      totalApartados: conteoPorEstado.fold<int>(0, (s, r) => s + (r['total'] as int)),
      pendientes: conteoDe('Pendiente'),
      liquidados: conteoDe('Liquidado'),
      cancelados: conteoDe('Cancelado'),
      vencidos: conteoDe('Vencido'),
      montoReservado: (activosRes.first['monto_reservado'] as num).toDouble(),
      saldoPendienteTotal: (activosRes.first['saldo_pendiente'] as num).toDouble(),
      apartadosRecientes: recientes,
    );
  }

  /// Detalle de una compra ya con la forma de "carrito" que espera
  /// [TicketComprasService.generarTicket] para reimprimir el ticket.
  Future<List<Map<String, dynamic>>> obtenerDetalleCompraParaTicket(int idCompra) async {
    final db = await DatabaseHelper().database;

    final detalles = await db.rawQuery(
      '''
      SELECT Producto.nombre, Detalle_Compra.cantidad, Detalle_Compra.precio
      FROM Detalle_Compra
      INNER JOIN Producto ON Producto.id_producto = Detalle_Compra.id_producto
      WHERE Detalle_Compra.id_compra = ?
      ''',
      [idCompra],
    );

    return detalles.map((item) {
      return {
        'nombre': item['nombre'],
        'cantidad': item['cantidad'] ?? 1,
        'precio_compra': item['precio'],
      };
    }).toList();
  }

  /// Cuentas por pagar: deuda total/por proveedor (siempre "a hoy", no
  /// depende del rango), compras vencidas (idem), y pagos realizados +
  /// salidas de caja en efectivo acotados a [desde]/[hasta].
  Future<ReporteCuentasPorPagarResumen> obtenerReporteCuentasPorPagar({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final db = await DatabaseHelper().database;

    final deudaTotal = await _cuentasPorPagarController.deudaTotal();
    final deudaPorProveedor = await _cuentasPorPagarController.deudaPorProveedor();
    final comprasPendientes = await _cuentasPorPagarController.obtenerCuentasPendientes();
    final comprasVencidas = await _cuentasPorPagarController.obtenerCuentasVencidas();
    final proximosVencimientos = await _cuentasPorPagarController.obtenerProximosVencimientos();

    final pagosRealizados = await db.rawQuery('''
      SELECT ab.id_abono, ab.id_compra, ab.fecha, ab.monto, ab.referencia,
             p.nombre as proveedor, u.nombre as usuario
      FROM Abonos ab
      INNER JOIN Compras c ON c.id_compra = ab.id_compra
      LEFT JOIN Proveedores p ON p.id_proveedor = c.id_proveedor
      LEFT JOIN Usuarios u ON u.id_usuario = ab.id_usuario
      WHERE date(ab.fecha) BETWEEN date(?) AND date(?)
      ORDER BY ab.fecha DESC
    ''', [desde.toIso8601String(), hasta.toIso8601String()]);

    final salidasRes = await db.rawQuery('''
      SELECT IFNULL(SUM(apg.monto), 0) as total
      FROM Abono_Pagos apg
      INNER JOIN Abonos ab ON ab.id_abono = apg.id_abono
      WHERE apg.metodo_pago = 'Efectivo'
        AND date(ab.fecha) BETWEEN date(?) AND date(?)
    ''', [desde.toIso8601String(), hasta.toIso8601String()]);

    return ReporteCuentasPorPagarResumen(
      deudaTotal: deudaTotal,
      deudaPorProveedor: deudaPorProveedor,
      comprasPendientes: comprasPendientes,
      comprasVencidas: comprasVencidas,
      pagosRealizados: pagosRealizados,
      proximosVencimientos: proximosVencimientos,
      salidasCajaEfectivo: (salidasRes.first['total'] as num).toDouble(),
    );
  }
}
