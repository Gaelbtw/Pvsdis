import '../../models/producto_model.dart';

enum TipoResultadoEscaneo { agregado, noEncontrado, inactivo, stockInsuficiente }

/// Resultado de procesar un código escaneado/ingresado en Ventas. No
/// contiene lógica: solo describe qué pasó, para que la vista decida cómo
/// mostrarlo.
class ResultadoEscaneo {
  final TipoResultadoEscaneo tipo;
  final Producto? producto;
  final String mensaje;

  const ResultadoEscaneo._(this.tipo, this.producto, this.mensaje);

  factory ResultadoEscaneo.agregado(Producto producto) =>
      ResultadoEscaneo._(TipoResultadoEscaneo.agregado, producto, '');

  factory ResultadoEscaneo.noEncontrado() => const ResultadoEscaneo._(
        TipoResultadoEscaneo.noEncontrado,
        null,
        'Código no encontrado.',
      );

  factory ResultadoEscaneo.inactivo(Producto producto) => ResultadoEscaneo._(
        TipoResultadoEscaneo.inactivo,
        producto,
        'El producto "${producto.nombre}" está inactivo y no se puede vender.',
      );

  factory ResultadoEscaneo.stockInsuficiente(Producto producto) => ResultadoEscaneo._(
        TipoResultadoEscaneo.stockInsuficiente,
        producto,
        'Stock insuficiente de "${producto.nombre}".',
      );
}

/// Decide qué debe pasar al escanear [codigo]: localizar el producto entre
/// [productos] (por código de barras exacto), validar que esté activo y que
/// haya stock suficiente para sumar una unidad más a las [cantidadEnCarrito]
/// que ya tiene. No toca base de datos ni estado de UI, para poder probarse
/// sin Flutter ni sqflite.
ResultadoEscaneo resolverEscaneo({
  required String codigo,
  required List<Producto> productos,
  required Map<int, int> stockDisponible,
  required int Function(int? idProducto) cantidadEnCarrito,
}) {
  final normalizado = Producto.normalizarCodigoBarras(codigo);
  if (normalizado == null) return ResultadoEscaneo.noEncontrado();

  Producto? producto;
  for (final p in productos) {
    if (p.codigoBarras == normalizado) {
      producto = p;
      break;
    }
  }

  if (producto == null) return ResultadoEscaneo.noEncontrado();
  if (producto.estado != 'Activo') return ResultadoEscaneo.inactivo(producto);

  final stock = stockDisponible[producto.idProducto] ?? 0;
  if (cantidadEnCarrito(producto.idProducto) + 1 > stock) {
    return ResultadoEscaneo.stockInsuficiente(producto);
  }

  return ResultadoEscaneo.agregado(producto);
}
