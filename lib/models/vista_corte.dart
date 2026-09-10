import '../controllers/caja_controller.dart';

/// Que numeros puede ver en pantalla quien esta a punto de cerrar la caja.
///
/// El arqueo a ciegas ya existia, pero a medias: se ocultaba el **total**
/// del efectivo esperado y se mostraban todos sus **sumandos** —fondo
/// inicial, ventas en efectivo, cambio entregado, devoluciones—. Con una
/// calculadora, el numero "oculto" salia en veinte segundos, y un control que
/// se rodea en veinte segundos no es un control: es una molestia para el
/// cajero honesto y nada para el otro.
///
/// La regla ahora cabe en un renglon y se puede probar:
///
/// > **Si un numero es sumando del efectivo esperado, quien cuenta a ciegas
/// > no lo ve antes de cerrar.**
///
/// Tarjeta, transferencia y numero de tickets si se muestran: no entran al
/// cajon, no aparecen en la formula del esperado, y al cajero le sirven para
/// cuadrar sus vouchers durante el turno.
///
/// El total vendido se oculta aunque no sea un sumando directo, porque se
/// despeja: vendido − tarjeta − transferencia = ventas en efectivo.
///
/// Nada de esto es permanente. Al cerrar se revela todo (ver
/// `CajaView`), y ademas sale impreso en el corte del cajero: contar a ciegas
/// es un orden de operaciones, no un secreto.
class VistaCorte {
  const VistaCorte({required this.resumen, required this.aCiegas});

  final ResumenCaja resumen;

  /// `true` cuando quien tiene la caja abierta es la persona auditada y no
  /// quien audita. Lo decide la vista con `SessionManager.isCajero`.
  final bool aCiegas;

  // --- Siempre visible: nada de esto entra en el efectivo esperado ---

  int get tickets => resumen.ticketsCerrados;
  double get ventasTarjeta => resumen.ventasTarjeta;
  double get ventasTransferencia => resumen.ventasTransferencia;
  double get anticiposTarjeta => resumen.anticiposTarjeta;
  double get anticiposTransferencia => resumen.anticiposTransferencia;
  double get totalNoEfectivo => resumen.totalNoEfectivo;

  // --- Visible solo cuando NO se cuenta a ciegas ---

  /// Los renglones con signo que suman el efectivo esperado. Lista vacia
  /// mientras se cuenta a ciegas.
  List<({String etiqueta, double importe, bool suma})> get renglonesEfectivo =>
      aCiegas ? const [] : resumen.renglonesEfectivo;

  double? get efectivoEsperado => aCiegas ? null : resumen.efectivoEsperado;

  /// Se oculta a ciegas porque se despeja: restarle tarjeta y transferencia
  /// deja las ventas en efectivo, que si es sumando del esperado.
  double? get totalVendido => aCiegas ? null : resumen.totalVentas;

  /// Todos los montos que la pantalla tiene permitido dibujar en este estado.
  ///
  /// Existe para la prueba `NINGUN SUMANDO DEL ESPERADO SE FILTRA`: si
  /// alguien agrega mas adelante un dato de efectivo a la pantalla del cajero
  /// y olvida esta regla, esa prueba truena. Sin esta lista, la unica forma de
  /// notar la fuga seria que un cliente la descubriera antes.
  List<double> get montosVisibles => [
        ventasTarjeta,
        ventasTransferencia,
        anticiposTarjeta,
        anticiposTransferencia,
        totalNoEfectivo,
        if (!aCiegas) ...[
          ...renglonesEfectivo.map((r) => r.importe),
          resumen.efectivoEsperado,
          resumen.totalVentas,
        ],
      ];

  /// Los sumandos del efectivo esperado, para contrastar contra
  /// [montosVisibles]. No se muestra ninguno de estos mientras [aCiegas].
  List<double> get sumandosDelEsperado => [
        resumen.fondoInicial,
        resumen.ventasEfectivo,
        resumen.anticiposEfectivo,
        resumen.entradasEfectivo,
        resumen.cambioEntregado,
        resumen.cambioAnticipos,
        resumen.devoluciones,
        resumen.pagosProveedoresEfectivo,
        resumen.salidasEfectivo,
      ];
}
