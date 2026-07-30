import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Notificación breve y NO invasiva, con estética de **escritorio**: aparece
/// como una tarjeta compacta anclada a la esquina inferior derecha de la
/// ventana (no una barra a lo ancho abajo, que es el patrón de móvil/tablet).
/// Varias se apilan hacia arriba; la más reciente queda pegada a la esquina.
/// Se cierra sola, se puede cerrar a mano con la «×», y el auto-cierre se
/// pausa mientras el mouse está encima (para poder leerla con calma).
///
/// Reemplaza los diálogos modales de "éxito/aviso" que solo decían "listo,
/// Aceptar" e interrumpían el flujo. Los diálogos modales quedan reservados
/// para confirmaciones reales (borrar, cerrar caja, etc.).
///
/// La API estática (`Toast.exito/info/error(context, mensaje)`) se mantiene
/// idéntica a la versión anterior basada en `SnackBar`, para no tocar los
/// puntos de llamada repartidos por toda la app.
class Toast {
  Toast._();

  static void exito(BuildContext context, String mensaje) =>
      _GestorToasts.instancia.mostrar(context, mensaje, AppColors.success, Icons.check_circle_outline);

  static void info(BuildContext context, String mensaje) =>
      _GestorToasts.instancia.mostrar(context, mensaje, AppColors.primaryDark, Icons.info_outline);

  static void error(BuildContext context, String mensaje) =>
      _GestorToasts.instancia.mostrar(context, mensaje, AppColors.error, Icons.error_outline);
}

/// Métricas de apilado compartidas por todas las tarjetas.
const double _anchoToast = 340;
const double _altoToast = 64;
const double _margen = 24;
const double _separacion = 12;

/// Cuántas tarjetas pueden convivir en pantalla: al superar el tope se cierra
/// la más antigua, para que una ráfaga de avisos no tape media ventana.
const int _maxSimultaneos = 5;

/// Un aviso activo: su datos + la [OverlayEntry] que lo dibuja.
class _ToastActivo {
  _ToastActivo({required this.mensaje, required this.color, required this.icono});

  final String mensaje;
  final Color color;
  final IconData icono;
  OverlayEntry? entrada;
}

/// Mantiene la pila de toasts vivos y los coloca en el overlay raíz de la app.
///
/// Cada toast es su propia [OverlayEntry] insertada en el momento de mostrarse:
/// así siempre queda por encima de lo que haya (incluido un diálogo abierto,
/// caso de las validaciones de formulario que avisan con `Toast.error` sin
/// cerrar el diálogo). El índice dentro de [_activos] determina la altura de
/// cada tarjeta; al insertar/cerrar una, se reconstruyen las demás para que
/// se reacomoden con animación.
class _GestorToasts {
  _GestorToasts._();
  static final _GestorToasts instancia = _GestorToasts._();

  final List<_ToastActivo> _activos = [];

  void mostrar(BuildContext context, String mensaje, Color color, IconData icono) {
    final overlay = Overlay.of(context, rootOverlay: true);

    final toast = _ToastActivo(mensaje: mensaje, color: color, icono: icono);
    toast.entrada = OverlayEntry(
      builder: (_) => _TarjetaToast(
        toast: toast,
        indiceDe: () => _activos.indexOf(toast),
        onCerrar: () => _cerrar(toast),
      ),
    );

    // El más reciente se inserta al frente (índice 0 = pegado a la esquina);
    // los anteriores suben un escalón.
    _activos.insert(0, toast);
    overlay.insert(toast.entrada!);

    // Si nos pasamos del tope, cerramos el más antiguo (final de la lista).
    if (_activos.length > _maxSimultaneos) {
      _cerrar(_activos.last);
    }

    _reacomodar();
  }

  void _cerrar(_ToastActivo toast) {
    if (!_activos.contains(toast)) return;
    toast.entrada?.remove();
    toast.entrada = null;
    _activos.remove(toast);
    _reacomodar();
  }

  void _reacomodar() {
    for (final t in _activos) {
      t.entrada?.markNeedsBuild();
    }
  }
}

/// La tarjeta en sí: anima su entrada (aparece deslizándose desde la derecha),
/// se reacomoda con [AnimatedPositioned] cuando cambia su índice en la pila, y
/// se auto-cierra a los 3 s (pausable al pasar el mouse).
class _TarjetaToast extends StatefulWidget {
  const _TarjetaToast({
    required this.toast,
    required this.indiceDe,
    required this.onCerrar,
  });

  final _ToastActivo toast;
  final int Function() indiceDe;
  final VoidCallback onCerrar;

  @override
  State<_TarjetaToast> createState() => _TarjetaToastState();
}

class _TarjetaToastState extends State<_TarjetaToast> with SingleTickerProviderStateMixin {
  static const _duracionVisible = Duration(seconds: 3);

  late final AnimationController _anim;
  Timer? _temporizador;
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
    _programarCierre();
  }

  void _programarCierre([Duration duracion = _duracionVisible]) {
    _temporizador?.cancel();
    _temporizador = Timer(duracion, _cerrar);
  }

  Future<void> _cerrar() async {
    if (_cerrando) return;
    _cerrando = true;
    _temporizador?.cancel();
    await _anim.reverse();
    widget.onCerrar();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indice = widget.indiceDe();
    // Si la tarjeta ya salió de la pila (índice -1), la dejamos donde estaba
    // para que su animación de salida no salte.
    final escalon = indice < 0 ? 0 : indice;

    final curva = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      right: _margen,
      bottom: _margen + escalon * (_altoToast + _separacion),
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(curva),
          child: MouseRegion(
            // Pausa el auto-cierre mientras se lee; al salir el mouse, da un
            // margen corto y se cierra.
            onEnter: (_) => _temporizador?.cancel(),
            onExit: (_) {
              if (!_cerrando) _programarCierre(const Duration(milliseconds: 1200));
            },
            child: _contenido(),
          ),
        ),
      ),
    );
  }

  Widget _contenido() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _anchoToast,
        height: _altoToast,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(color: widget.toast.color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Icon(widget.toast.icono, color: widget.toast.color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.toast.mensaje,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: AppText.body,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Cierre manual: en escritorio se espera poder descartar el aviso.
            InkWell(
              onTap: _cerrar,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
