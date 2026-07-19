import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lógica de los atajos de teclado de Ventas, separada de `VentasView` para
/// poder probarla sin depender de sus cargas asíncronas reales (productos,
/// caja, promociones), que son las que hacen inestable montar la vista
/// completa en un widget test.
///
/// - Las decisiones puras (a qué línea saltar, si ya se puede confirmar la
///   venta) son funciones sueltas, sin estado.
/// - [VentasAtajos] es el único widget con `CallbackShortcuts`: aplica la
///   misma guarda "no dispares si se está escribiendo" a F4/flechas/Delete
///   (F2 y Escape sí deben funcionar siempre) y delega el resto a los
///   callbacks que le pase `VentasView`.

/// Calcula la nueva línea seleccionada del carrito al mover [delta] (-1
/// arriba, +1 abajo) desde [actual]. `null` si el carrito está vacío.
int? moverSeleccionCarrito({
  required int? actual,
  required int delta,
  required int totalLineas,
}) {
  if (totalLineas == 0) return null;

  final base = actual ?? (delta > 0 ? -1 : totalLineas);
  return (base + delta).clamp(0, totalLineas - 1);
}

/// Mismas 3 condiciones que ya habilitan el botón "Confirmar Venta": carrito
/// con productos, pagos válidos y una caja abierta.
bool puedeConfirmarVenta({
  required bool carritoVacio,
  required bool pagosValidos,
  required bool cajaAbierta,
}) {
  return !carritoVacio && pagosValidos && cajaAbierta;
}

/// Envuelve [child] con los atajos de teclado de Ventas.
class VentasAtajos extends StatelessWidget {
  final Widget child;
  final VoidCallback onEnfocarBusqueda;
  final VoidCallback onConfirmarVenta;
  final VoidCallback onEscape;
  final void Function(int delta) onMoverSeleccion;
  final VoidCallback onEliminarSeleccionada;

  const VentasAtajos({
    super.key,
    required this.child,
    required this.onEnfocarBusqueda,
    required this.onConfirmarVenta,
    required this.onEscape,
    required this.onMoverSeleccion,
    required this.onEliminarSeleccionada,
  });

  /// `true` si el foco actual está dentro de un campo de texto editable
  /// (cualquier `TextField`/`TextFormField`, sin importar cuál). Se usa
  /// para que F4/flechas/Delete no disparen una acción por accidente
  /// mientras el usuario está escribiendo.
  static bool estaEscribiendoEnCampoDeTexto() {
    final foco = FocusManager.instance.primaryFocus;
    final ctx = foco?.context;
    if (ctx == null) return false;

    var enCampo = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        enCampo = true;
        return false;
      }
      return true;
    });
    return enCampo;
  }

  void _siNoEstaEscribiendo(VoidCallback accion) {
    if (estaEscribiendoEnCampoDeTexto()) return;
    accion();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): onEnfocarBusqueda,
        const SingleActivator(LogicalKeyboardKey.f4): () => _siNoEstaEscribiendo(onConfirmarVenta),
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            () => _siNoEstaEscribiendo(() => onMoverSeleccion(-1)),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            () => _siNoEstaEscribiendo(() => onMoverSeleccion(1)),
        const SingleActivator(LogicalKeyboardKey.delete):
            () => _siNoEstaEscribiendo(onEliminarSeleccionada),
      },
      child: child,
    );
  }
}
