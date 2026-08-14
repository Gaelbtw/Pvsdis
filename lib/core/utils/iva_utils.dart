import 'money.dart';

/// Base gravable e IVA de una venta, ya sumados sobre todas sus líneas.
///
/// Los precios del sistema son IVA-INCLUIDO: el total que paga el cliente no
/// cambia por desglosarlo. Lo que este desglose responde es cuánto de ese
/// total es mercancía y cuánto es impuesto.
class DesgloseIva {
  /// Suma de las bases (importe sin IVA) de todas las líneas.
  final double base;

  /// Suma del IVA contenido en todas las líneas.
  final double iva;

  /// Tasas distintas presentes en la venta, de mayor a menor. Con más de una
  /// (por ejemplo, despensa exenta junto a un refresco gravado) el ticket no
  /// puede rotular "IVA (16%)" sobre el total: la lista permite que muestre
  /// las tasas que realmente intervinieron.
  final List<double> tasas;

  const DesgloseIva({
    required this.base,
    required this.iva,
    required this.tasas,
  });

  static const DesgloseIva sinIva = DesgloseIva(base: 0, iva: 0, tasas: []);

  bool get hayIva => iva > 0;

  /// `true` si intervino más de una tasa distinta.
  bool get tasasMixtas => tasas.length > 1;

  /// Etiqueta para el renglón de IVA del ticket: "IVA (16.00%)" con una sola
  /// tasa, "IVA (16.00%, 0.00%)" cuando se mezclaron.
  String get etiqueta {
    if (tasas.isEmpty) return 'IVA';
    return 'IVA (${tasas.map((t) => '${t.toStringAsFixed(2)}%').join(', ')})';
  }
}

/// Separa base e IVA de una venta cuyas líneas traen precios IVA-incluido.
///
/// Cada línea de [lineas] puede traer:
/// - `importe_neto`: lo realmente cobrado por esa línea, YA con todos los
///   descuentos (de promoción, de línea y la parte proporcional del global).
/// - `iva_tasa`: la tasa de ese producto en porcentaje; `null` = usa
///   [tasaGeneral], que es como se comportaba todo el catálogo antes de que el
///   IVA fuera por producto.
///
/// Si ninguna línea trae `importe_neto` (tickets reimpresos por caminos viejos
/// que no lo guardaban), se cae al cálculo anterior: [tasaGeneral] aplicada al
/// [total]. Es una aproximación, pero es exactamente lo que el ticket mostraba
/// antes, así que no empeora nada; con líneas completas el resultado es exacto
/// incluso mezclando tasas.
DesgloseIva desglosarIva({
  required List<Map<String, dynamic>> lineas,
  required double tasaGeneral,
  required double total,
}) {
  final conImporte = lineas.where((l) => l['importe_neto'] != null).toList();

  if (conImporte.isEmpty) {
    if (tasaGeneral <= 0 || total <= 0) return DesgloseIva.sinIva;
    final base = redondearMoneda(total / (1 + tasaGeneral / 100));
    return DesgloseIva(
      base: base,
      iva: redondearMoneda(total - base),
      tasas: [tasaGeneral],
    );
  }

  var base = 0.0;
  var iva = 0.0;
  final tasas = <double>{};

  for (final linea in conImporte) {
    final neto = (linea['importe_neto'] as num).toDouble();
    final tasa = (linea['iva_tasa'] as num?)?.toDouble() ?? tasaGeneral;

    // Una tasa 0 sigue contando como línea gravada a 0% para efectos del
    // rótulo solo si el resto de la venta también tiene IVA; se agrega a
    // `tasas` únicamente cuando hay algo de impuesto en la venta (se filtra
    // más abajo) para no rotular "IVA (0.00%)" en un negocio que no cobra IVA.
    final baseLinea = tasa <= 0 ? neto : redondearMoneda(neto / (1 + tasa / 100));
    base = redondearMoneda(base + baseLinea);
    iva = redondearMoneda(iva + (neto - baseLinea));
    tasas.add(tasa);
  }

  if (iva <= 0) return DesgloseIva.sinIva;

  final ordenadas = tasas.toList()..sort((a, b) => b.compareTo(a));
  return DesgloseIva(base: base, iva: iva, tasas: ordenadas);
}
