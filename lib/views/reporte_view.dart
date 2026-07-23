import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/custom_alert.dart';
import '../controllers/auditoria_controller.dart';
import '../controllers/reporte_controller.dart';
import '../controllers/usuarios_controller.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/auditoria_helpers.dart';
import '../models/auditoria_model.dart';
import '../models/usuarios_model.dart';
import '../services/ticket_compras_service.dart';
import '../services/ticket_service.dart';
import '../widgets/nav_bar.dart';
import 'detalle_venta_view.dart';

class ReporteView extends StatefulWidget {
  const ReporteView({super.key});

  @override
  State<ReporteView> createState() => _ReporteViewState();
}

class _ReporteViewState extends State<ReporteView> {
  final _reporteController = ReporteController();
  final _auditoriaController = AuditoriaController();

  DateTime desde = DateTime.now().subtract(const Duration(days: 6));
  DateTime hasta = DateTime.now();
  bool cargando = false;

  int paginaSeleccionada = 0;

  int totalVentas = 0;
  double ingresosTotales = 0;
  List<Map<String, dynamic>> productosVendidos = [];
  List<Map<String, dynamic>> ventasRecientes = [];

  int totalCompras = 0;
  double gastoTotal = 0;
  List<Map<String, dynamic>> productosComprados = [];
  List<Map<String, dynamic>> comprasRecientes = [];

  // Movimientos por usuario (solo Administrador): reutiliza Auditorias, sin
  // duplicar ningún registro.
  List<Usuarios> usuarios = [];
  List<Auditoria> movimientos = [];
  bool cargandoMovimientos = false;
  int? filtroUsuarioId;
  String? filtroAccion;
  String? filtroTabla;
  DateTime? filtroDesde;
  DateTime? filtroHasta;

  // Cuentas por pagar (solo Administrador): de solo lectura aquí; registrar
  // abonos vive en CuentasPorPagarView para no duplicar esa acción en dos
  // pantallas.
  ReporteCuentasPorPagarResumen? cuentasPorPagar;

  bool get esCajero =>
      SessionManager.currentUserRole == "Cajero";
  int? get usuarioId =>
      SessionManager.currentUserId;

  String get rangoTexto => '${_formatDate(desde)} - ${_formatDate(hasta)}';

  String get tituloReporte => switch (paginaSeleccionada) {
        0 => 'Reporte de Ventas',
        1 => 'Reporte de Compras',
        2 => 'Movimientos por usuario',
        _ => 'Cuentas por pagar',
      };

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _cargarReportes();
    if (!esCajero) {
      _cargarUsuarios();
      _cargarMovimientos();
    }
  }

  Future<void> _cargarUsuarios() async {
    final data = await UsuariosController().obtenerTodos();
    if (!mounted) return;
    setState(() => usuarios = data);
  }

  Future<void> _cargarMovimientos() async {
    setState(() => cargandoMovimientos = true);

    final data = await _auditoriaController.obtenerFiltradas(
      idUsuario: filtroUsuarioId,
      accion: filtroAccion,
      tabla: filtroTabla,
      desde: filtroDesde,
      hasta: filtroHasta,
    );

    if (!mounted) return;
    setState(() {
      movimientos = data;
      cargandoMovimientos = false;
    });
  }

  Future<void> _cargarReportes() async {
    setState(() => cargando = true);

    try {
      await _cargarReportesVentas();
      await _cargarReportesCompras();
      if (!esCajero) {
        await _cargarCuentasPorPagar();
      }
    } finally {
      if (mounted) {
        setState(() => cargando = false);
      }
    }
  }

  Future<void> _cargarCuentasPorPagar() async {
    final resumen = await _reporteController.obtenerReporteCuentasPorPagar(
      desde: desde,
      hasta: hasta,
    );

    if (!mounted) return;
    setState(() => cuentasPorPagar = resumen);
  }

Future<void> _cargarReportesVentas() async {
  final resumen = await _reporteController.obtenerReporteVentas(
    desde: desde,
    hasta: hasta,
    filtrarPorUsuario: esCajero,
    usuarioId: usuarioId,
  );

  if (!mounted) return;

  setState(() {
    totalVentas = resumen.totalVentas;
    ingresosTotales = resumen.ingresosTotales;
    productosVendidos = resumen.productosVendidos;
    ventasRecientes = resumen.ventasRecientes;
  });
}

  Future<void> _cargarReportesCompras() async {
  final resumen = await _reporteController.obtenerReporteCompras(
    desde: desde,
    hasta: hasta,
    filtrarPorUsuario: esCajero,
    usuarioId: SessionManager.currentUserId,
  );

  if (!mounted) return;

  setState(() {
    totalCompras = resumen.totalCompras;
    gastoTotal = resumen.gastoTotal;
    productosComprados = resumen.productosComprados;
    comprasRecientes = resumen.comprasRecientes;
  });
}

  Future<void> _seleccionarRango(int diasAtras) async {
    final now = DateTime.now();
    setState(() {
      desde = now.subtract(Duration(days: diasAtras - 1));
      hasta = now;
    });
    await _cargarReportes();
  }

  Future<void> _seleccionarFechasPersonalizadas() async {
    final fechaInicio = await showDatePicker(
      context: context,
      initialDate: desde,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (fechaInicio == null) return;

    final fechaFin = await showDatePicker(
      context: context,
      initialDate: hasta,
      firstDate: fechaInicio,
      lastDate: DateTime.now(),
    );
    if (fechaFin == null) return;

    setState(() {
      desde = fechaInicio;
      hasta = fechaFin;
    });
    await _cargarReportes();
  }

  Future<void> _imprimirReporte() async {
    final pdf = pw.Document();
    final esVentas = paginaSeleccionada == 0;
    final productos = esVentas ? productosVendidos : productosComprados;
    final movimientos = esVentas ? ventasRecientes : comprasRecientes;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
        ),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    AppConfig.actual.nombreNegocio,
                    style: pw.TextStyle(
                      fontSize: AppText.heading,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(tituloReporte),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber100,
                  borderRadius: pw.BorderRadius.circular(AppRadius.sm),
                ),
                child: pw.Text('Rango: $rangoTexto'),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            children: [
              _pdfResumen(
                esVentas ? 'Ventas realizadas' : 'Compras realizadas',
                esVentas ? '$totalVentas' : '$totalCompras',
              ),
              pw.SizedBox(width: 12),
              _pdfResumen(
                esVentas ? 'Ingresos' : 'Gastos',
                '${AppConfig.formatoMoneda((esVentas ? ingresosTotales : gastoTotal))}',
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            esVentas ? 'Productos mas vendidos' : 'Productos mas comprados',
            style: pw.TextStyle(fontSize: AppText.bodyLg, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _pdfProductos(productos),
          pw.SizedBox(height: 24),
          pw.Text(
            esVentas ? 'Ventas registradas' : 'Compras registradas',
            style: pw.TextStyle(fontSize: AppText.bodyLg, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _pdfMovimientos(movimientos, esVentas),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _pdfResumen(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(AppRadius.sm),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: AppText.title, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfProductos(List<Map<String, dynamic>> productos) {
    if (productos.isEmpty) {
      return pw.Text('Sin productos en este rango.');
    }

    return pw.Table.fromTextArray(
      headers: const ['Producto', 'Cantidad'],
      data: productos
          .map((item) => [item['nombre']?.toString() ?? '', '${item['total']}'])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(8),
    );
  }

  pw.Widget _pdfMovimientos(
    List<Map<String, dynamic>> movimientos,
    bool esVentas,
  ) {
    if (movimientos.isEmpty) {
      return pw.Text('Sin movimientos en este rango.');
    }

    return pw.Table.fromTextArray(
      headers: esVentas
          ? const ['Folio', 'Fecha', 'Cliente', 'Pago', 'Estado', 'Total']
          : const ['Folio', 'Fecha', 'Proveedor', 'Total'],
      data: movimientos.map((item) {
        final fecha = DateTime.tryParse(item['fecha']?.toString() ?? '');
        if (esVentas) {
          final totalNeto = (item['total_neto'] as num?)?.toDouble() ??
              (item['total'] as num?)?.toDouble() ??
              0;
          return [
            '#${item['id_venta']}',
            fecha == null ? '' : _formatDate(fecha),
            item['cliente']?.toString() ?? 'Final',
            item['metodo_pago']?.toString() ?? 'efectivo',
            item['estado']?.toString() ?? 'Activa',
            '${AppConfig.formatoMoneda(totalNeto)}',
          ];
        }

        return [
          '#${item['id_compra']}',
          fecha == null ? '' : _formatDate(fecha),
          item['proveedor']?.toString() ?? 'Sin proveedor',
          '${AppConfig.formatoMoneda(((item['total'] as num?)?.toDouble() ?? 0))}',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.all(8),
    );
  }

  Future<void> _mostrarRecibo(
  int idVenta,
  String metodoPago,
  double total,
  String cliente,
  String fecha,
) async {
  final carrito = await _reporteController.obtenerDetalleVentaParaTicket(idVenta);
  final totales = await _reporteController.obtenerTotalesVentaParaTicket(idVenta);
  final pagos = await _reporteController.obtenerPagosVenta(idVenta);

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: 'Ticket de venta #$idVenta',
      mensaje:
          'Cliente: ${cliente.isNotEmpty ? cliente : 'Consumidor final'}\n\n'
          'Fecha: ${_formatDate(DateTime.parse(fecha))}\n'
          'Método: $metodoPago\n\n'
          '${totales.descuentoTotal > 0 ? 'Subtotal: ${AppConfig.formatoMoneda(totales.subtotal)}\nDescuento: -${AppConfig.formatoMoneda(totales.descuentoTotal)}\n' : ''}'
          'Total: ${AppConfig.formatoMoneda(total)}\n\n'
          '¿Deseas imprimir el ticket?',
      icono: Icons.receipt_long,
      textoCancelar: 'Cerrar',
      textoConfirmar: 'Imprimir',

      onConfirm: () async {
        final pdf = await TicketService.generarTicket(
          carrito: carrito,
          total: totales.total,
          subtotal: totales.subtotal,
          descuento: totales.descuentoTotal,
          pagos: pagos,
          cambio: totales.cambio,
        );

        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdf.save(),
        );
      },
    ),
  );
}

  Future<void> _mostrarReciboCompra(
  int idCompra,
  String proveedor,
  double total,
) async {
  final carrito = await _reporteController.obtenerDetalleCompraParaTicket(idCompra);

  if (carrito.isEmpty) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => const CustomAlert(
        titulo: 'Sin productos',
        mensaje: 'No se encontraron productos para esta compra.',
        icono: Icons.warning_amber_rounded,
        textoConfirmar: 'Aceptar',
      ),
    );

    return;
  }

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: 'Ticket de compra #$idCompra',
      mensaje:
          'Proveedor: $proveedor\n\n'
          'Total: ${AppConfig.formatoMoneda(total)}\n\n'
          '¿Deseas imprimir el ticket de compra?',
      icono: Icons.shopping_bag_outlined,
      textoCancelar: 'Cerrar',
      textoConfirmar: 'Imprimir',

      onConfirm: () async {
        try {
          final pdf = await TicketComprasService.generarTicket(
            carrito: carrito,
            total: total,
            proveedor: proveedor,
          );

          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdf.save(),
          );
        } catch (e) {
          if (!mounted) return;

          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: 'Error',
              mensaje: 'Error al abrir el ticket de compra:\n$e',
              icono: Icons.error_outline,
              textoConfirmar: 'Aceptar',
            ),
          );
        }
      },
    ),
  );
}

  // Solo lectura: registrar abonos vive en CuentasPorPagarView (evita
  // duplicar esa acción en dos pantallas). Reutiliza el mismo rango de
  // fechas (desde/hasta) que Ventas/Compras.
  Widget _buildCuentasPorPagarTab() {
    final resumen = cuentasPorPagar;
    if (resumen == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      children: [
        Row(
          children: [
            _statCard('Deuda total', resumen.deudaTotal, AppColors.error),
            const SizedBox(width: 16),
            _statCard(
              'Salidas de caja (efectivo) en el rango',
              resumen.salidasCajaEfectivo,
              AppColors.warning,
            ),
            const SizedBox(width: 16),
            _statCardEntero('Compras vencidas', resumen.comprasVencidas.length, AppColors.error),
            const SizedBox(width: 16),
            _statCardEntero(
              'Próximos vencimientos (7 días)',
              resumen.proximosVencimientos.length,
              AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _seccionCuentasPorPagar(
          'Deuda por proveedor',
          resumen.deudaPorProveedor.map((r) {
            final saldo = (r['saldo'] as num).toDouble();
            return '${r['proveedor'] ?? 'Sin proveedor'} — ${AppConfig.formatoMoneda(saldo)} (${r['compras']} compra(s))';
          }).toList(),
        ),
        const SizedBox(height: 16),
        _seccionCuentasPorPagar(
          'Compras vencidas',
          resumen.comprasVencidas.map((r) {
            final saldo = (r['saldo'] as num).toDouble();
            return 'Compra #${r['id_compra']} · ${r['proveedor'] ?? 'Sin proveedor'} — Saldo ${AppConfig.formatoMoneda(saldo)}';
          }).toList(),
        ),
        const SizedBox(height: 16),
        _seccionCuentasPorPagar(
          'Próximos vencimientos',
          resumen.proximosVencimientos.map((r) {
            final saldo = (r['saldo'] as num).toDouble();
            return 'Compra #${r['id_compra']} · ${r['proveedor'] ?? 'Sin proveedor'} — Vence ${r['fecha_vencimiento']} — Saldo ${AppConfig.formatoMoneda(saldo)}';
          }).toList(),
        ),
        const SizedBox(height: 16),
        _seccionCuentasPorPagar(
          'Pagos realizados en el rango',
          resumen.pagosRealizados.map((r) {
            final monto = (r['monto'] as num).toDouble();
            return '${r['proveedor'] ?? 'Sin proveedor'} — ${AppConfig.formatoMoneda(monto)} · ${r['usuario'] ?? ''}';
          }).toList(),
        ),
      ],
    );
  }

  Widget _statCard(String label, double valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('${AppConfig.formatoMoneda(valor)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.subtitle, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _statCardEntero(String label, int valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('$valor', style: TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.subtitle, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _seccionCuentasPorPagar(String titulo, List<String> lineas) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (lineas.isEmpty)
            const Text('Sin datos en este rango.', style: TextStyle(color: AppColors.textSecondary))
          else
            ...lineas.map(
              (l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(l),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMovimientosPorUsuarioTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFiltrosMovimientos(),
        const SizedBox(height: 16),
        Expanded(
          child: cargandoMovimientos
              ? const Center(child: CircularProgressIndicator())
              : movimientos.isEmpty
                  ? _emptyState('No hay movimientos con estos filtros.')
                  : ListView(
                      children: [
                        _tablaMovimientosHeader(),
                        const SizedBox(height: 8),
                        ...movimientos.map(_filaMovimiento),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildFiltrosMovimientos() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdownFiltro<int?>(
          label: 'Usuario',
          value: filtroUsuarioId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            ...usuarios.map(
              (u) => DropdownMenuItem(value: u.idUsuario, child: Text(u.nombre)),
            ),
          ],
          onChanged: (value) {
            setState(() => filtroUsuarioId = value);
            _cargarMovimientos();
          },
        ),
        _dropdownFiltro<String?>(
          label: 'Tipo de movimiento',
          value: filtroAccion,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            ...accionesAuditoria.map(
              (a) => DropdownMenuItem(value: a, child: Text(a)),
            ),
          ],
          onChanged: (value) {
            setState(() => filtroAccion = value);
            _cargarMovimientos();
          },
        ),
        _dropdownFiltro<String?>(
          label: 'Módulo',
          value: filtroTabla,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            ...modulosAuditoria.map(
              (t) => DropdownMenuItem(value: t, child: Text(t)),
            ),
          ],
          onChanged: (value) {
            setState(() => filtroTabla = value);
            _cargarMovimientos();
          },
        ),
        OutlinedButton.icon(
          onPressed: _seleccionarFechasMovimientos,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(
            filtroDesde == null || filtroHasta == null
                ? 'Rango de fechas'
                : '${_formatDate(filtroDesde!)} - ${_formatDate(filtroHasta!)}',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
        if (filtroDesde != null || filtroHasta != null)
          TextButton(
            onPressed: () {
              setState(() {
                filtroDesde = null;
                filtroHasta = null;
              });
              _cargarMovimientos();
            },
            child: const Text('Limpiar fechas'),
          ),
        ElevatedButton.icon(
          onPressed: _exportarMovimientosPDF,
          icon: const Icon(Icons.picture_as_pdf, size: 18),
          label: const Text('Exportar PDF'),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
      ],
    );
  }

  Widget _dropdownFiltro<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(label),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _seleccionarFechasMovimientos() async {
    final fechaInicio = await showDatePicker(
      context: context,
      initialDate: filtroDesde ?? DateTime.now().subtract(const Duration(days: 6)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (fechaInicio == null || !mounted) return;

    final fechaFin = await showDatePicker(
      context: context,
      initialDate: filtroHasta ?? DateTime.now(),
      firstDate: fechaInicio,
      lastDate: DateTime.now(),
    );
    if (fechaFin == null) return;

    setState(() {
      filtroDesde = fechaInicio;
      // Fin de día, para no excluir movimientos del último día del rango.
      filtroHasta = DateTime(fechaFin.year, fechaFin.month, fechaFin.day, 23, 59, 59);
    });
    await _cargarMovimientos();
  }

  Widget _tablaMovimientosHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        children: [
          Expanded(flex: 16, child: Text("FECHA Y HORA", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("USUARIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("ACCION", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("MODULO", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("REGISTRO", style: auditoriaHeaderStyle)),
          Expanded(flex: 8, child: Text("CAJA", style: auditoriaHeaderStyle)),
          Expanded(flex: 22, child: Text("DESCRIPCION", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaMovimiento(Auditoria m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(flex: 16, child: Text(formatearFechaHora(m.fechaHora))),
          Expanded(flex: 14, child: Text(m.usuario)),
          Expanded(
            flex: 10,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorPorAccionAuditoria(m.accion).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconoPorAccionAuditoria(m.accion),
                        size: 14, color: colorPorAccionAuditoria(m.accion)),
                    const SizedBox(width: 4),
                    Text(
                      m.accion,
                      style: TextStyle(
                        fontSize: AppText.overline,
                        fontWeight: FontWeight.w800,
                        color: colorPorAccionAuditoria(m.accion),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(flex: 12, child: Text(m.tabla)),
          Expanded(flex: 10, child: Text(m.idRegistro?.toString() ?? '-')),
          Expanded(flex: 8, child: Text(m.idCaja?.toString() ?? '-')),
          Expanded(
            flex: 22,
            child: Text(m.descripcion, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarMovimientosPDF() async {
    if (movimientos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay movimientos para exportar.')),
      );
      return;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: 'Movimientos por usuario'),
          pw.Paragraph(text: 'Generado el ${DateTime.now().toLocal()}'),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headers: [
              'Fecha y hora',
              'Usuario',
              'Acción',
              'Módulo',
              'Registro',
              'Caja',
              'Descripción',
            ],
            data: movimientos.map((m) {
              return [
                formatearFechaHora(m.fechaHora),
                m.usuario,
                m.accion,
                m.tabla,
                m.idRegistro?.toString() ?? '-',
                m.idCaja?.toString() ?? '-',
                m.descripcion,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.amber100),
            cellStyle: const pw.TextStyle(fontSize: AppText.overline),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: tituloReporte, mostrarVolver: true),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  children: [
                    _buildToolbar(),
                    const SizedBox(height: 20),
                    if (paginaSeleccionada == 2)
                      Expanded(child: _buildMovimientosPorUsuarioTab())
                    else if (paginaSeleccionada == 3)
                      Expanded(child: _buildCuentasPorPagarTab())
                    else ...[
                      _buildResumen(),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _buildProductosPanel(),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 6,
                              child: _buildMovimientosPanel(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        _buildTabButton(
          label: 'Ventas',
          icon: Icons.point_of_sale,
          selected: paginaSeleccionada == 0,
          onTap: () => setState(() => paginaSeleccionada = 0),
        ),
        const SizedBox(width: 10),
        _buildTabButton(
          label: 'Compras',
          icon: Icons.shopping_bag_outlined,
          selected: paginaSeleccionada == 1,
          onTap: () => setState(() => paginaSeleccionada = 1),
        ),
        if (!esCajero) ...[
          const SizedBox(width: 10),
          _buildTabButton(
            label: 'Movimientos por usuario',
            icon: Icons.manage_accounts_outlined,
            selected: paginaSeleccionada == 2,
            onTap: () => setState(() => paginaSeleccionada = 2),
          ),
          const SizedBox(width: 10),
          _buildTabButton(
            label: 'Cuentas por pagar',
            icon: Icons.account_balance_wallet_outlined,
            selected: paginaSeleccionada == 3,
            onTap: () => setState(() => paginaSeleccionada = 3),
          ),
        ],
        const SizedBox(width: 18),
        if (!esCajero && paginaSeleccionada != 2 && paginaSeleccionada != 3)
        _buildRangeButton('7 dias', () => _seleccionarRango(7)),
        const SizedBox(width: 8),
        if (!esCajero && paginaSeleccionada != 2 && paginaSeleccionada != 3)
        _buildRangeButton('30 dias', () => _seleccionarRango(30)),
        const SizedBox(width: 8),
        if (!esCajero && paginaSeleccionada != 2 && paginaSeleccionada != 3)
        OutlinedButton.icon(
          onPressed: _seleccionarFechasPersonalizadas,
          icon: const Icon(Icons.date_range, size: 18),
          label: const Text('Rango'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        const Spacer(),
        if (!esCajero && paginaSeleccionada != 2 && paginaSeleccionada != 3)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                rangoTexto,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (!esCajero && paginaSeleccionada != 2 && paginaSeleccionada != 3)
        ElevatedButton.icon(
          onPressed: _imprimirReporte,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('Imprimir reporte'),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      child: Text(label),
    );
  }

  Widget _buildResumen() {
    final esVentas = paginaSeleccionada == 0;
    return Row(
      children: [
        _summaryCard(
          icon: esVentas ? Icons.receipt_long : Icons.shopping_bag_outlined,
          label: esVentas ? 'Ventas realizadas' : 'Compras realizadas',
          value: esVentas ? '$totalVentas' : '$totalCompras',
          color: AppColors.primaryLight,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: esVentas ? Icons.payments_outlined : Icons.account_balance_wallet,
          label: esVentas ? 'Ingresos totales' : 'Gasto total',
          value:
              '${AppConfig.formatoMoneda((esVentas ? ingresosTotales : gastoTotal))}',
          color: const Color(0xFFE8F0D5),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: Icons.trending_up,
          label: esVentas ? 'Ticket promedio' : 'Compra promedio',
          value: _promedioTexto(esVentas),
          color: AppColors.primaryLighter,
        ),
      ],
    );
  }

  String _promedioTexto(bool esVentas) {
    final cantidad = esVentas ? totalVentas : totalCompras;
    final total = esVentas ? ingresosTotales : gastoTotal;

    if (cantidad == 0) return '\$0.00';
    return '${AppConfig.formatoMoneda((total / cantidad))}';
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, color: Colors.black87),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppText.heading,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductosPanel() {
    final esVentas = paginaSeleccionada == 0;
    final productos = esVentas ? productosVendidos : productosComprados;

    return _sectionPanel(
      title: esVentas ? 'Productos mas vendidos' : 'Productos mas comprados',
      icon: Icons.inventory_2_outlined,
      child: productos.isEmpty
          ? _emptyState(
              esVentas
                  ? 'No hay productos vendidos en este rango.'
                  : 'No hay productos comprados en este rango.',
            )
          : ListView.separated(
              itemCount: productos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final item = productos[index];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item['nombre']?.toString() ?? 'Producto',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${item['total']} uds',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildMovimientosPanel() {
    final esVentas = paginaSeleccionada == 0;
    final movimientos = esVentas ? ventasRecientes : comprasRecientes;

    return _sectionPanel(
      title: esVentas ? 'Ventas del periodo' : 'Compras del periodo',
      icon: Icons.list_alt,
      child: movimientos.isEmpty
          ? _emptyState(
              esVentas
                  ? 'No hay ventas para este rango.'
                  : 'No hay compras para este rango.',
            )
          : ListView.separated(
              itemCount: movimientos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                return esVentas
                    ? _ventaTile(movimientos[index])
                    : _compraTile(movimientos[index]);
              },
            ),
    );
  }

  Widget _sectionPanel({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppText.subtitle,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _ventaTile(Map<String, dynamic> venta) {
    final fecha = DateTime.tryParse(venta['fecha']?.toString() ?? '');
    final total = (venta['total'] as num?)?.toDouble() ?? 0;
    final totalNeto = (venta['total_neto'] as num?)?.toDouble() ?? total;
    final cliente = venta['cliente']?.toString() ?? 'Consumidor final';
    final metodoPago = venta['metodo_pago']?.toString() ?? 'efectivo';
    final idVenta = venta['id_venta'] as int;
    final estado = venta['estado']?.toString() ?? 'Activa';

    return _movementTile(
      icon: Icons.point_of_sale,
      title: 'Venta #$idVenta',
      subtitle:
          '${fecha == null ? 'Sin fecha' : _formatDate(fecha)}  |  $cliente  |  $metodoPago',
      total: totalNeto,
      estado: estado,
      onDetalle: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetalleVentaView(idVenta: idVenta)),
        );
        await _cargarReportesVentas();
      },
      onReceipt: () => _mostrarRecibo(
        idVenta,
        metodoPago,
        total,
        cliente,
        venta['fecha']?.toString() ?? '',
      ),
    );
  }

  Widget _compraTile(Map<String, dynamic> compra) {
    final fecha = DateTime.tryParse(compra['fecha']?.toString() ?? '');
    final total = (compra['total'] as num?)?.toDouble() ?? 0;
    final proveedor = compra['proveedor']?.toString() ?? 'Sin proveedor';

    return _movementTile(
      icon: Icons.shopping_bag_outlined,
      title: 'Compra #${compra['id_compra']}',
      subtitle: '${fecha == null ? 'Sin fecha' : _formatDate(fecha)}  |  $proveedor',
      total: total,
      onReceipt: () => _mostrarReciboCompra(
        compra['id_compra'] as int,
        proveedor,
        total,
      ),
    );
  }

  Widget _movementTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required double total,
    required VoidCallback onReceipt,
    String? estado,
    VoidCallback? onDetalle,
  }) {
    final colorEstado = switch (estado) {
      'Cancelada' => AppColors.error,
      'Parcialmente devuelta' => AppColors.warning,
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (colorEstado != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorEstado.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          estado!,
                          style: TextStyle(
                            color: colorEstado,
                            fontSize: AppText.overline,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${AppConfig.formatoMoneda(total)}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.bodyLg),
          ),
          const SizedBox(width: 8),
          if (onDetalle != null)
            IconButton(
              tooltip: 'Ver detalle',
              onPressed: onDetalle,
              icon: const Icon(Icons.visibility_outlined),
            ),
          IconButton(
            tooltip: 'Imprimir ticket',
            onPressed: onReceipt,
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: AppColors.disabled),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
