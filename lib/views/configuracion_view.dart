import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../controllers/auditoria_controller.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/configuracion_model.dart';
import '../services/configuracion_service.dart';
import '../widgets/menu_card.dart';
import '../widgets/nav_bar.dart';
import '../widgets/toast.dart';
import 'apartados_view.dart';
import 'auditorias_view.dart';
import 'base_datos_view.dart';
import 'cuentas_por_pagar_view.dart';
import 'pedidos_view.dart';
import 'promociones_view.dart';
import 'reporte_view.dart';
import 'sync_config_view.dart';
import 'usuarios_view.dart';

class ConfiguracionView extends StatefulWidget {
  const ConfiguracionView({super.key});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  final _configuracionService = ConfiguracionService();

  bool cargando = true;

  TimeOfDay matutinoInicio = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay matutinoFin = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay vespertinoInicio = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay vespertinoFin = const TimeOfDay(hour: 21, minute: 0);

  final stockCtrl = TextEditingController();
  final fondoCtrl = TextEditingController();

  final nombreCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final correoCtrl = TextEditingController();
  final rfcCtrl = TextEditingController();
  final monedaCtrl = TextEditingController();
  final ivaCtrl = TextEditingController();
  final mensajeTicketCtrl = TextEditingController();
  final descuentoMaximoCtrl = TextEditingController();

  bool descuentoCajeroPuedeAplicar = true;
  bool descuentoCajeroRequiereAutorizacion = true;
  bool mostrarIvaDesglosado = false;

  String tamanoPapel = '80mm';
  bool autoImprimirTicket = false;
  String? impresoraUrl;
  String? impresoraNombre;

  /// Sección activa del panel de configuración (índice en [_secciones]).
  int _seccion = 0;

  /// Secciones del panel. El 4.º campo es el grupo temático: se muestra como
  /// encabezado en la barra lateral para separar visualmente los ajustes del
  /// negocio, de ventas, de operación y de administración.
  static const _secciones = <(IconData, String, String, String)>[
    (Icons.storefront_outlined, 'Negocio', 'Nombre, logo y datos de contacto', 'NEGOCIO'),
    (Icons.palette_outlined, 'Apariencia', 'Color principal del sistema', 'NEGOCIO'),
    (Icons.receipt_long_outlined, 'Ticket y ventas', 'Moneda, IVA y mensaje del ticket', 'VENTAS'),
    (Icons.sell_outlined, 'Descuentos', 'Límite y permisos del cajero', 'VENTAS'),
    (Icons.print_outlined, 'Impresión', 'Papel, impresora y ticket automático', 'VENTAS'),
    (Icons.schedule_outlined, 'Turnos', 'Horario matutino y vespertino', 'OPERACIÓN'),
    (Icons.inventory_2_outlined, 'Inventario y caja', 'Inventario mínimo y fondo de caja', 'OPERACIÓN'),
    (Icons.grid_view_rounded, 'Accesos', 'Usuarios, reportes, respaldos y más', 'ADMINISTRACIÓN'),
  ];

  String? logoPath;
  late Color colorSeleccionado;

  static const _paletaColores = [
    Color(0xFFF2C500), // dorado (default)
    Color(0xFF2563EB), // azul
    Color(0xFF16A34A), // verde
    Color(0xFFDC2626), // rojo
    Color(0xFF9333EA), // morado
    Color(0xFFEA580C), // naranja
    Color(0xFF0D9488), // verde azulado
    Color(0xFF334155), // gris azulado oscuro
  ];

  @override
  void initState() {
    super.initState();
    colorSeleccionado = AppColors.primary;
    cargarConfig();
  }

  Future<void> cargarConfig() async {
    final config = await _configuracionService.obtener();

    setState(() {
      stockCtrl.text = config.stockMinimo.toString();
      fondoCtrl.text = config.fondoCaja.toString();

      matutinoInicio = _parseHora(config.horaInicioMatutino);
      matutinoFin = _parseHora(config.horaFinMatutino);
      vespertinoInicio = _parseHora(config.horaInicioVespertino);
      vespertinoFin = _parseHora(config.horaFinVespertino);

      nombreCtrl.text = config.nombreNegocio;
      direccionCtrl.text = config.direccion ?? '';
      telefonoCtrl.text = config.telefono ?? '';
      correoCtrl.text = config.correo ?? '';
      rfcCtrl.text = config.rfc ?? '';
      monedaCtrl.text = config.simboloMoneda;
      ivaCtrl.text = config.tasaImpuestoPorcentaje == 0
          ? ''
          : config.tasaImpuestoPorcentaje.toString();
      mostrarIvaDesglosado = config.mostrarIvaDesglosado;
      tamanoPapel = config.tamanoPapel;
      autoImprimirTicket = config.autoImprimirTicket;
      impresoraUrl = config.impresoraUrl;
      impresoraNombre = config.impresoraNombre;
      mensajeTicketCtrl.text = config.mensajeTicket;
      logoPath = config.logoPath;
      colorSeleccionado = Color(config.colorPrimario);

      descuentoMaximoCtrl.text = config.descuentoMaximoPorcentaje.toString();
      descuentoCajeroPuedeAplicar = config.descuentoCajeroPuedeAplicar;
      descuentoCajeroRequiereAutorizacion = config.descuentoCajeroRequiereAutorizacion;

      cargando = false;
    });
  }

  Future<void> seleccionarLogo() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.image,
    );

    final rutaOrigen = resultado?.files.single.path;
    if (rutaOrigen == null) return;

    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : Directory(await getDatabasesPathFallback());

    final extension = p.extension(rutaOrigen);
    final destino = p.join(baseDir.path, 'logo$extension');

    await File(rutaOrigen).copy(destino);

    setState(() {
      logoPath = destino;
    });
  }

  /// En Android/iOS no existe getApplicationSupportDirectory con el mismo
  /// significado que en desktop; se usa el directorio de documentos.
  Future<String> getDatabasesPathFallback() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _seleccionarImpresora() async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer == null || !mounted) return;
    setState(() {
      impresoraUrl = printer.url;
      impresoraNombre = printer.name;
    });
  }

  Future<void> guardar() async {
    if (stockCtrl.text.trim().isEmpty ||
        fondoCtrl.text.trim().isEmpty ||
        nombreCtrl.text.trim().isEmpty) {
      Toast.error(context, "Faltan datos: el nombre del negocio, el inventario mínimo y el fondo de caja son obligatorios.");
      return;
    }

    final nuevaConfig = Configuracion(
      horaInicioMatutino: format(matutinoInicio),
      horaFinMatutino: format(matutinoFin),
      horaInicioVespertino: format(vespertinoInicio),
      horaFinVespertino: format(vespertinoFin),
      stockMinimo: int.parse(stockCtrl.text),
      fondoCaja: double.parse(fondoCtrl.text),
      nombreNegocio: nombreCtrl.text.trim(),
      logoPath: logoPath,
      direccion: direccionCtrl.text.trim().isEmpty ? null : direccionCtrl.text.trim(),
      telefono: telefonoCtrl.text.trim().isEmpty ? null : telefonoCtrl.text.trim(),
      correo: correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
      rfc: rfcCtrl.text.trim().isEmpty ? null : rfcCtrl.text.trim(),
      simboloMoneda: monedaCtrl.text.trim().isEmpty ? r'$' : monedaCtrl.text.trim(),
      tasaImpuestoPorcentaje: double.tryParse(ivaCtrl.text.trim()) ?? 0,
      mostrarIvaDesglosado: mostrarIvaDesglosado,
      tamanoPapel: tamanoPapel,
      autoImprimirTicket: autoImprimirTicket,
      impresoraUrl: impresoraUrl,
      impresoraNombre: impresoraNombre,
      mensajeTicket: mensajeTicketCtrl.text.trim().isEmpty
          ? Configuracion.porDefecto().mensajeTicket
          : mensajeTicketCtrl.text.trim(),
      colorPrimario: colorSeleccionado.toARGB32(),
      descuentoMaximoPorcentaje:
          (double.tryParse(descuentoMaximoCtrl.text.trim()) ?? 20).clamp(0, 100).toDouble(),
      descuentoCajeroPuedeAplicar: descuentoCajeroPuedeAplicar,
      descuentoCajeroRequiereAutorizacion: descuentoCajeroRequiereAutorizacion,
    );

    await _configuracionService.guardar(nuevaConfig);
    AppConfig.actualizar(nuevaConfig);

    await AuditoriaController().registrar(
      tabla: 'Configuracion',
      accion: 'EDIT',
      descripcion: 'Configuración del negocio actualizada',
    );

    if (!mounted) return;

    Toast.exito(
      context,
      colorSeleccionado.toARGB32() != AppColors.primary.toARGB32()
          ? "Configuración guardada. El nuevo color de marca se aplicará al reiniciar la app."
          : "Configuración guardada.",
    );
  }

  String format(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  TimeOfDay _parseHora(String hora) {
    final parts = hora.split(":");
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> pickHora(bool inicio, bool matutino) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      if (matutino) {
        inicio ? matutinoInicio = picked : matutinoFin = picked;
      } else {
        inicio ? vespertinoInicio = picked : vespertinoFin = picked;
      }
    });
  }

  /// Accesos administrativos que antes vivían como tarjetas sueltas en el
  /// inicio del Administrador (Usuarios, Reportes, Auditorías, Base de
  /// datos) más Apartados, Promociones y Pedidos, agrupados aquí para no
  /// duplicar accesos en dos partes distintas de la app.
  Widget _accesosAdministracion(BuildContext context) {
    final accesos = <Widget>[
      MenuCard(
        title: "Usuarios",
        subtitle: "Gestión de usuarios",
        icon: Icons.person,
        color: AppColors.primaryLight,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsuariosView()),
        ),
      ),
      MenuCard(
        title: "Reportes",
        subtitle: "Análisis y estadísticas",
        icon: Icons.bar_chart,
        color: AppColors.primaryLighter,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReporteView()),
        ),
      ),
      MenuCard(
        title: "Actividad",
        subtitle: "Registro de movimientos",
        icon: Icons.fact_check_outlined,
        color: AppColors.primaryLighter,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AuditoriasView()),
        ),
      ),
      MenuCard(
        title: "Copias de seguridad",
        subtitle: "Respaldo y restauración",
        icon: Icons.storage_rounded,
        color: AppColors.primaryLighter,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BaseDatosView()),
        ),
      ),
      MenuCard(
        title: "Apartados",
        subtitle: "Reservas con anticipo",
        icon: Icons.event_available,
        color: AppColors.primaryLighter,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApartadosView()),
        ),
      ),
      MenuCard(
        title: "Promociones",
        subtitle: "Descuentos automáticos",
        icon: Icons.local_offer,
        color: AppColors.primaryLight,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PromocionesView()),
        ),
      ),
      MenuCard(
        title: "Pedidos",
        subtitle: "Gestión de pedidos",
        icon: Icons.receipt_long,
        color: AppColors.primaryLight,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PedidosView()),
        ),
      ),
      MenuCard(
        title: "Cuentas por pagar",
        subtitle: "Deuda con proveedores",
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.primaryLighter,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CuentasPorPagarView()),
        ),
      ),
      MenuCard(
        title: "Sincronización",
        subtitle: "Conexión con la nube",
        icon: Icons.cloud_sync_outlined,
        color: AppColors.primaryLight,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SyncConfigView()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Estos módulos no aparecen en el inicio para mantenerlo enfocado en la venta diaria. Ábrelos desde aquí cuando los necesites.",
          style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            int columnas = 2;
            if (constraints.maxWidth >= 700) columnas = 3;
            if (constraints.maxWidth >= 1000) columnas = 4;

            return GridView.count(
              crossAxisCount: columnas,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: constraints.maxWidth >= 700 ? 1.15 : 1.3,
              children: accesos,
            );
          },
        ),
      ],
    );
  }

  Widget sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLighter,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: AppText.bodyLg,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: AppText.small,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget customInput({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget horaButton({
    required String label,
    required String hora,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, color: AppColors.primaryDark, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: AppText.caption, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hora,
                    style: const TextStyle(
                      fontSize: AppText.bodyLg,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF9F9A93)),
          ],
        ),
      ),
    );
  }

  Widget _logoSelector() {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.borderLight),
          ),
          clipBehavior: Clip.antiAlias,
          child: logoPath != null && File(logoPath!).existsSync()
              ? Image.file(File(logoPath!), fit: BoxFit.cover)
              : Icon(Icons.storefront_outlined, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: seleccionarLogo,
            icon: const Icon(Icons.upload_outlined),
            label: Text(logoPath == null ? "Subir logo" : "Cambiar logo"),
          ),
        ),
      ],
    );
  }

  Widget _selectorColor() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _paletaColores.map((color) {
        final seleccionado = color.toARGB32() == colorSeleccionado.toARGB32();
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => setState(() => colorSeleccionado = color),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: seleccionado ? AppColors.textPrimary : Colors.transparent,
                width: 3,
              ),
            ),
            child: seleccionado
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SessionManager.isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: CustomHeader(titulo: "Configuración", mostrarVolver: Navigator.canPop(context), mostrarInfo: false),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Acceso restringido. Esta sección es solo para administradores.",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.body),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: "Configuración", mostrarVolver: Navigator.canPop(context), mostrarInfo: false),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              // El cuerpo scrollea y las columnas se alinean arriba con altura
              // natural: así el panel se ajusta a su contenido y las secciones
              // cortas ya no dejan un gran vacío blanco.
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _navSecciones(),
                      const SizedBox(width: 24),
                      Expanded(child: _panelSeccion()),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ------------------------------------------- navegación de secciones

  Widget _navSecciones() {
    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _secciones.length; i++) ...[
            // Encabezado del grupo: se muestra al empezar un grupo nuevo.
            if (i == 0 || _secciones[i].$4 != _secciones[i - 1].$4)
              Padding(
                padding: EdgeInsets.fromLTRB(14, i == 0 ? 2 : 18, 14, 8),
                child: Text(
                  _secciones[i].$4,
                  style: const TextStyle(
                    fontSize: AppText.overline,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _navItem(i),
          ],
        ],
      ),
    );
  }

  Widget _navItem(int i) {
    final (icon, label, _, _) = _secciones[i];
    final sel = _seccion == i;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: sel ? AppColors.primary.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => setState(() => _seccion = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: sel ? AppColors.primaryDark : AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                      fontSize: AppText.body,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                      color: sel ? AppColors.textPrimary : AppColors.textSecondary,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------- panel de la sección

  Widget _contenidoSeccion(int i) {
    switch (i) {
      case 0:
        return _seccionNegocio();
      case 1:
        return _seccionApariencia();
      case 2:
        return _seccionTicket();
      case 3:
        return _seccionDescuentos();
      case 4:
        return _seccionImpresion();
      case 5:
        return _seccionTurnos();
      case 6:
        return _seccionInventarioCaja();
      case 7:
        return _accesosAdministracion(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _panelSeccion() {
    final (icon, titulo, subtitulo, _) = _secciones[_seccion];
    final esAccesos = _seccion == _secciones.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: AppColors.primaryLighter, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(icon, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitulo, style: const TextStyle(fontSize: AppText.small, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: _contenidoSeccion(_seccion),
          ),
          if (!esAccesos) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: guardar,
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text("Guardar cambios"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      textStyle: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bloque(String titulo, Widget contenido) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          contenido,
        ],
      );

  Widget _seccionNegocio() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _logoSelector(),
          const SizedBox(height: 16),
          customInput(controller: nombreCtrl, hint: "Nombre del negocio"),
          const SizedBox(height: 12),
          customInput(controller: direccionCtrl, hint: "Dirección"),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: customInput(controller: telefonoCtrl, hint: "Teléfono", keyboard: TextInputType.phone)),
            const SizedBox(width: 12),
            Expanded(child: customInput(controller: correoCtrl, hint: "Correo", keyboard: TextInputType.emailAddress)),
          ]),
          const SizedBox(height: 12),
          customInput(controller: rfcCtrl, hint: "RFC / dato fiscal (opcional)"),
        ],
      );

  Widget _seccionTicket() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: customInput(controller: monedaCtrl, hint: "Símbolo de moneda (ej. \$)")),
            const SizedBox(width: 12),
            Expanded(child: customInput(controller: ivaCtrl, hint: "IVA % (ej. 16)", keyboard: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          const SizedBox(height: 12),
          customInput(controller: mensajeTicketCtrl, hint: "Mensaje al final del ticket"),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Desglosar IVA en el ticket"),
            subtitle: const Text("Muestra base (sin IVA) e IVA por separado, en vez de solo \"IVA incluido\""),
            value: mostrarIvaDesglosado,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => mostrarIvaDesglosado = v),
          ),
        ],
      );

  Widget _seccionImpresion() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: tamanoPapel,
            decoration: const InputDecoration(labelText: "Tamaño de papel", border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: '58mm', child: Text("58 mm (angosto)")),
              DropdownMenuItem(value: '80mm', child: Text("80 mm (estándar)")),
            ],
            onChanged: (v) => setState(() => tamanoPapel = v ?? '80mm'),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.print_outlined),
            title: Text(impresoraNombre ?? "Sin impresora seleccionada"),
            subtitle: const Text("Impresora para auto-imprimir"),
            trailing: OutlinedButton(onPressed: _seleccionarImpresora, child: const Text("Elegir")),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Imprimir automáticamente al cobrar"),
            subtitle: const Text("Sin diálogo de impresión. Requiere una impresora seleccionada"),
            value: autoImprimirTicket,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => autoImprimirTicket = v),
          ),
        ],
      );

  Widget _seccionApariencia() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Elige el color principal del sistema. Se usa en los botones, encabezados y detalles de toda la app.",
            style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          _selectorColor(),
          const SizedBox(height: 18),
          _nota("El nuevo color se aplica por completo al reiniciar la aplicación."),
        ],
      );

  Widget _seccionTurnos() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Define el horario de cada turno. Las cajas y las ventas se clasifican automáticamente según la hora en que ocurren.",
            style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _bloque(
            "TURNO MATUTINO",
            Row(children: [
              Expanded(child: horaButton(label: "Hora de inicio", hora: format(matutinoInicio), onTap: () => pickHora(true, true))),
              const SizedBox(width: 14),
              Expanded(child: horaButton(label: "Hora de fin", hora: format(matutinoFin), onTap: () => pickHora(false, true))),
            ]),
          ),
          const SizedBox(height: 22),
          _bloque(
            "TURNO VESPERTINO",
            Row(children: [
              Expanded(child: horaButton(label: "Hora de inicio", hora: format(vespertinoInicio), onTap: () => pickHora(true, false))),
              const SizedBox(width: 14),
              Expanded(child: horaButton(label: "Hora de fin", hora: format(vespertinoFin), onTap: () => pickHora(false, false))),
            ]),
          ),
        ],
      );

  Widget _seccionInventarioCaja() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _bloque("INVENTARIO MÍNIMO", customInput(controller: stockCtrl, hint: "Ej. 5 piezas", keyboard: TextInputType.number))),
            const SizedBox(width: 16),
            Expanded(child: _bloque("FONDO DE CAJA", customInput(controller: fondoCtrl, hint: "Ej. 500", keyboard: TextInputType.number))),
          ]),
          const SizedBox(height: 14),
          _nota("Cuando un producto llega al inventario mínimo, se marca como \"por agotarse\" para que sepas cuándo reabastecer. El fondo de caja es el dinero con el que inicia cada turno."),
        ],
      );

  /// Nota informativa breve al pie de una sección.
  Widget _nota(String texto) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: const TextStyle(fontSize: AppText.caption, color: AppColors.textSecondary, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _seccionDescuentos() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          customInput(
            controller: descuentoMaximoCtrl,
            hint: "Umbral (% a partir del cual se exige motivo)",
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("El cajero puede aplicar descuentos"),
            value: descuentoCajeroPuedeAplicar,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => descuentoCajeroPuedeAplicar = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Requiere autorización de administrador al superar el umbral"),
            value: descuentoCajeroRequiereAutorizacion,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => descuentoCajeroRequiereAutorizacion = v),
          ),
        ],
      );
}
