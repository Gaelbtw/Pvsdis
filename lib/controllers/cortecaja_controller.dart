import '../core/database/database_helper.dart';

/// Totales del día usados por el corte de caja.
class CorteCajaResumen {
  final double total;
  final double efectivo;
  final double tarjeta;
  final double salidas;
  final double devoluciones;

  const CorteCajaResumen({
    required this.total,
    required this.efectivo,
    required this.tarjeta,
    required this.salidas,
    required this.devoluciones,
  });
}

/// Consultas del corte de caja. Antes vivían como `rawQuery` directamente
/// dentro de `cortecaja_view.dart`.
class CorteCajaController {
  Future<CorteCajaResumen> calcularResumenDelDia(DateTime fecha) async {
    final db = await DatabaseHelper().database;

    final hoy =
        "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";

    // Ventas brutas del día, por método de pago.
    Future<double> ventasDelDia(String? metodoPago) async {
      final res = await db.rawQuery(
        metodoPago == null
            ? "SELECT IFNULL(SUM(total), 0) as total FROM Ventas WHERE fecha LIKE ?"
            : "SELECT IFNULL(SUM(total), 0) as total FROM Ventas WHERE metodo_pago = ? AND fecha LIKE ?",
        metodoPago == null ? ['$hoy%'] : [metodoPago, '$hoy%'],
      );
      return (res.first['total'] as num).toDouble();
    }

    // Devoluciones PROCESADAS hoy (sin importar la fecha de la venta
    // original): es lo correcto para reconciliar caja física, ya que el
    // efectivo/tarjeta sale del cajón el día en que se hace la devolución,
    // no el día en que se hizo la venta. Se filtra por el método de pago
    // de la venta original, para descontar del mismo bucket que sumó.
    Future<double> devolucionesDelDia(String? metodoPago) async {
      final res = await db.rawQuery(
        '''
        SELECT IFNULL(SUM(dd.cantidad * dd.precio), 0) as total
        FROM Detalle_Devolucion dd
        INNER JOIN Devoluciones d ON d.id_devolucion = dd.id_devolucion
        INNER JOIN Ventas v ON v.id_venta = d.id_venta
        WHERE d.fecha_hora LIKE ?
        ${metodoPago == null ? '' : 'AND v.metodo_pago = ?'}
        ''',
        metodoPago == null ? ['$hoy%'] : ['$hoy%', metodoPago],
      );
      return (res.first['total'] as num).toDouble();
    }

    final ventasTotal = await ventasDelDia(null);
    final ventasEfectivo = await ventasDelDia('efectivo');
    final ventasTarjeta = await ventasDelDia('tarjeta');

    final devolucionesTotal = await devolucionesDelDia(null);
    final devolucionesEfectivo = await devolucionesDelDia('efectivo');
    final devolucionesTarjeta = await devolucionesDelDia('tarjeta');

    final salidasRes = await db.rawQuery(
      "SELECT IFNULL(SUM(total), 0) as total FROM Compras WHERE fecha LIKE ?",
      ['$hoy%'],
    );

    return CorteCajaResumen(
      total: ventasTotal - devolucionesTotal,
      efectivo: ventasEfectivo - devolucionesEfectivo,
      tarjeta: ventasTarjeta - devolucionesTarjeta,
      salidas: (salidasRes.first["total"] as num).toDouble(),
      devoluciones: devolucionesTotal,
    );
  }
}
