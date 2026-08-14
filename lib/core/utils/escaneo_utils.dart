import '../../models/producto_model.dart';
import 'limites_carrito.dart';

enum TipoResultadoEscaneo { agregado, noEncontrado, inactivo, stockInsuficiente }

/// Resultado de procesar un código escaneado/ingresado en Ventas. No
/// contiene lógica: solo describe qué pasó, para que la vista decida cómo
/// mostrarlo.
class ResultadoEscaneo {
  final TipoResultadoEscaneo tipo;
  final Producto? producto;
  final String mensaje;

  /// Cuántas piezas hay que agregar. Es 1 salvo que se haya usado el
  /// multiplicador (ver [interpretarEntradaEscaneo]).
  final int cantidad;

  const ResultadoEscaneo._(this.tipo, this.producto, this.mensaje, {this.cantidad = 1});

  factory ResultadoEscaneo.agregado(Producto producto, {int cantidad = 1}) =>
      ResultadoEscaneo._(TipoResultadoEscaneo.agregado, producto, '', cantidad: cantidad);

  factory ResultadoEscaneo.noEncontrado() => const ResultadoEscaneo._(
        TipoResultadoEscaneo.noEncontrado,
        null,
        'Código no encontrado.',
      );

  /// El [mensaje] lo arma [validarCantidadEnCarrito], para que el aviso sea
  /// idéntico se llegue por el lector o por la pantalla.
  factory ResultadoEscaneo.inactivo(Producto producto, String mensaje) =>
      ResultadoEscaneo._(TipoResultadoEscaneo.inactivo, producto, mensaje);

  factory ResultadoEscaneo.stockInsuficiente(Producto producto, String mensaje) =>
      ResultadoEscaneo._(TipoResultadoEscaneo.stockInsuficiente, producto, mensaje);
}

/// Decide qué debe pasar al escanear [codigo]: localizar el producto entre
/// [productos], validar que esté activo y que haya stock suficiente para sumar
/// una unidad más a las [cantidadEnCarrito] que ya tiene. No toca base de datos
/// ni estado de UI, para poder probarse sin Flutter ni sqflite.
///
/// La búsqueda es por código de barras exacto y, si ninguno coincide, por SKU
/// exacto: la etiqueta que el negocio imprime para lo que se vende a granel
/// lleva su clave interna, no un código de fabricante, y el lector la manda por
/// el mismo camino. El código de barras tiene prioridad para que agregar una
/// clave nueva no pueda cambiar a qué producto responde un código ya en uso.
///
/// Las reglas de "cuánto cabe" viven en [validarCantidadEnCarrito], compartidas
/// con los demás caminos de la pantalla (tocar la tarjeta, el botón `+`,
/// teclear la cantidad): antes cada uno decidía por su cuenta y este era el
/// único que validaba de verdad.
ResultadoEscaneo resolverEscaneo({
  required String codigo,
  required List<Producto> productos,
  required Map<int, int> stockDisponible,
  required int Function(int? idProducto) cantidadEnCarrito,
}) {
  // Primero se intenta el texto COMPLETO como código. Solo si no corresponde a
  // ningún producto se interpreta como "cantidad × código": así, una clave que
  // de casualidad se vea como multiplicador (un SKU '3X4') sigue ganando sobre
  // esa lectura.
  var producto = _buscarProducto(codigo, productos);
  var cantidad = 1;

  if (producto == null) {
    final entrada = interpretarEntradaEscaneo(codigo);
    if (entrada.tieneMultiplicador) {
      producto = _buscarProducto(entrada.codigo, productos);
      cantidad = entrada.cantidad;
    }
  }

  if (producto == null) return ResultadoEscaneo.noEncontrado();

  final limite = validarCantidadEnCarrito(
    producto: producto,
    cantidadDeseada: cantidadEnCarrito(producto.idProducto) + cantidad,
    disponible: stockDisponible[producto.idProducto] ?? 0,
  );

  if (!limite.permitido) {
    return limite.motivo == MotivoRechazoLinea.inactivo
        ? ResultadoEscaneo.inactivo(producto, limite.mensaje)
        : ResultadoEscaneo.stockInsuficiente(producto, limite.mensaje);
  }

  return ResultadoEscaneo.agregado(producto, cantidad: cantidad);
}

/// Busca por código de barras exacto y, si no hay, por SKU exacto.
Producto? _buscarProducto(String codigo, List<Producto> productos) {
  final normalizado = Producto.normalizarCodigoBarras(codigo);
  if (normalizado == null) return null;

  for (final p in productos) {
    if (p.codigoBarras == normalizado) return p;
  }
  for (final p in productos) {
    if (p.sku == normalizado) return p;
  }

  return null;
}

/// Lo que el cajero tecleó/escaneó, ya separado en cantidad y código.
class EntradaEscaneo {
  final int cantidad;
  final String codigo;

  /// `true` si el texto venía con multiplicador ("3*750...").
  final bool tieneMultiplicador;

  const EntradaEscaneo({
    required this.cantidad,
    required this.codigo,
    required this.tieneMultiplicador,
  });
}

/// Separa el multiplicador de cantidad del código.
///
/// Vender doce piezas iguales obligaba a escanear doce veces o a corregir la
/// cantidad a mano en la línea. Con esto el cajero teclea `12*` y pasa el
/// lector: como el lector escribe en el mismo campo y termina con Enter, el
/// texto llega junto ("12*7501234567890"). Se aceptan `*`, `x` y `×` como
/// separador, con o sin espacios, hasta 4 dígitos de cantidad.
EntradaEscaneo interpretarEntradaEscaneo(String texto) {
  final match = RegExp(r'^\s*(\d{1,4})\s*[*xX×]\s*(\S.*)$').firstMatch(texto);

  if (match == null) {
    return EntradaEscaneo(cantidad: 1, codigo: texto, tieneMultiplicador: false);
  }

  final cantidad = int.parse(match.group(1)!);

  // "0*algo" no tiene sentido como cantidad; se trata como texto normal en vez
  // de agregar cero piezas en silencio.
  if (cantidad <= 0) {
    return EntradaEscaneo(cantidad: 1, codigo: texto, tieneMultiplicador: false);
  }

  return EntradaEscaneo(
    cantidad: cantidad,
    codigo: match.group(2)!.trim(),
    tieneMultiplicador: true,
  );
}
