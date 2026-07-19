import 'money.dart';

/// Métodos de pago habilitados en la UI. Agregar uno nuevo (ej. "Vale de
/// despensa") solo requiere sumarlo aquí: [validarPagosMixtos] ya es
/// agnóstica a cuántos métodos no-efectivo existan, solo distingue
/// efectivo/no-efectivo.
const List<String> metodosPagoDisponibles = ['Efectivo', 'Tarjeta', 'Transferencia'];

/// Comparación insensible a mayúsculas/minúsculas: los datos históricos
/// (previos a pagos mixtos) guardan el método en minúsculas ('efectivo').
bool esMetodoEfectivo(String metodoPago) => metodoPago.trim().toLowerCase() == 'efectivo';

/// Marca de "sin método de pago registrado", usada únicamente por la
/// migración que da por pagadas las compras a proveedores anteriores a
/// Cuentas por Pagar (ver `_backfillAbonosComprasExistentes` en
/// `database_helper.dart`): ese dinero nunca se registró como efectivo,
/// tarjeta o transferencia, así que inventar uno de esos tres falsearía
/// reportes y cierres de caja. A propósito NO está en
/// [metodosPagoDisponibles]: no es un método seleccionable para abonos
/// nuevos, solo una marca retroactiva.
const metodoPagoHistorico = 'Historico';

/// Etiqueta amigable para mostrar [metodoPagoHistorico] en la UI.
const labelMetodoPagoHistorico = 'Pago histórico';

/// Traduce un método de pago crudo a su etiqueta de UI (hoy solo
/// [metodoPagoHistorico] tiene una traducción; el resto se muestra tal cual).
String labelMetodoPago(String metodoPago) {
  return metodoPago == metodoPagoHistorico ? labelMetodoPagoHistorico : metodoPago;
}

class PagoIngresado {
  final String metodoPago;
  final double monto;

  const PagoIngresado({required this.metodoPago, required this.monto});
}

class ResultadoValidacionPagos {
  final double totalPagado;
  final double restante;
  final double cambio;
  final bool esValido;
  final String? mensajeError;

  const ResultadoValidacionPagos({
    required this.totalPagado,
    required this.restante,
    required this.cambio,
    required this.esValido,
    this.mensajeError,
  });
}

/// Valida una lista de pagos contra el total de la venta y calcula el
/// desglose (pagado, restante, cambio).
///
/// El cambio únicamente puede originarse de efectivo: si todos los pagos
/// son en efectivo, la suma puede superar el total (el excedente es el
/// cambio). En cuanto hay un método no-efectivo en la mezcla, la suma debe
/// coincidir exactamente con el total — un excedente ya no es válido aunque
/// "provenga" del lado efectivo, porque el sistema no puede saber si ese
/// excedente iba a cubrir parte del monto electrónico.
ResultadoValidacionPagos validarPagosMixtos({
  required double total,
  required List<PagoIngresado> pagos,
}) {
  final totalRedondeado = redondearMoneda(total);

  if (pagos.isEmpty) {
    return ResultadoValidacionPagos(
      totalPagado: 0,
      restante: totalRedondeado,
      cambio: 0,
      esValido: false,
      mensajeError: 'Agrega al menos un método de pago.',
    );
  }

  for (final pago in pagos) {
    if (pago.monto < 0) {
      return ResultadoValidacionPagos(
        totalPagado: 0,
        restante: totalRedondeado,
        cambio: 0,
        esValido: false,
        mensajeError: 'El monto no puede ser negativo.',
      );
    }
  }

  final metodosVistos = <String>{};
  for (final pago in pagos) {
    final clave = pago.metodoPago.trim().toLowerCase();
    if (!metodosVistos.add(clave)) {
      return ResultadoValidacionPagos(
        totalPagado: 0,
        restante: totalRedondeado,
        cambio: 0,
        esValido: false,
        mensajeError:
            'El método "${pago.metodoPago}" ya está agregado; edita esa línea en vez de duplicarla.',
      );
    }
  }

  final totalPagado = redondearMoneda(
    pagos.fold<double>(0, (acc, p) => acc + p.monto),
  );

  if (totalPagado < totalRedondeado) {
    final restante = redondearMoneda(totalRedondeado - totalPagado);
    return ResultadoValidacionPagos(
      totalPagado: totalPagado,
      restante: restante,
      cambio: 0,
      esValido: false,
      mensajeError: 'Falta \$${restante.toStringAsFixed(2)} por cobrar.',
    );
  }

  if (totalPagado == totalRedondeado) {
    return ResultadoValidacionPagos(
      totalPagado: totalPagado,
      restante: 0,
      cambio: 0,
      esValido: true,
    );
  }

  final esSoloEfectivo = pagos.every((p) => esMetodoEfectivo(p.metodoPago));

  if (esSoloEfectivo) {
    return ResultadoValidacionPagos(
      totalPagado: totalPagado,
      restante: 0,
      cambio: redondearMoneda(totalPagado - totalRedondeado),
      esValido: true,
    );
  }

  return ResultadoValidacionPagos(
    totalPagado: totalPagado,
    restante: 0,
    cambio: 0,
    esValido: false,
    mensajeError:
        'El pago excede el total; con métodos electrónicos el monto debe coincidir exactamente.',
  );
}
