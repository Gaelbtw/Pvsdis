import 'dart:math' as math;

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

/// Reparte [monto] proporcionalmente entre [bases] (según el peso de cada
/// una sobre su suma); la última base absorbe el remanente de redondeo para
/// que la suma de partes cuadre exactamente con [monto]. Compartido entre el
/// descuento global de línea (más abajo) y el motor de promociones
/// (combos), que necesita el mismo prorrateo-con-remanente.
List<double> prorratearMonto(List<double> bases, double monto) {
  if (bases.isEmpty) return const [];

  final total = bases.fold<double>(0, (s, b) => s + b);
  double acumulado = 0;
  final resultado = <double>[];

  for (var i = 0; i < bases.length; i++) {
    double parte;
    if (i == bases.length - 1) {
      parte = redondearMoneda(monto - acumulado);
    } else {
      final proporcion = total <= 0 ? 0.0 : bases[i] / total;
      parte = redondearMoneda(monto * proporcion);
      acumulado = redondearMoneda(acumulado + parte);
    }
    resultado.add(parte);
  }

  return resultado;
}

/// Línea ya calculada: conserva [precioOriginal] intacto y expone
/// [precioNetoUnitario], el precio unitario tras el descuento de promoción,
/// su propio descuento de línea *y* la parte proporcional del descuento
/// global — es lo que deben usar las devoluciones para calcular el importe
/// realmente pagado.
class LineaVentaCalculada {
  final int idProducto;
  final String nombre;
  final double precioOriginal;
  final int cantidad;
  final double descuentoPromocion;
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
    this.descuentoPromocion = 0,
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
  final double descuentoPromocionTotal;
  final TipoDescuento? descuentoGlobalTipo;
  final double descuentoGlobalValor;
  final double descuentoGlobalMonto;
  final double descuentoTotal;
  final double total;

  /// `true` si algún descuento (de línea o global) superó el umbral
  /// configurado, y por lo tanto requiere motivo obligatorio (y posible
  /// autorización de administrador si quien vende es Cajero). Las
  /// promociones automáticas nunca lo activan: ya fueron aprobadas por un
  /// administrador al crearse, así que no pasan por el mismo control de
  /// discreción que un descuento manual de cajero.
  final bool requiereAutorizacion;

  const VentaCalculada({
    required this.lineas,
    required this.subtotal,
    this.descuentoPromocionTotal = 0,
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
    descuentoPromocionTotal: 0,
    descuentoGlobalTipo: null,
    descuentoGlobalValor: 0,
    descuentoGlobalMonto: 0,
    descuentoTotal: 0,
    total: 0,
    requiereAutorizacion: false,
  );
}

/// Calcula subtotal, descuentos (de promoción, línea y global) y total de
/// una venta a partir de las líneas del carrito. Cada elemento de [carrito]
/// debe traer `id_producto`, `nombre`, `precio`, `cantidad` y,
/// opcionalmente, `descuento_tipo` (`TipoDescuento?`) y `descuento_valor`
/// (`num?`).
///
/// [descuentosPromocionPorLinea], si se da, debe tener el mismo largo que
/// [carrito] (mismo índice = misma línea): es el monto que el motor de
/// promociones automáticas (`promociones_engine.dart`) ya calculó para esa
/// línea. Se resta del subtotal de línea *antes* del descuento manual, para
/// que la promoción reduzca el precio base y el descuento manual (si lo
/// hay) se aplique sobre ese remanente.
///
/// No toca base de datos ni UI: es la única fuente de verdad para el
/// cálculo financiero, usada tanto por la vista (para la vista previa en
/// tiempo real) como por el controlador (para persistir de forma
/// autoritativa, sin confiar en un total pre-calculado por la UI).
VentaCalculada calcularVenta({
  required List<Map<String, dynamic>> carrito,
  List<double>? descuentosPromocionPorLinea,
  TipoDescuento? descuentoGlobalTipo,
  double descuentoGlobalValor = 0,
  required double descuentoMaximoPorcentaje,
}) {
  if (carrito.isEmpty) return VentaCalculada.vacia;

  var requiereAutorizacion = false;

  final calculos = carrito.asMap().entries.map((entry) {
    final index = entry.key;
    final item = entry.value;
    final precio = (item['precio'] as num).toDouble();
    final cantidad = item['cantidad'] as int;
    final subtotalLinea = redondearMoneda(precio * cantidad);
    final promocionBruta = (descuentosPromocionPorLinea != null && index < descuentosPromocionPorLinea.length)
        ? descuentosPromocionPorLinea[index]
        : 0.0;
    final descuentoPromocion = redondearMoneda(math.max(0.0, math.min(promocionBruta, subtotalLinea)));
    final baseTrasPromocion = redondearMoneda(subtotalLinea - descuentoPromocion);
    final tipo = item['descuento_tipo'] as TipoDescuento?;
    final valor = (item['descuento_valor'] as num?)?.toDouble() ?? 0;

    final resultado = calcularMontoDescuento(tipo: tipo, valor: valor, base: baseTrasPromocion);
    if (resultado.porcentajeEfectivo > descuentoMaximoPorcentaje) {
      requiereAutorizacion = true;
    }

    return (
      idProducto: item['id_producto'] as int,
      nombre: item['nombre'] as String,
      precio: precio,
      cantidad: cantidad,
      subtotalLinea: subtotalLinea,
      descuentoPromocion: descuentoPromocion,
      baseTrasPromocion: baseTrasPromocion,
      tipo: tipo,
      valor: valor,
      resultado: resultado,
    );
  }).toList();

  final subtotal = redondearMoneda(calculos.fold<double>(0, (s, c) => s + c.subtotalLinea));
  final descuentoPromocionTotal = redondearMoneda(
    calculos.fold<double>(0, (s, c) => s + c.descuentoPromocion),
  );
  final baseGlobal = redondearMoneda(
    calculos.fold<double>(0, (s, c) => s + (c.baseTrasPromocion - c.resultado.monto)),
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
    final montoTrasLinea = redondearMoneda(c.baseTrasPromocion - c.resultado.monto);

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
      descuentoPromocion: c.descuentoPromocion,
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
  var total = redondearMoneda(subtotal - descuentoPromocionTotal - descuentoTotal);
  if (total < 0) total = 0; // defensa adicional: nunca debería ocurrir (ver pruebas)

  return VentaCalculada(
    lineas: lineas,
    subtotal: subtotal,
    descuentoPromocionTotal: descuentoPromocionTotal,
    descuentoGlobalTipo: descuentoGlobalTipo,
    descuentoGlobalValor: descuentoGlobalValor,
    descuentoGlobalMonto: resultadoGlobal.monto,
    descuentoTotal: descuentoTotal,
    total: total,
    requiereAutorizacion: requiereAutorizacion,
  );
}

/// Reglas de permiso/autorización de descuento, compartidas por cualquier
/// controlador que persista un [VentaCalculada] (hoy `VentasController` y
/// `ApartadosController`): si el vendedor es cajero y la política no le
/// permite aplicar descuentos, o si el descuento superó el umbral y falta
/// motivo/autorización, lanza una excepción con el mensaje correspondiente.
/// No hace nada si todo está en regla.
void validarPermisoDescuento({
  required VentaCalculada calculo,
  required bool esCajero,
  required bool cajeroPuedeAplicarDescuento,
  required bool cajeroRequiereAutorizacion,
  String? descuentoMotivo,
  int? descuentoAutorizadoPor,
}) {
  // Red de seguridad a nivel de negocio: aunque la UI ya debería impedir
  // llegar hasta aquí en estos casos, la lógica financiera/autorización no
  // puede depender solo de que la UI se haya comportado bien.
  if (calculo.descuentoTotal > 0 && esCajero && !cajeroPuedeAplicarDescuento) {
    throw Exception('No tienes permiso para aplicar descuentos.');
  }

  if (calculo.requiereAutorizacion) {
    final motivoLimpio = descuentoMotivo?.trim() ?? '';
    if (motivoLimpio.isEmpty) {
      throw Exception('El motivo es obligatorio para este descuento.');
    }
    if (esCajero && cajeroRequiereAutorizacion && descuentoAutorizadoPor == null) {
      throw Exception('Este descuento requiere autorización de un administrador.');
    }
  }
}
