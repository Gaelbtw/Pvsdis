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
import 'apartados_view.dart';
import 'caja_view.dart';
import 'clientes_view.dart';
import 'compras_view.dart';
import 'configuracion_view.dart';
import 'inventario_view.dart';
import 'login_view.dart';
import 'pedidos_view.dart';
import 'productos_view.dart';
import 'proveedores_view.dart';
import 'reporte_view.dart';
import 'ventas_view.dart';

class _Modulo {
  const _Modulo(this.titulo, this.subtitulo, this.icono, this.builder);
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final WidgetBuilder builder;
}

/// Inicio en formato **tablero del día**: saludo, buscador, indicadores con
/// datos reales (ventas de hoy, caja, stock bajo), acción principal de Ventas,
/// módulos, y un panel lateral con las últimas ventas y lo que hay por surtir.
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
  List<Map<String, dynamic>> _ultimasVentas = const [];
  List<Map<String, dynamic>> _porSurtir = const [];

  bool get _esAdmin => SessionManager.isAdmin;

  @override
  void initState() {
    super.initState();
    _cargarTablero();
  }

  Future<void> _cargarTablero() async {
    final hoy = DateTime.now();
    final ayer = hoy.subtract(const Duration(days: 1));
    final idUsuario = SessionManager.currentUserId ?? 1;

    try {
      final resultados = await Future.wait([
        _reporte.obtenerReporteVentas(desde: hoy, hasta: hoy, filtrarPorUsuario: false),
        _reporte.obtenerReporteVentas(desde: ayer, hasta: ayer, filtrarPorUsuario: false),
        _caja.obtenerCajaAbierta(idUsuario),
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
        _ultimasVentas = rHoy.ventasRecientes.take(4).toList();
        _porSurtir = bajos.take(4).toList();
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
    await AuditoriaController().registrar(tabla: 'Sesion', accion: 'LOGOUT', descripcion: 'Cierre de sesión');
    SessionManager.clear();
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
              const SizedBox(height: 2),
              const Text('Este es el resumen de hoy',
                  style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const _RelojPill(),
            _pill(Icons.cloud_done_outlined, 'Sincronizado', fondo: AppColors.success.withValues(alpha: 0.12), colorTexto: AppColors.success),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 5, 5, 5),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(SessionManager.currentUserName,
                      style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text(SessionManager.currentUserRole.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.4)),
                ]),
                const SizedBox(width: 8),
                Container(
                  width: 32, height: 32, alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF14151A), shape: BoxShape.circle),
                  child: Text(inicial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: AppText.caption)),
                ),
              ]),
            ),
            if (_esAdmin)
              _botonIcono(Icons.settings_outlined, AppColors.surface, AppColors.textSecondary, () => _abrir((_) => const ConfiguracionView())),
            _botonIcono(Icons.logout, const Color(0xFF14151A), Colors.white, _cerrarSesion),
          ],
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String texto, {required Color fondo, required Color colorTexto}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17, color: colorTexto),
          const SizedBox(width: 7),
          Text(texto, style: TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w700, color: colorTexto)),
        ]),
      );

  Widget _botonIcono(IconData icon, Color fondo, Color color, VoidCallback onTap) => Material(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: color)),
        ),
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
          _chipTecla('F1  Nueva venta'),
          const SizedBox(width: 8),
          _chipTecla('F2  Corte'),
        ]),
      ),
    );
  }

  Widget _chipTecla(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
        child: Text(t, style: const TextStyle(fontSize: AppText.overline, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );

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
          ),
          _kpi(
            icono: Icons.point_of_sale_outlined, iconoColor: AppColors.success,
            label: 'En caja',
            valor: cajaAbierta ? AppConfig.formatoMoneda(_enCaja) : '—',
            pie: cajaAbierta ? '● Abierta${desde != null ? ' desde $desde' : ''}' : 'Sin abrir',
            pieColor: cajaAbierta ? AppColors.success : AppColors.textSecondary,
          ),
          _kpi(
            icono: Icons.warning_amber_rounded, iconoColor: AppColors.warning,
            label: 'Inventario bajo',
            valor: _cargando ? '—' : '$_stockBajo',
            pie: _stockBajo == 1 ? 'producto por surtir' : 'productos por surtir',
            pieColor: AppColors.warning,
            fondo: _stockBajo > 0 ? AppColors.warning.withValues(alpha: 0.08) : null,
            grande: false,
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
    Color? fondo,
    bool grande = true,
  }) {
    return _Hoverable(
      onTap: () {},
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

  Widget _cuerpo() {
    return LayoutBuilder(builder: (context, c) {
      final anchoPanel = 330.0;
      if (c.maxWidth >= 1040) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _modulosGrid()),
            const SizedBox(width: 20),
            SizedBox(width: anchoPanel, child: _panelLateral()),
          ],
        );
      }
      return Column(children: [_modulosGrid(), const SizedBox(height: 20), _panelLateral()]);
    });
  }

  Widget _modulosGrid() {
    final resto = _modulos;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 720 ? 2 : 1;
      // El hero (con Spacer) necesita altura acotada; el GridView es un
      // viewport perezoso que NO soporta dimensiones intrínsecas, así que en
      // vez de envolver en IntrinsicHeight (que reventaba al medir el grid)
      // le damos al hero una altura fija y alineamos ambas columnas arriba.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: SizedBox(height: 300, child: _heroVentas())),
          const SizedBox(width: 16),
          Expanded(
            flex: 7,
            child: GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.75,
              children: resto.map(_tarjetaModulo).toList(),
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

  // -------------------------------------------------------- panel lateral

  Widget _panelLateral() {
    return Column(children: [_panelUltimasVentas(), const SizedBox(height: 16), _panelPorSurtir()]);
  }

  Widget _panelUltimasVentas() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Últimas ventas', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            GestureDetector(
              onTap: () => _abrir((_) => const ReporteView()),
              child: Text('Ver todo', style: TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            ),
          ]),
          const SizedBox(height: 6),
          if (_ultimasVentas.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('Sin ventas hoy.', style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary)))
          else
            ..._ultimasVentas.map(_filaVenta),
        ],
      ),
    );
  }

  Widget _filaVenta(Map<String, dynamic> v) {
    final id = (v['id_venta'] as num?)?.toInt() ?? 0;
    final total = (v['total_neto'] as num?)?.toDouble() ?? (v['total'] as num?)?.toDouble() ?? 0;
    final metodo = (v['metodo_pago'] as String? ?? '').isEmpty ? 'Efectivo' : (v['metodo_pago'] as String);
    final metodoCap = metodo[0].toUpperCase() + metodo.substring(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${id.toString().padLeft(6, '0')}', style: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('${_haceCuanto(v['fecha'] as String?)} · $metodoCap', style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
          ]),
        ),
        Text(AppConfig.formatoMoneda(total), style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ]),
    );
  }

  Widget _panelPorSurtir() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _porSurtir.isEmpty ? Colors.white : AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _porSurtir.isEmpty ? AppColors.border : AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: _porSurtir.isEmpty ? AppColors.textSecondary : AppColors.warning),
            const SizedBox(width: 8),
            Text('Por surtir', style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800, color: _porSurtir.isEmpty ? AppColors.textPrimary : AppColors.warning)),
          ]),
          const SizedBox(height: 6),
          if (_porSurtir.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Todo con existencia suficiente.', style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary)))
          else ...[
            ..._porSurtir.map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text('${p['nombre']}', style: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${(p['cantidad'] as num?)?.toInt() ?? 0} pz', style: TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w800, color: AppColors.warning)),
                  ]),
                )),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _abrir((_) => ComprasView()),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Crear orden de compra', style: TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w800, color: AppColors.warning)),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 17, color: AppColors.warning),
              ]),
            ),
          ],
        ],
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

  String _haceCuanto(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final min = DateTime.now().difference(dt).inMinutes;
    if (min < 1) return 'hace un momento';
    if (min < 60) return 'hace $min min';
    final hrs = min ~/ 60;
    if (hrs < 24) return 'hace $hrs h';
    return 'hace ${hrs ~/ 24} d';
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
