import '../core/utils/descuento_utils.dart';
import 'cliente_model.dart';

/// Una venta pausada temporalmente para retomarla después (patrón "poner en
/// espera" de un POS). Es una foto del carrito en el momento de pausar: sus
/// líneas, el descuento global y el cliente asociado. No toca base de datos —
/// vive solo en memoria mientras la app está abierta (ver
/// [VentasEnEsperaStore]).
class VentaEnEspera {
  /// Número corto y legible para identificarla en la lista (1, 2, 3…),
  /// asignado por el store. No es el id de ninguna venta real.
  final int folio;
  final DateTime creadaEn;
  final Cliente? cliente;
  final List<Map<String, dynamic>> items;
  final TipoDescuento? descuentoGlobalTipo;
  final double descuentoGlobalValor;

  const VentaEnEspera({
    required this.folio,
    required this.creadaEn,
    required this.cliente,
    required this.items,
    required this.descuentoGlobalTipo,
    required this.descuentoGlobalValor,
  });

  int get totalUnidades =>
      items.fold(0, (acc, item) => acc + (item['cantidad'] as int));

  /// Subtotal aproximado (precio de lista × cantidad, sin descuentos ni
  /// promociones), solo para mostrar en la lista de espera. El total real se
  /// recalcula al retomarla, igual que cualquier venta.
  double get subtotalAproximado => items.fold(
        0.0,
        (acc, item) =>
            acc + (item['precio'] as num).toDouble() * (item['cantidad'] as int),
      );
}
