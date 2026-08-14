/// Por qué se movió el inventario a mano.
///
/// Antes todo ajuste manual se guardaba con el texto fijo "Ajuste manual de
/// stock": la bitácora registraba QUÉ cambió y QUIÉN lo cambió, pero no si
/// faltaban piezas porque se rompieron, porque se regalaron o porque alguien
/// tecleó mal la existencia al dar de alta el producto. Sin esa distinción no
/// se puede medir la merma, que es justo lo que un negocio necesita vigilar.
///
/// El valor que se guarda en `Movimiento_Inventario.motivo` es [etiqueta]
/// (texto legible, no el nombre del enum) para que la bitácora siga siendo
/// entendible al leerla directo de la base de datos o exportada a CSV.
enum MotivoAjusteInventario {
  conteoFisico('Conteo físico'),
  merma('Merma (dañado o caducado)'),
  regalo('Regalo o cortesía'),
  errorCaptura('Corrección de captura'),
  entradaMercancia('Entrada de mercancía'),
  otro('Otro');

  const MotivoAjusteInventario(this.etiqueta);

  final String etiqueta;

  /// Motivo por defecto de una entrada rápida desde Inventario: sumar piezas
  /// casi siempre es mercancía que acaba de llegar.
  static const MotivoAjusteInventario porDefectoEntrada = entradaMercancia;

  /// Motivo por defecto al corregir la existencia de un producto: lo más
  /// común es que se esté cuadrando contra un conteo físico.
  static const MotivoAjusteInventario porDefectoAjuste = conteoFisico;

  /// Recupera el motivo a partir de la [etiqueta] guardada en la bitácora.
  /// `null` si el texto no corresponde a ninguno (por ejemplo, movimientos
  /// anteriores a que existieran los motivos).
  static MotivoAjusteInventario? porEtiqueta(String? etiqueta) {
    if (etiqueta == null) return null;
    for (final motivo in MotivoAjusteInventario.values) {
      if (motivo.etiqueta == etiqueta) return motivo;
    }
    return null;
  }
}
