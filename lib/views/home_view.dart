import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/auditoria_controller.dart';
import '../controllers/caja_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/reporte_controller.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/caja_model.dart';
import '../widgets/custom_alert.dart';
import 'apartados_view.dart';
import 'caja_view.dart';
import 'clientes_view.dart';
import 'compras_view.dart';
import 'configuracion_view.dart';
import 'cuentas_por_pagar_view.dart';
import 'inventario_view.dart';
import 'login_view.dart';
import 'pedidos_view.dart';
import 'productos_view.dart';
import 'promociones_view.dart';
import 'proveedores_view.dart';
import 'reporte_view.dart';
import 'ventas_view.dart';
import '../core/security/permisos_service.dart';

class _Modulo {
  const _Modulo(this.titulo, this.subtitulo, this.icono, this.builder);
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final WidgetBuilder builder;
}

/// Inicio en formato **tablero del día**: saludo, buscador, indicadores con
/// datos reales (ventas de hoy, caja, inventario bajo), acción principal de
/// Ventas y la parrilla de módulos.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final _reporte = ReporteController();
  final _caja = CajaController();
  final _producto = ProductoController();

  bool _cargando = true;
  double _ventasHoy = 0;
  double? _cambioVsAyer;
  Caja? _cajaAbierta;
  double _enCaja = 0;
  int _stockBajo = 0;

  bool get _esAdmin => SessionManager.isAdmin;

  @override
  void initState() {
    super.initState();
    _cargarTablero();
  }

  Future<void> _cargarTablero() async {
    final hoy = DateTime.now();
    final ayer = hoy.subtract(const Duration(days: 1));
    final idUsuario = SessionManager.currentUserId;

    try {
      final resultados = await Future.wait([
        _reporte.obtenerReporteVentas(desde: hoy, hasta: hoy, filtrarPorUsuario: false),
        _reporte.obtenerReporteVentas(desde: ayer, hasta: ayer, filtrarPorUsuario: false),
        // Sin sesión no hay caja abierta que mostrar en el KPI.
        idUsuario == null ? Future<Caja?>.value() : _caja.obtenerCajaAbierta(idUsuario),
        _producto.obtenerConStock(),
      ]);

      final rHoy = resultados[0] as ReporteVentasResumen;
      final rAyer = resultados[1] as ReporteVentasResumen;
      final caja = resultados[2] as Caja?;
      final productos = resultados[3] as List<Map<String, dynamic>>;

      double enCaja = 0;
      if (caja?.idCaja != null) {
        enCaja = (await _caja.calcularResumenCaja(caja!.idCaja!)).efectivoEsperado;
      }

      final bajos = productos.where((p) {
        final min = (p['stock_minimo'] as num?)?.toInt() ?? 0;
        final cant = (p['cantidad'] as num?)?.toInt() ?? 0;
        return min > 0 && cant <= min;
      }).toList();

      if (!mounted) return;
      setState(() {
        _ventasHoy = rHoy.ingresosTotales;
        _cambioVsAyer = rAyer.ingresosTotales > 0
            ? (rHoy.ingresosTotales - rAyer.ingresosTotales) / rAyer.ingresosTotales * 100
            : null;
        _cajaAbierta = caja;
        _enCaja = enCaja;
        _stockBajo = bajos.length;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(WidgetBuilder builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    _cargarTablero();
  }

  Future<void> _cerrarSesion() async {
    // Si el usuario tiene una caja abierta, primero debe hacer el corte de
    // caja: no se le deja cerrar sesión (ni cambiar de cuenta) con el efectivo
    // sin cuadrar. Este aviso SÍ es importante y se mantiene como modal.
    final idUsuario = SessionManager.currentUserId;
    if (idUsuario != null) {
      final caja = await _caja.obtenerCajaAbierta(idUsuario);
      if (caja != null) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => CustomAlert(
            titulo: 'Tienes una caja abierta',
            mensaje: 'Antes de cerrar sesión debes hacer el corte de caja.',
            icono: Icons.point_of_sale_outlined,
            color: AppColors.warning,
            textoCancelar: 'Ahora no',
            textoConfirmar: 'Ir a caja',
            onConfirm: () => _abrir((_) => const CajaView()),
          ),
        );
        return;
      }
    }

    await AuditoriaController().registrar(tabla: 'Sesion', accion: 'LOGOUT', descripcion: 'Cierre de sesión');
    SessionManager.clear();
    // La matriz cargada en memoria pertenece al usuario que se va: si no se
    // descarta, el siguiente login la hereda hasta que `cargar()` la
    // reemplace.
    PermisosService.instancia.limpiar();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginView()), (r) => false);
  }

  List<_Modulo> get _modulos => _esAdmin
      ? [
          _Modulo('Productos', 'Gestión de productos', Icons.inventory_2_outlined, (_) => const ProductosView()),
          _Modulo('Clientes', 'Base de clientes', Icons.groups_outlined, (_) => const ClientesView()),
          _Modulo('Inventario', 'Control de existencias', Icons.layers_outlined, (_) => const InventarioView()),
          _Modulo('Proveedores', 'Gestión de proveedores', Icons.local_shipping_outlined, (_) => const ProveedorView()),
          _Modulo('Compras', 'Compras a proveedores', Icons.shopping_cart_outlined, (_) => ComprasView()),
          _Modulo('Pedidos', 'Gestión de pedidos', Icons.receipt_long_outlined, (_) => const PedidosView()),
          _Modulo('Apartados', 'Reservas con anticipo', Icons.bookmark_outline, (_) => const ApartadosView()),
          _Modulo('Promociones', 'Descuentos automáticos', Icons.local_offer_outlined, (_) => const PromocionesView()),
          _Modulo('Cuentas por pagar', 'Deuda con proveedores', Icons.account_balance_wallet_outlined, (_) => const CuentasPorPagarView()),
          _Modulo('Caja', 'Apertura, cierre e historial', Icons.point_of_sale_outlined, (_) => const CajaView()),
        ]
      : [
          _Modulo('Apartados', 'Reservas con anticipo', Icons.bookmark_outline, (_) => const ApartadosView()),
          _Modulo('Clientes', 'Base de clientes', Icons.groups_outlined, (_) => const ClientesView()),
          _Modulo('Inventario', 'Control de existencias', Icons.layers_outlined, (_) => const InventarioView()),
          _Modulo('Pedidos', 'Gestión de pedidos', Icons.receipt_long_outlined, (_) => const PedidosView()),
          _Modulo('Reportes', 'Análisis', Icons.bar_chart_outlined, (_) => const ReporteView()),
          _Modulo('Compras', 'Compras a proveedores', Icons.shopping_cart_outlined, (_) => ComprasView()),
          _Modulo('Caja', 'Apertura, cierre e historial', Icons.point_of_sale_outlined, (_) => const CajaView()),
        ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 20),
              _buscador(),
              const SizedBox(height: 20),
              _franjaKpis(),
              const SizedBox(height: 20),
              _cuerpo(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- header

  Widget _header() {
    final h = DateTime.now().hour;
    final saludo = h < 12 ? 'Buenos días' : (h < 19 ? 'Buenas tardes' : 'Buenas noches');
    final inicial = (SessionManager.currentUserName.isNotEmpty ? SessionManager.currentUserName[0] : '?').toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$saludo, ${SessionManager.currentUserName}',
                  style: const TextStyle(fontSize: AppText.heading, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _RelojPill(),
            _menuUsuario(inicial),
          ],
        ),
      ],
    );
  }

  /// Avatar de la cuenta (solo la inicial). Al hacer clic despliega el menú de
  /// sesión: Configuración (solo admin), cambiar de cuenta y cerrar sesión.
  Widget _menuUsuario(String inicial) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      offset: const Offset(0, 48),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(SessionManager.currentUserName,
                  style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(SessionManager.currentUserRoleLabel,
                  style: const TextStyle(fontSize: AppText.overline, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (_esAdmin)
          PopupMenuItem<String>(value: 'config', child: _itemMenu(Icons.settings_outlined, 'Configuración')),
        PopupMenuItem<String>(value: 'cambiar', child: _itemMenu(Icons.switch_account_outlined, 'Cambiar de cuenta')),
        PopupMenuItem<String>(value: 'salir', child: _itemMenu(Icons.logout, 'Cerrar sesión', color: AppColors.error)),
      ],
      onSelected: (v) {
        switch (v) {
          case 'config':
            _abrir((_) => const ConfiguracionView());
            break;
          case 'cambiar':
          case 'salir':
            _cerrarSesion();
            break;
        }
      },
      child: Container(
        width: 40, height: 40, alignment: Alignment.center,
        decoration: const BoxDecoration(color: Color(0xFF14151A), shape: BoxShape.circle),
        child: Text(inicial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: AppText.body)),
      ),
    );
  }

  Widget _itemMenu(IconData icon, String label, {Color? color}) => Row(
        children: [
          Icon(icon, size: 19, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
        ],
      );

  // ----------------------------------------------------------- buscador

  Widget _buscador() {
    return GestureDetector(
      onTap: () => _abrir((_) => const VentasView()),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.search, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Buscar producto, cliente o ticket…', style: TextStyle(fontSize: AppText.body, color: AppColors.textSecondary)),
          ),
        ]),
      ),
    );
  }

  // --------------------------------------------------------------- KPIs

  Widget _franjaKpis() {
    final cajaAbierta = _cajaAbierta != null;
    final desde = cajaAbierta ? _horaDe(_cajaAbierta!.fechaApertura) : null;

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 760 ? 3 : (c.maxWidth >= 460 ? 2 : 1);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2.6,
        children: [
          _kpi(
            icono: Icons.trending_up, iconoColor: const Color(0xFF2740C6),
            label: 'Ventas de hoy',
            valor: _cargando ? '—' : AppConfig.formatoMoneda(_ventasHoy),
            pie: _cambioVsAyer == null ? 'Sin datos de ayer' : '${_cambioVsAyer! >= 0 ? '↑' : '↓'} ${_cambioVsAyer!.abs().toStringAsFixed(0)}% vs. ayer',
            pieColor: _cambioVsAyer == null || _cambioVsAyer! >= 0 ? AppColors.success : AppColors.error,
            onTap: () => _abrir((_) => const ReporteView()),
          ),
          _kpi(
            icono: Icons.point_of_sale_outlined, iconoColor: AppColors.success,
            label: 'En caja',
            // `_enCaja` ES el efectivo esperado. Mostrárselo al cajero en el
            // dashboard anulaba por completo el arqueo ciego del cierre (ver
            // `CajaView.arqueoCiego`): no hacía falta ni entrar a Caja, el
            // número estaba en la pantalla de inicio todo el turno. Para el
            // cajero la tarjeta solo informa si la caja está abierta.
            valor: !cajaAbierta
                ? '—'
                : SessionManager.isCajero
                    ? '•••'
                    : AppConfig.formatoMoneda(_enCaja),
            pie: cajaAbierta ? '● Abierta${desde != null ? ' desde $desde' : ''}' : 'Sin abrir',
            pieColor: cajaAbierta ? AppColors.success : AppColors.textSecondary,
            onTap: () => _abrir((_) => const CajaView()),
          ),
          _kpi(
            icono: Icons.warning_amber_rounded, iconoColor: AppColors.warning,
            label: 'Inventario bajo',
            valor: _cargando ? '—' : '$_stockBajo',
            pie: _stockBajo == 1 ? 'producto por surtir' : 'productos por surtir',
            pieColor: AppColors.warning,
            fondo: _stockBajo > 0 ? AppColors.warning.withValues(alpha: 0.08) : null,
            grande: false,
            onTap: () => _abrir((_) => const InventarioView()),
          ),
        ],
      );
    });
  }

  Widget _kpi({
    required IconData icono,
    required Color iconoColor,
    required String label,
    required String valor,
    required String pie,
    required Color pieColor,
    required VoidCallback onTap,
    Color? fondo,
    bool grande = true,
  }) {
    return _Hoverable(
      onTap: onTap,
      builder: (hover) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
        decoration: BoxDecoration(
          color: fondo ?? Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: hover ? AppColors.borderLight : AppColors.border),
          boxShadow: hover ? AppColors.cardShadow : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(icono, size: 18, color: iconoColor),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor, style: TextStyle(fontSize: grande ? AppText.display : AppText.heading, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.0)),
            ),
            const SizedBox(height: 3),
            Text(pie, style: TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w700, color: pieColor)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- cuerpo

  Widget _cuerpo() => _modulosGrid();

  Widget _modulosGrid() {
    final resto = _modulos;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
      // El hero (con Spacer) necesita altura acotada → altura fija.
      // El GridView usa `mainAxisExtent` (altura fija por tarjeta) en vez de
      // `childAspectRatio`: así la altura de la tarjeta NO depende del ancho.
      // Esto evita el overflow del contenido y mantiene la parrilla compacta,
      // para que todo el dashboard quepa sin cortarse abajo.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: SizedBox(height: 300, child: _heroVentas())),
          const SizedBox(width: 16),
          Expanded(
            flex: 7,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: resto.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 132,
              ),
              itemBuilder: (_, i) => _tarjetaModulo(resto[i]),
            ),
          ),
        ],
      );
    });
  }

  Widget _heroVentas() {
    return _Hoverable(
      onTap: () => _abrir((_) => const VentasView()),
      builder: (hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
        constraints: const BoxConstraints(minHeight: 300),
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primary, AppColors.primaryDark]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: hover ? 0.45 : 0.30), blurRadius: 30, offset: const Offset(0, 16))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.point_of_sale_outlined, size: 30, color: AppColors.onPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(999)),
                child: Text('MÁS USADO', style: TextStyle(color: AppColors.onPrimary, fontSize: AppText.overline, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              ),
            ]),
            const Spacer(),
            Text('Ventas', style: TextStyle(color: AppColors.onPrimary, fontSize: AppText.display + 6, fontWeight: FontWeight.w900, height: 1.0)),
            const SizedBox(height: 6),
            Text('Registrar una nueva venta', style: TextStyle(color: AppColors.onPrimary.withValues(alpha: 0.88), fontSize: AppText.body)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: AppColors.onPrimary, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Nueva venta', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: AppText.body)),
                const SizedBox(width: 8),
                _chipEnHero('F1'),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 19, color: AppColors.primaryDark),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipEnHero(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: AppColors.primaryDark.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: AppText.overline)),
      );

  Widget _tarjetaModulo(_Modulo m) {
    final mostrarBadge = m.titulo == 'Inventario' && _stockBajo > 0;
    return _Hoverable(
      onTap: () => _abrir(m.builder),
      builder: (hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: hover ? AppColors.cardShadow : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.primaryLighter, borderRadius: BorderRadius.circular(13)),
                child: Icon(m.icono, size: 24, color: AppColors.primaryDark),
              ),
              const Spacer(),
              if (mostrarBadge)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                  child: Text('$_stockBajo bajos', style: TextStyle(fontSize: AppText.overline, fontWeight: FontWeight.w800, color: AppColors.warning)),
                ),
            ]),
            const Spacer(),
            Text(m.titulo, style: const TextStyle(fontSize: AppText.subtitle, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(m.subtitulo, style: const TextStyle(fontSize: AppText.small, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- utils

  String _horaDe(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'p.m.' : 'a.m.'}';
  }

}

/// Pastillas de fecha + hora, con la hora actualizándose sola cada segundo.
class _RelojPill extends StatefulWidget {
  const _RelojPill();
  @override
  State<_RelojPill> createState() => _RelojPillState();
}

class _RelojPillState extends State<_RelojPill> {
  late Timer _timer;
  DateTime _ahora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _ahora = DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _pill(Icons.calendar_today_outlined, _fecha(_ahora)),
      const SizedBox(width: 10),
      _pill(Icons.schedule, _hora(_ahora)),
    ]);
  }

  Widget _pill(IconData icon, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 7),
          Text(t, style: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ]),
      );

  String _fecha(DateTime v) {
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    return '${dias[v.weekday - 1]}, ${v.day} de ${meses[v.month - 1]}';
  }

  String _hora(DateTime v) {
    final h = v.hour % 12 == 0 ? 12 : v.hour % 12;
    return '$h:${v.minute.toString().padLeft(2, '0')}:${v.second.toString().padLeft(2, '0')} ${v.hour >= 12 ? 'p.m.' : 'a.m.'}';
  }
}

/// Wrapper de hover (cursor + lift). Motion nativo, sin paquetes.
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.builder, required this.onTap});
  final Widget Function(bool hover) builder;
  final VoidCallback onTap;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(onTap: widget.onTap, child: widget.builder(_hover)),
    );
  }
}
