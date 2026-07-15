import 'money.dart';

enum TipoDescuento {
  porcentaje,
  fijo;

  String get nombre => this == TipoDescuento.porcentaje ? 'porcentaje' : 'fijo';

  static TipoDescuento? desdeNombre(String? nombre) {
    switch (nombre) {
      case 'porcentaje':
        return TipoDescuento.porcentaje;
      case 'fijo':
        return TipoDescuento.fijo;
      default:
        return null;
    }
  }
}

/// Monto en moneda ya calculado (y redondeado) para un descuento, junto con
/// el porcentaje efectivo que representa sobre su base — este último es lo
/// que se compara contra el umbral configurable, sin importar si el
/// descuento se ingresó como porcentaje o como monto fijo.
class ResultadoDescuento {
  final double monto;
  final double porcentajeEfectivo;

  const ResultadoDescuento(this.monto, this.porcentajeEfectivo);

  static const ResultadoDescuento ninguno = ResultadoDescuento(0, 0);
}

/// Calcula el monto de un descuento sobre [base], validando las reglas
/// estructurales: nunca negativo, porcentaje nunca mayor a 100, fijo nunca
/// mayor a la base aplicable. No valida el umbral de autorización — eso lo
/// decide [calcularVenta] comparando [ResultadoDescuento.porcentajeEfectivo].
ResultadoDescuento calcularMontoDescuento({
  required TipoDescuento? tipo,
  required double valor,
  required double base,
}) {
  if (tipo == null || valor == 0) return ResultadoDescuento.ninguno;

  if (valor < 0) {
    throw Exception('El descuento no puede ser negativo.');
  }

  double monto;
  if (tipo == TipoDescuento.porcentaje) {
    if (valor > 100) {
      throw Exception('El descuento porcentual no puede superar 100%.');
    }
    monto = redondearMoneda(base * valor / 100);
  } else {
    if (valor > base) {
      throw Exception(
        'El descuento fijo no puede superar el subtotal aplicable (\$${base.toStringAsFixed(2)}).',
      );
    }
    monto = redondearMoneda(valor);
  }

  final porcentajeEfectivo = base <= 0 ? 0.0 : (monto / base * 100);
  return ResultadoDescuento(monto, porcentajeEfectivo);
}

/// Línea ya calculada: conserva [precioOriginal] intacto y expone
/// [precioNetoUnitario], el precio unitario tras su propio descuento de
/// línea *y* la parte proporcional del descuento global — es lo que deben
/// usar las devoluciones para calcular el importe realmente pagado.
class LineaVentaCalculada {
  final int idProducto;
  final String nombre;
  final double precioOriginal;
  final int cantidad;
  final TipoDescuento? descuentoTipo;
  final double descuentoValor;
  final double descuentoMonto;
  final double subtotalLinea;
  final double montoNeto;
  final double precioNetoUnitario;

  const LineaVentaCalculada({
    required this.idProducto,
    required this.nombre,
    required this.precioOriginal,
    required this.cantidad,
    required this.descuentoTipo,
    required this.descuentoValor,
    required this.descuentoMonto,
    required this.subtotalLinea,
    required this.montoNeto,
    required this.precioNetoUnitario,
  });
}

class VentaCalculada {
  final List<LineaVentaCalculada> lineas;
  final double subtotal;
  final TipoDescuento? descuentoGlobalTipo;
  final double descuentoGlobalValor;
  final double descuentoGlobalMonto;
  final double descuentoTotal;
  final double total;

  /// `true` si algún descuento (de línea o global) superó el umbral
  /// configurado, y por lo tanto requiere motivo obligatorio (y posible
  /// autorización de administrador si quien vende es Cajero).
  final bool requiereAutorizacion;

  const VentaCalculada({
    required this.lineas,
    required this.subtotal,
    required this.descuentoGlobalTipo,
    required this.descuentoGlobalValor,
    required this.descuentoGlobalMonto,
    required this.descuentoTotal,
    required this.total,
    required this.requiereAutorizacion,
  });

  static const VentaCalculada vacia = VentaCalculada(
    lineas: [],
    subtotal: 0,
    descuentoGlobalTipo: null,
    descuentoGlobalValor: 0,
    descuentoGlobalMonto: 0,
    descuentoTotal: 0,
    total: 0,
    requiereAutorizacion: false,
  );
}

/// Calcula subtotal, descuentos (de línea y global) y total de una venta a
/// partir de las líneas del carrito. Cada elemento de [carrito] debe traer
/// `id_producto`, `nombre`, `precio`, `cantidad` y, opcionalmente,
/// `descuento_tipo` (`TipoDescuento?`) y `descuento_valor` (`num?`).
///
/// No toca base de datos ni UI: es la única fuente de verdad para el
/// cálculo financiero, usada tanto por la vista (para la vista previa en
/// tiempo real) como por el controlador (para persistir de forma
/// autoritativa, sin confiar en un total pre-calculado por la UI).
VentaCalculada calcularVenta({
  required List<Map<String, dynamic>> carrito,
  TipoDescuento? descuentoGlobalTipo,
  double descuentoGlobalValor = 0,
  required double descuentoMaximoPorcentaje,
}) {
  if (carrito.isEmpty) return VentaCalculada.vacia;

  var requiereAutorizacion = false;

  final calculos = carrito.map((item) {
    final precio = (item['precio'] as num).toDouble();
    final cantidad = item['cantidad'] as int;
    final subtotalLinea = redondearMoneda(precio * cantidad);
    final tipo = item['descuento_tipo'] as TipoDescuento?;
    final valor = (item['descuento_valor'] as num?)?.toDouble() ?? 0;

    final resultado = calcularMontoDescuento(tipo: tipo, valor: valor, base: subtotalLinea);
    if (resultado.porcentajeEfectivo > descuentoMaximoPorcentaje) {
      requiereAutorizacion = true;
    }

    return (
      idProducto: item['id_producto'] as int,
      nombre: item['nombre'] as String,
      precio: precio,
      cantidad: cantidad,
      subtotalLinea: subtotalLinea,
      tipo: tipo,
      valor: valor,
      resultado: resultado,
    );
  }).toList();

  final subtotal = redondearMoneda(calculos.fold<double>(0, (s, c) => s + c.subtotalLinea));
  final baseGlobal = redondearMoneda(
    calculos.fold<double>(0, (s, c) => s + (c.subtotalLinea - c.resultado.monto)),
  );

  final resultadoGlobal = calcularMontoDescuento(
    tipo: descuentoGlobalTipo,
    valor: descuentoGlobalValor,
    base: baseGlobal,
  );
  if (resultadoGlobal.porcentajeEfectivo > descuentoMaximoPorcentaje) {
    requiereAutorizacion = true;
  }

  // Reparte el descuento global proporcionalmente entre líneas; la última
  // absorbe el remanente de redondeo para que la suma de partes cuadre
  // exactamente con el monto global.
  double acumuladoAsignado = 0;
  final lineas = <LineaVentaCalculada>[];

  for (var i = 0; i < calculos.length; i++) {
    final c = calculos[i];
    final montoTrasLinea = redondearMoneda(c.subtotalLinea - c.resultado.monto);

    double asignadoGlobal;
    if (i == calculos.length - 1) {
      asignadoGlobal = redondearMoneda(resultadoGlobal.monto - acumuladoAsignado);
    } else {
      final proporcion = baseGlobal <= 0 ? 0.0 : montoTrasLinea / baseGlobal;
      asignadoGlobal = redondearMoneda(resultadoGlobal.monto * proporcion);
      acumuladoAsignado = redondearMoneda(acumuladoAsignado + asignadoGlobal);
    }

    final montoNeto = redondearMoneda(montoTrasLinea - asignadoGlobal);
    final precioNetoUnitario = c.cantidad == 0 ? 0.0 : redondearMoneda(montoNeto / c.cantidad);

    lineas.add(LineaVentaCalculada(
      idProducto: c.idProducto,
      nombre: c.nombre,
      precioOriginal: c.precio,
      cantidad: c.cantidad,
      descuentoTipo: c.tipo,
      descuentoValor: c.valor,
      descuentoMonto: c.resultado.monto,
      subtotalLinea: c.subtotalLinea,
      montoNeto: montoNeto,
      precioNetoUnitario: precioNetoUnitario,
    ));
  }

  final descuentoTotal = redondearMoneda(
    calculos.fold<double>(0, (s, c) => s + c.resultado.monto) + resultadoGlobal.monto,
  );
  var total = redondearMoneda(subtotal - descuentoTotal);
  if (total < 0) total = 0; // defensa adicional: nunca debería ocurrir (ver pruebas)

  return VentaCalculada(
    lineas: lineas,
    subtotal: subtotal,
    descuentoGlobalTipo: descuentoGlobalTipo,
    descuentoGlobalValor: descuentoGlobalValor,
    descuentoGlobalMonto: resultadoGlobal.monto,
    descuentoTotal: descuentoTotal,
    total: total,
    requiereAutorizacion: requiereAutorizacion,
  );
}
