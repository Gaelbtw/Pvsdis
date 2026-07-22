import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Escribe una fila en `Movimiento_Caja` (bitácora nueva de la Fase 3) cada
/// vez que ocurre un evento de caja sincronizable: un pago recibido al
/// cobrar una venta, o una devolución en efectivo. Mismo patrón que
/// [MovimientoInventarioLogger] -- ver ese archivo para el criterio general.
///
/// [tipoMovimiento] debe ser uno de los valores del CHECK de la tabla
/// (`'VentaEfectivo'`, `'VentaTarjeta'`, `'VentaTransferencia'`,
/// `'EntradaManual'`, `'SalidaManual'`, `'DevolucionEfectivo'`,
/// `'AbonoCuentaCobrar'`, `'AbonoCuentaPagar'`), mismos nombres que el enum
/// `TipoMovimientoCaja` del backend.
class MovimientoCajaLogger {
  Future<int> registrar(
    DatabaseExecutor db, {
    required int idCaja,
    required String tipoMovimiento,
    required double monto,
    String? concepto,
    int? idVentaReferencia,
  }) {
    return DatabaseHelper.insertarConGuidSync(db, 'Movimiento_Caja', {
      'id_caja': idCaja,
      'tipo_movimiento': tipoMovimiento,
      'monto': monto,
      'concepto': concepto,
      'fecha': DateTime.now().toUtc().toIso8601String(),
      'id_venta_referencia': idVentaReferencia,
    });
  }

  /// Traduce el método de pago local (texto libre, ver
  /// `lib/core/utils/pagos_mixtos.dart`) al `tipo_movimiento` de venta que
  /// corresponde. Métodos no reconocidos (ej. `metodoPagoHistorico`) caen a
  /// `'VentaEfectivo'` -- el tipo más común, para no dejar de registrar el
  /// movimiento por un método de pago con formato inesperado.
  static String tipoMovimientoParaMetodoPago(String metodoPago) {
    switch (metodoPago.trim().toLowerCase()) {
      case 'tarjeta':
        return 'VentaTarjeta';
      case 'transferencia':
        return 'VentaTransferencia';
      default:
        return 'VentaEfectivo';
    }
  }
}
