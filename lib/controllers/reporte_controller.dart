import '../core/database/database_helper.dart';

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

/// Consultas de reportes (ventas/compras por rango, detalle para reimprimir
/// un ticket). Antes vivían como `rawQuery` directamente dentro de
/// `reporte_view.dart`.
class ReporteController {
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

  /// Subtotal/descuento/total de una venta ya registrada, para reimprimir
  /// el ticket con el mismo desglose que se mostró al momento de la venta.
  Future<({double subtotal, double descuentoTotal, double total, String metodoPago})>
      obtenerTotalesVentaParaTicket(int idVenta) async {
    final db = await DatabaseHelper().database;

    final rows = await db.query(
      'Ventas',
      columns: ['subtotal', 'descuento_total', 'total', 'metodo_pago'],
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
      metodoPago: venta['metodo_pago']?.toString() ?? 'efectivo',
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
}
