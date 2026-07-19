import 'dart:math' as math;

import '../../models/promocion_model.dart';
import 'descuento_utils.dart';
import 'money.dart';

/// Cuánto de una promoción se aplicó a una línea específica del carrito:
/// cuántas unidades cubrió y cuánto se ahorró en esa línea. Es lo que
/// [VentasController] persiste en `Venta_Promociones_Detalle`.
class AplicacionLinea {
  final int indexLinea;
  final int idProducto;
  final int cantidadAfectada;
  final double ahorro;

  const AplicacionLinea({
    required this.indexLinea,
    required this.idProducto,
    required this.cantidadAfectada,
    required this.ahorro,
  });
}

/// Una promoción que sí tuvo efecto sobre el carrito evaluado, con el
/// desglose de qué líneas afectó. Promociones sin ningún match (ahorro 0)
/// no aparecen aquí.
class PromocionAplicada {
  final int? idPromocion;
  final String nombre;
  final TipoPromocion tipo;
  final List<AplicacionLinea> lineas;

  const PromocionAplicada({
    required this.idPromocion,
    required this.nombre,
    required this.tipo,
    required this.lineas,
  });

  double get ahorroTotal => redondearMoneda(lineas.fold<double>(0, (s, l) => s + l.ahorro));
}

class ResultadoPromociones {
  final List<double> descuentoPorLinea;
  final List<PromocionAplicada> aplicaciones;

  const ResultadoPromociones({
    required this.descuentoPorLinea,
    required this.aplicaciones,
  });

  double get ahorroTotal =>
      redondearMoneda(descuentoPorLinea.fold<double>(0, (s, d) => s + d));

  static const ResultadoPromociones vacio = ResultadoPromociones(descuentoPorLinea: [], aplicaciones: []);
}

/// Estado mutable de una línea del carrito mientras se evalúan promociones:
/// cuántas unidades siguen sin reclamar (`libres`) y cuántas fueron
/// reclamadas exclusivamente por promociones combinables (`combinablesClaimed`,
/// disponibles para que OTRA promoción combinable también aplique sobre
/// ellas). Una unidad reclamada por al menos una promoción no combinable
/// queda bloqueada para siempre: ni `libres` ni `combinablesClaimed` la
/// vuelven a contar, así que ninguna otra promoción puede tocarla.
class _LineaEstado {
  final int index;
  final int idProducto;
  final int? idCategoria;
  final double precio;
  final int cantidad;
  int libres;
  int combinablesClaimed;

  _LineaEstado({
    required this.index,
    required this.idProducto,
    required this.idCategoria,
    required this.precio,
    required this.cantidad,
  })  : libres = cantidad,
        combinablesClaimed = 0;

  int capacidadPara(Promocion promo) => promo.combinable ? libres + combinablesClaimed : libres;

  void consumir(Promocion promo, int unidades) {
    final desdeLibres = unidades > libres ? libres : unidades;
    libres -= desdeLibres;
    if (promo.combinable) {
      combinablesClaimed += desdeLibres;
    }
  }

  bool matchParticipante(Promocion promo) =>
      promo.productosIds.contains(idProducto) ||
      (idCategoria != null && promo.categoriasIds.contains(idCategoria));
}

/// Evalúa qué promociones automáticas aplican sobre [carrito] y cuánto
/// descuenta cada una, línea por línea. Función pura: no toca base de
/// datos ni UI, así que tanto la vista (para la vista previa en vivo) como
/// `VentasController` (para el cálculo autoritativo al cobrar) pueden
/// invocarla con el mismo resultado dado el mismo carrito y las mismas
/// promociones.
///
/// [carrito] usa el mismo formato que ya consume `calcularVenta`: mapas con
/// `id_producto`, `nombre`, `precio`, `cantidad` y, opcionalmente,
/// `id_categoria`. [promocionesActivas] debe venir ya filtrada por vigencia
/// (activo=true y dentro del rango de fechas) — el motor no vuelve a
/// filtrar por fecha, eso es responsabilidad del controller.
ResultadoPromociones evaluarPromociones({
  required List<Map<String, dynamic>> carrito,
  required List<Promocion> promocionesActivas,
}) {
  if (carrito.isEmpty) return ResultadoPromociones.vacio;

  final lineas = carrito.asMap().entries.map((entry) {
    final item = entry.value;
    return _LineaEstado(
      index: entry.key,
      idProducto: item['id_producto'] as int,
      idCategoria: item['id_categoria'] as int?,
      precio: (item['precio'] as num).toDouble(),
      cantidad: item['cantidad'] as int,
    );
  }).toList();

  // Orden por prioridad descendente; a igual prioridad, se procesan en el
  // orden en que llegaron (desempate explícito por índice original, sin
  // depender de que `List.sort` sea estable).
  final indexOriginal = <Promocion, int>{
    for (final e in promocionesActivas.asMap().entries) e.value: e.key,
  };
  final promosOrdenadas = List<Promocion>.from(promocionesActivas)
    ..sort((a, b) {
      final cmp = b.prioridad.compareTo(a.prioridad);
      if (cmp != 0) return cmp;
      return (indexOriginal[a] ?? 0).compareTo(indexOriginal[b] ?? 0);
    });

  final descuentoPorLinea = List<double>.filled(carrito.length, 0);
  final aplicaciones = <PromocionAplicada>[];

  for (final promo in promosOrdenadas) {
    final resultado = promo.tipo == TipoPromocion.combo
        ? _evaluarCombo(promo, lineas)
        : _evaluarSimple(promo, lineas);

    if (resultado.isEmpty) continue;

    for (final aplicacion in resultado) {
      descuentoPorLinea[aplicacion.indexLinea] =
          redondearMoneda(descuentoPorLinea[aplicacion.indexLinea] + aplicacion.ahorro);
    }

    aplicaciones.add(PromocionAplicada(
      idPromocion: promo.idPromocion,
      nombre: promo.nombre,
      tipo: promo.tipo,
      lineas: resultado,
    ));
  }

  return ResultadoPromociones(descuentoPorLinea: descuentoPorLinea, aplicaciones: aplicaciones);
}

List<AplicacionLinea> _evaluarSimple(Promocion promo, List<_LineaEstado> lineas) {
  final aplicaciones = <AplicacionLinea>[];

  for (final linea in lineas) {
    if (!linea.matchParticipante(promo)) continue;

    switch (promo.tipo) {
      case TipoPromocion.porcentajeProducto:
      case TipoPromocion.montoFijoProducto:
        final disponible = linea.capacidadPara(promo);
        if (disponible <= 0) continue;

        final descuentoPorUnidad = promo.tipo == TipoPromocion.porcentajeProducto
            ? redondearMoneda(linea.precio * (promo.valor ?? 0) / 100)
            : redondearMoneda(math.max(0.0, math.min(promo.valor ?? 0.0, linea.precio)));
        if (descuentoPorUnidad <= 0) continue;

        final ahorro = redondearMoneda(descuentoPorUnidad * disponible);
        linea.consumir(promo, disponible);
        aplicaciones.add(AplicacionLinea(
          indexLinea: linea.index,
          idProducto: linea.idProducto,
          cantidadAfectada: disponible,
          ahorro: ahorro,
        ));
        break;

      case TipoPromocion.nxy:
        final nxLleva = promo.nxLleva ?? 0;
        final nxPaga = promo.nxPaga ?? 0;
        if (nxLleva <= 0 || nxPaga < 0 || nxPaga >= nxLleva) continue;

        final disponible = linea.capacidadPara(promo);
        final grupos = disponible ~/ nxLleva;
        if (grupos <= 0) continue;

        final unidadesGratis = grupos * (nxLleva - nxPaga);
        final consumidas = grupos * nxLleva;
        final ahorro = redondearMoneda(linea.precio * unidadesGratis);
        if (ahorro <= 0) continue;

        linea.consumir(promo, consumidas);
        aplicaciones.add(AplicacionLinea(
          indexLinea: linea.index,
          idProducto: linea.idProducto,
          cantidadAfectada: consumidas,
          ahorro: ahorro,
        ));
        break;

      case TipoPromocion.descuentoCantidad:
        final minimo = promo.cantidadMinima ?? 0;
        final disponible = linea.capacidadPara(promo);
        if (disponible <= minimo) continue;

        final excedente = disponible - minimo;
        final descuentoPorUnidad = promo.tipoValor == TipoDescuento.porcentaje
            ? redondearMoneda(linea.precio * (promo.valor ?? 0) / 100)
            : redondearMoneda(math.max(0.0, math.min(promo.valor ?? 0.0, linea.precio)));
        if (descuentoPorUnidad <= 0) continue;

        final ahorro = redondearMoneda(descuentoPorUnidad * excedente);
        linea.consumir(promo, excedente);
        aplicaciones.add(AplicacionLinea(
          indexLinea: linea.index,
          idProducto: linea.idProducto,
          cantidadAfectada: excedente,
          ahorro: ahorro,
        ));
        break;

      case TipoPromocion.combo:
        break; // manejado aparte por _evaluarCombo
    }
  }

  return aplicaciones;
}

/// Un combo puede formarse varias veces en el mismo carrito (p. ej. dos
/// "combo hamburguesa" si hay suficientes unidades de cada ingrediente); el
/// ahorro de todas las instancias formables se calcula de una vez y se
/// reparte proporcionalmente entre los productos involucrados.
List<AplicacionLinea> _evaluarCombo(Promocion promo, List<_LineaEstado> lineas) {
  if (promo.comboItems.isEmpty) return const [];

  final lineaPorProducto = <int, _LineaEstado>{for (final l in lineas) l.idProducto: l};

  var instancias = 1 << 30; // "infinito" hasta que algún item lo acote
  for (final item in promo.comboItems) {
    final linea = lineaPorProducto[item.idProducto];
    if (linea == null || item.cantidad <= 0) {
      instancias = 0;
      break;
    }
    final disponible = linea.capacidadPara(promo);
    final posibles = disponible ~/ item.cantidad;
    if (posibles < instancias) instancias = posibles;
  }

  if (instancias <= 0) return const [];

  final precioNormalPorItem = <int, double>{};
  var totalNormalUnaInstancia = 0.0;
  for (final item in promo.comboItems) {
    final linea = lineaPorProducto[item.idProducto]!;
    final normal = redondearMoneda(linea.precio * item.cantidad);
    precioNormalPorItem[item.idProducto] = normal;
    totalNormalUnaInstancia = redondearMoneda(totalNormalUnaInstancia + normal);
  }

  final totalNormal = redondearMoneda(totalNormalUnaInstancia * instancias);
  final totalCombo = redondearMoneda((promo.precioCombo ?? 0) * instancias);
  final ahorroTotal = redondearMoneda(totalNormal - totalCombo);
  if (ahorroTotal <= 0) return const [];

  final bases = promo.comboItems
      .map((item) => redondearMoneda(precioNormalPorItem[item.idProducto]! * instancias))
      .toList();
  final ahorroPorItem = prorratearMonto(bases, ahorroTotal);

  final aplicaciones = <AplicacionLinea>[];
  for (var i = 0; i < promo.comboItems.length; i++) {
    final item = promo.comboItems[i];
    final linea = lineaPorProducto[item.idProducto]!;
    final consumidas = item.cantidad * instancias;
    linea.consumir(promo, consumidas);
    aplicaciones.add(AplicacionLinea(
      indexLinea: linea.index,
      idProducto: linea.idProducto,
      cantidadAfectada: consumidas,
      ahorro: ahorroPorItem[i],
    ));
  }

  return aplicaciones;
}
