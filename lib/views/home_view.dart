import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/toast.dart';

import '../core/utils/mensaje_error.dart';

import '../controllers/auditoria_controller.dart';
import '../controllers/caja_controller.dart';
import '../controllers/producto_controller.dart';
import '../controllers/reporte_controller.dart';
import '../core/config/app_config.dart';
import '../core/licencia/guarda_licencia.dart';
import '../core/licencia/licencia_service.dart';
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
import 'licencia_view.dart';
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

/// Inicio en formato **tablero del día**.
///
/// El orden de la pantalla es el orden de uso real, no el del organigrama:
/// primero las dos cosas que se hacen todos los días (vender y cortar caja),
/// luego los tres números que se miran de reojo, y hasta el final la parrilla
/// de módulos, que se visita cuando hay algo que administrar.
///
/// Antes, Ventas era una tarjeta alta a la izquierda de una parrilla de diez
/// módulos: ocupaba un tercio de la pantalla y competía visualmente con
/// "Proveedores". Ahora es una banda ancha arriba de todo, con el estado de
/// la caja escrito dentro y Enter como atajo real.
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

  /// El aviso de licencia se muestra una vez por arranque, no una vez por
  /// visita al inicio: se vuelve aquí después de cada venta, y un modal cada
  /// vez enseña a cerrarlo sin leerlo.
  static bool _avisoLicenciaMostrado = false;

  @override
  void initState() {
    super.initState();
    _cargarTablero();
    WidgetsBinding.instance.addPostFrameCallback((_) => _avisarLicencia());
  }

  /// Aviso de una sola vez al abrir, para lo que no amerita franja permanente
  /// (una licencia por vencer) y para que lo degradado no pase inadvertido.
  Future<void> _avisarLicencia() async {
    if (_avisoLicenciaMostrado) return;

    final estado = LicenciaService.instancia.estado;
    if (!estado.requiereAvisoAlAbrir) return;

    _avisoLicenciaMostrado = true;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.workspace_premium_outlined,
          size: 32,
          color: estado.estaDegradada ? AppColors.error : AppColors.warning,
        ),
        title: const Text('Licencia'),
        content: Text(estado.mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Después'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _abrir((_) => const LicenciaView());
            },
            child: const Text('Ver licencia'),
          ),
        ],
      ),
    );
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

  /// Configuración queda bloqueada con la licencia vencida, pero la pantalla
  /// de Licencia NO: el cliente tiene que poder activar lo que acaba de pagar
  /// aunque todo lo demás esté restringido. Por eso el guarda desvía ahí en
  /// vez de simplemente negar.
  Future<void> _abrirConfiguracion() async {
    if (!await GuardaLicencia.permite(
      context,
      FuncionLicenciada.configuracion,
    )) {
      return;
    }
    if (!mounted) return;
    await _abrir((_) => const ConfiguracionView());
  }

  Future<void> _abrir(WidgetBuilder builder) async {
    await Navigator.push(context, MaterialPageRoute(builder: builder));
    _cargarTablero();
  }

  Future<void> _cerrarSesion() async {
    try {
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
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo cerrar la sesión. ${mensajeDeError(e)}');
    }
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
    // Enter abre Ventas. La banda de arriba anuncia el atajo, y un atajo
    // anunciado que no funciona es peor que no anunciarlo: se prueba una vez,
    // no pasa nada, y a partir de ahi no se le vuelve a creer a ninguna
    // etiqueta de la app.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _irAVender,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _irAVender,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 20),
                  _accionesPrincipales(),
                  const SizedBox(height: 16),
                  _franjaKpis(),
                  const SizedBox(height: 20),
                  _modulosGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- header

  Widget _header() {
    final inicial = (SessionManager.currentUserName.isNotEmpty
            ? SessionManager.currentUserName[0]
            : '?')
        .toUpperCase();

    return Row(
      children: [
        // El nombre del negocio, no el saludo. En una pantalla que el dueño
        // ve cincuenta veces al día, "Buenas tardes, Miguel" es ruido: ya
        // sabe quién es. Lo que sí sirve es que la pantalla se identifique
        // sola cuando hay dos computadoras en el mostrador.
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            border: AppColors.primaryNecesitaBorde
                ? Border.all(color: AppColors.bordePrimario)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AppConfig.actual.nombreNegocio,
            style: const TextStyle(
              fontSize: AppText.titleLg,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
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
            _abrirConfiguracion();
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

  // ------------------------------------------------ acciones principales

  /// Vender y cortar caja, lo único que se hace todos los días.
  ///
  /// Antes aquí había un buscador falso: una caja con lupa que no buscaba
  /// nada, solo abría Ventas. Prometía una función que no existe y costaba un
  /// clic averiguarlo.
  Widget _accionesPrincipales() {
    return LayoutBuilder(builder: (context, c) {
      final angosto = c.maxWidth < 720;
      final vender = _accionVender();
      final corte = _accionCorte();

      if (angosto) {
        return Column(children: [vender, const SizedBox(height: 14), corte]);
      }
      return Row(children: [
        Expanded(child: vender),
        const SizedBox(width: 16),
        SizedBox(width: 300, child: corte),
      ]);
    });
  }

  Widget _accionVender() {
    final abierta = _cajaAbierta != null;
    final desde = abierta ? _horaDe(_cajaAbierta!.fechaApertura) : null;
    final tinta = AppColors.onPrimary;

    return _Hoverable(
      onTap: _irAVender,
      builder: (hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: AppColors.primaryNecesitaBorde
              ? Border.all(color: AppColors.bordePrimario)
              : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: hover ? 0.42 : 0.30),
              blurRadius: hover ? 24 : 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(children: [
          Icon(Icons.point_of_sale_outlined, size: 38, color: tinta),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Vender',
                    style: TextStyle(
                        fontSize: AppText.heading,
                        fontWeight: FontWeight.w900,
                        color: tinta,
                        height: 1.1)),
                const SizedBox(height: 2),
                Text(
                  // El estado de la caja va DENTRO del botón que lo necesita.
                  // Abrir Ventas sin caja abierta termina en un error a media
                  // venta, con el cliente enfrente.
                  abierta
                      ? 'Caja abierta${desde != null ? ' desde $desde' : ''}'
                      : 'Sin caja abierta — se abre al entrar',
                  style: TextStyle(
                      fontSize: AppText.body,
                      color: tinta.withValues(alpha: 0.78)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tinta.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            // El atajo esta escrito porque de verdad funciona: ver el
            // `CallbackShortcuts` de `build`.
            child: Text('Enter',
                style: TextStyle(
                    fontSize: AppText.small,
                    fontWeight: FontWeight.w800,
                    color: tinta)),
          ),
        ]),
      ),
    );
  }

  Widget _accionCorte() {
    return _Hoverable(
      onTap: () => _abrir((_) => const CajaView()),
      builder: (hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: hover ? AppColors.borderLight : AppColors.border),
          boxShadow: hover ? AppColors.cardShadow : const [],
        ),
        child: Row(children: [
          const Icon(Icons.calculate_outlined,
              size: 28, color: AppColors.textStrong),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Corte de caja',
                    style: TextStyle(
                        fontSize: AppText.bodyLg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(_cajaAbierta != null ? 'Cerrar turno' : 'Abrir turno',
                    style: const TextStyle(
                        fontSize: AppText.small,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  void _irAVender() => _abrir((_) => const VentasView());

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
            // `info` y no un azul suelto: es un color de ESTADO, y los de
            // estado no se derivan del color de marca ni se escriben a mano,
            // para que se lean igual en los 30 negocios.
            icono: Icons.trending_up, iconoColor: AppColors.info,
            label: 'Ventas de hoy',
            valor: _cargando ? '—' : AppConfig.formatoMoneda(_ventasHoy),
            pie: _cambioVsAyer == null ? 'Sin datos de ayer' : '${_cambioVsAyer! >= 0 ? '↑' : '↓'} ${_cambioVsAyer!.abs().toStringAsFixed(0)}% vs. ayer',
            pieColor: _cambioVsAyer == null || _cambioVsAyer! >= 0 ? AppColors.success : AppColors.error,
            onTap: () async {
              if (!await GuardaLicencia.permite(
                context,
                FuncionLicenciada.reportes,
              )) {
                return;
              }
              if (!mounted) return;
              await _abrir((_) => const ReporteView());
            },
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

  // ------------------------------------------------------------ modulos

  /// La parrilla, ya sin la tarjeta gigante de Ventas al lado.
  ///
  /// `mainAxisExtent` (altura fija por tarjeta) y no `childAspectRatio`: con
  /// una proporcion, la altura depende del ancho, y al angostar la ventana
  /// las tarjetas crecian hasta desbordar su contenido.
  Widget _modulosGrid() {
    final modulos = _modulos;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1080
          ? 5
          : c.maxWidth >= 860
              ? 4
              : c.maxWidth >= 620
                  ? 3
                  : c.maxWidth >= 420
                      ? 2
                      : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MÓDULOS',
              style: TextStyle(
                  fontSize: AppText.overline,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: modulos.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 124,
            ),
            itemBuilder: (_, i) => _tarjetaModulo(modulos[i]),
          ),
        ],
      );
    });
  }

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
