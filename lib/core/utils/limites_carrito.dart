import '../../models/producto_model.dart';

/// Por qué no se puede poner (más de) un producto en el carrito.
enum MotivoRechazoLinea {
  /// El producto está dado de baja: no se vende aunque queden piezas.
  inactivo,

  /// No queda ni una pieza disponible.
  sinExistencia,

  /// Quedan piezas, pero menos de las que se están pidiendo.
  existenciaInsuficiente,
}

/// Veredicto sobre cuánto de un producto cabe en el carrito.
class LimiteLinea {
  final bool permitido;
  final MotivoRechazoLinea? motivo;

  /// Texto listo para mostrarle al cajero. Vacío cuando [permitido] es `true`.
  final String mensaje;

  /// Cuántas piezas de este producto se pueden tener en total en el carrito.
  /// Sirve para recortar una cantidad tecleada en vez de solo rechazarla.
  final int maximo;

  const LimiteLinea._({
    required this.permitido,
    required this.maximo,
    this.motivo,
    this.mensaje = '',
  });
}

/// Decide si el carrito puede llegar a [cantidadDeseada] piezas de [producto]
/// habiendo [disponible] en existencia.
///
/// Es la ÚNICA regla de "cuánto puedo vender de esto", y por eso vive aparte de
/// la pantalla: antes solo el escáner validaba existencias (ver
/// `resolverEscaneo`), mientras que tocar la tarjeta del producto, el botón `+`
/// y teclear la cantidad en la línea aceptaban cualquier número. El cajero se
/// enteraba de que no había inventario **al cobrar**, con el cliente enfrente y
/// la venta ya capturada, en vez de al agregar, que es cuando todavía puede
/// ofrecer otra cosa.
///
/// [disponible] debe ser la existencia DISPONIBLE (física menos lo reservado
/// por apartados), no la física: una pieza ya apartada está vendida para
/// alguien más.
///
/// No conoce el carrito ni la base de datos —recibe números— para poder
/// probarse sin Flutter ni sqflite.
LimiteLinea validarCantidadEnCarrito({
  required Producto producto,
  required int cantidadDeseada,
  required int disponible,
}) {
  if (producto.estado != 'Activo') {
    return LimiteLinea._(
      permitido: false,
      motivo: MotivoRechazoLinea.inactivo,
      mensaje: 'El producto "${producto.nombre}" está inactivo y no se puede vender.',
      maximo: 0,
    );
  }

  final maximo = disponible < 0 ? 0 : disponible;

  if (maximo == 0) {
    return LimiteLinea._(
      permitido: false,
      motivo: MotivoRechazoLinea.sinExistencia,
      mensaje: 'No queda inventario de "${producto.nombre}".',
      maximo: 0,
    );
  }

  if (cantidadDeseada > maximo) {
    return LimiteLinea._(
      permitido: false,
      motivo: MotivoRechazoLinea.existenciaInsuficiente,
      mensaje: 'Inventario insuficiente de "${producto.nombre}": solo quedan $maximo.',
      maximo: maximo,
    );
  }

  return LimiteLinea._(permitido: true, maximo: maximo);
}
