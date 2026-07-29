import '../../models/cliente_model.dart';
import '../../models/venta_en_espera.dart';
import '../utils/descuento_utils.dart';

/// Almacén en memoria de las ventas puestas en espera. Es un singleton de
/// proceso: sobrevive al navegar entre pantallas (para poder retomar una
/// venta pausada aunque el cajero salga y vuelva al POS), pero NO persiste si
/// se cierra la app — igual que el "hold" de una caja registradora física,
/// que se pierde al apagarla.
class VentasEnEsperaStore {
  VentasEnEsperaStore._();
  static final VentasEnEsperaStore instancia = VentasEnEsperaStore._();

  final List<VentaEnEspera> _ventas = [];
  int _folioSeq = 0;

  List<VentaEnEspera> get ventas => List.unmodifiable(_ventas);
  bool get hayVentas => _ventas.isNotEmpty;
  int get cantidad => _ventas.length;

  VentaEnEspera guardar({
    required List<Map<String, dynamic>> items,
    Cliente? cliente,
    TipoDescuento? descuentoGlobalTipo,
    double descuentoGlobalValor = 0,
  }) {
    final venta = VentaEnEspera(
      folio: ++_folioSeq,
      creadaEn: DateTime.now(),
      cliente: cliente,
      items: items,
      descuentoGlobalTipo: descuentoGlobalTipo,
      descuentoGlobalValor: descuentoGlobalValor,
    );
    _ventas.add(venta);
    return venta;
  }

  void eliminar(VentaEnEspera venta) => _ventas.remove(venta);

  void limpiar() => _ventas.clear();
}
