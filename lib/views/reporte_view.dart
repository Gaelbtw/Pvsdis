import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/utils/csv.dart';
import '../services/exportacion_service.dart';
import '../widgets/custom_alert.dart';
import '../widgets/toast.dart';
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
import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';

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

  /// Utilidad del rango (solo con permiso `verGanancias`). `null` mientras no
  /// se haya cargado.
  ReporteUtilidadResumen? utilidad;

  /// Ordena "productos más vendidos" por utilidad en vez de por unidades (ver
  /// [_buildProductosPanel]).
  bool _ordenPorUtilidad = false;

  /// Movimientos de inventario del rango y filtro de tipo activo (`null` =
  /// todos).
  ReporteMovimientosInventario movimientosInventario =
      ReporteMovimientosInventario.vacio;
  String? filtroTipoMovimiento;

  /// Tipos de movimiento con su etiqueta legible. Los valores son los del
  /// CHECK de `Movimiento_Inventario` (los mismos nombres que el backend, ver
  /// `MovimientoInventarioLogger`), así que no se traducen al filtrar.
  static const _tiposMovimiento = <(String, String)>[
    ('EntradaCompra', 'Entrada por compra'),
    ('SalidaVenta', 'Salida por venta'),
    ('AjustePositivo', 'Ajuste positivo'),
    ('AjusteNegativo', 'Ajuste negativo'),
    ('DevolucionVenta', 'Devolución de venta'),
    ('DevolucionCompra', 'Devolución a proveedor'),
    ('TransferenciaEntrada', 'Transferencia recibida'),
    ('TransferenciaSalida', 'Transferencia enviada'),
  ];

  final _exportacionService = ExportacionService();

  /// Evita que un doble clic lance dos exportaciones a la vez (dos archivos
  /// casi idénticos y dos ventanas del Explorador).
  bool _exportando = false;

  /// Vista recortada del reporte: solo las ventas propias, sin filtros de
  /// fecha y sin las pestañas globales. Se decide por el permiso
  /// `verGanancias` (márgenes, costos y utilidad), no por el rol: antes era
  /// `rol == "Cajero"`, así que desmarcar "Ver ganancias" a un Supervisor en
  /// la matriz de permisos no tenía ningún efecto.
  bool get vistaRestringida =>
      !PermisosService.instancia.puedeActual(Permiso.verGanancias);
  int? get usuarioId =>
      SessionManager.currentUserId;

  String get rangoTexto => '${_formatDate(desde)} - ${_formatDate(hasta)}';

  String get tituloReporte => switch (paginaSeleccionada) {
        0 => 'Reporte de Ventas',
        1 => 'Reporte de Compras',
        2 => 'Movimientos por usuario',
        3 => 'Cuentas por pagar',
        4 => 'Utilidad',
        _ => 'Movimientos de inventario',
      };

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _cargarReportes();
    if (!vistaRestringida) {
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
      if (!vistaRestringida) {
        await _cargarCuentasPorPagar();
        await _cargarUtilidad();
        await _cargarMovimientosInventario();
      }
    } finally {
      if (mounted) {
        setState(() => cargando = false);
      }
    }
  }

  /// Exporta a CSV lo que está viendo la pestaña activa.
  ///
  /// Exporta EL DETALLE, no las tarjetas de resumen: quien pide el archivo
  /// (normalmente el contador) quiere las filas para hacer sus propias sumas.
  /// Los totales los recalcula Excel.
  Future<void> _exportarReporte() async {
    setState(() => _exportando = true);

    try {
      final (nombre, encabezados, filas) = _datosParaExportar();

      if (filas.isEmpty) {
        if (!mounted) return;
        Toast.info(context, 'No hay datos que exportar en este rango.');
        return;
      }

      final ruta = await _exportacionService.exportarTabla(
        nombreBase: nombre,
        encabezados: encabezados,
        filas: filas,
      );

      await _exportacionService.abrirCarpeta(ruta);

      if (!mounted) return;
      Toast.exito(context, 'Exportado a ${p.basename(ruta)}');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  /// Nombre de archivo, encabezados y filas según la pestaña activa.
  (String, List<String>, List<List<Object?>>) _datosParaExportar() {
    switch (paginaSeleccionada) {
      case 0:
        return (
          'ventas',
          ['Venta', 'Fecha', 'Cliente', 'Metodo de pago', 'Estado', 'Total', 'Total neto'],
          ventasRecientes
              .map((v) => <Object?>[
                    v['id_venta'],
                    v['fecha'],
                    v['cliente'] ?? '',
                    v['metodo_pago'] ?? '',
                    v['estado'] ?? '',
                    montoCsv(v['total'] as num?),
                    montoCsv(v['total_neto'] as num?),
                  ])
              .toList(),
        );

      case 1:
        return (
          'compras',
          ['Compra', 'Fecha', 'Proveedor', 'Total'],
          comprasRecientes
              .map((c) => <Object?>[
                    c['id_compra'],
                    c['fecha'],
                    c['proveedor'] ?? '',
                    montoCsv(c['total'] as num?),
                  ])
              .toList(),
        );

      case 2:
        return (
          'movimientos_por_usuario',
          ['Fecha', 'Usuario', 'Accion', 'Modulo', 'Descripcion'],
          movimientos
              .map((m) => <Object?>[
                    m.fechaHora,
                    m.usuario,
                    m.accion,
                    m.tabla,
                    m.descripcion,
                  ])
              .toList(),
        );

      case 3:
        final resumen = cuentasPorPagar;
        return (
          'cuentas_por_pagar',
          ['Proveedor', 'Compras', 'Saldo'],
          (resumen?.deudaPorProveedor ?? const [])
              .map((r) => <Object?>[
                    r['proveedor'] ?? 'Sin proveedor',
                    r['compras'],
                    montoCsv(r['saldo'] as num?),
                  ])
              .toList(),
        );

      case 5:
        return (
          'movimientos_inventario',
          [
            'Fecha',
            'Producto',
            'Clave',
            'Tipo',
            'Cantidad',
            'Existencia anterior',
            'Existencia nueva',
            'Motivo',
            'Referencia',
          ],
          movimientosInventario.movimientos
              .map((m) => <Object?>[
                    m['fecha'],
                    m['producto'],
                    m['sku'] ?? '',
                    _etiquetaTipoMovimiento(m['tipo_movimiento']?.toString()),
                    m['cantidad'],
                    m['cantidad_anterior'],
                    m['cantidad_nueva'],
                    m['motivo'] ?? '',
                    m['referencia_tipo'] == null
                        ? ''
                        : '${m['referencia_tipo']} ${m['referencia_id'] ?? ''}'.trim(),
                  ])
              .toList(),
        );

      default:
        final resumen = utilidad;
        return (
          'utilidad',
          ['Producto', 'Unidades', 'Ingresos', 'Costos', 'Utilidad', 'Devoluciones'],
          (resumen?.porProducto ?? const [])
              .map((r) => <Object?>[
                    r['nombre'],
                    (r['unidades'] as num?)?.toStringAsFixed(0) ?? '0',
                    montoCsv(r['ingresos'] as num?),
                    montoCsv(r['costos'] as num?),
                    montoCsv(r['utilidad'] as num?),
                    montoCsv(r['devoluciones'] as num?),
                  ])
              .toList(),
        );
    }
  }

  /// Solo se llama con permiso `verGanancias`: es justo el dato que ese
  /// permiso protege (márgenes y costos).
  Future<void> _cargarUtilidad() async {
    final resumen = await _reporteController.obtenerReporteUtilidad(
      desde: desde,
      hasta: hasta,
      filtrarPorUsuario: false,
    );

    if (!mounted) return;
    setState(() => utilidad = resumen);
  }

  Future<void> _cargarMovimientosInventario() async {
    final resumen = await _reporteController.obtenerMovimientosInventario(
      desde: desde,
      hasta: hasta,
      tipoMovimiento: filtroTipoMovimiento,
    );

    if (!mounted) return;
    setState(() => movimientosInventario = resumen);
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
    filtrarPorUsuario: vistaRestringida,
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
    filtrarPorUsuario: vistaRestringida,
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
    if (!mounted) return;

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
                AppConfig.formatoMoneda((esVentas ? ingresosTotales : gastoTotal)),
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

    return pw.TableHelper.fromTextArray(
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

    return pw.TableHelper.fromTextArray(
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
            AppConfig.formatoMoneda(totalNeto),
          ];
        }

        return [
          '#${item['id_compra']}',
          fecha == null ? '' : _formatDate(fecha),
          item['proveedor']?.toString() ?? 'Sin proveedor',
          AppConfig.formatoMoneda((item['total'] as num?)?.toDouble() ?? 0),
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

  Widget _buildUtilidadTab() {
    final resumen = utilidad;
    if (resumen == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorUtilidad =
        resumen.utilidad >= 0 ? AppColors.success : AppColors.error;

    // Column y no ListView: el encabezado es de altura fija y la única parte
    // que puede crecer sin límite es la lista de productos, que abajo va en su
    // propio ListView.builder dentro de un Expanded.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El aviso va ARRIBA de las cifras, no al pie: si el cálculo no cubre
        // todas las ventas del rango, eso hay que saberlo ANTES de leer el
        // número, no después de haberlo tomado por bueno.
        if (resumen.coberturaParcial) ...[
          _avisoCoberturaParcial(resumen),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            _statCard('Ingresos (neto)', resumen.ingresos, AppColors.info),
            const SizedBox(width: 16),
            _statCard('Costo de lo vendido', resumen.costos, AppColors.warning),
            const SizedBox(width: 16),
            _statCard('Utilidad', resumen.utilidad, colorUtilidad),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorUtilidad.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Margen',
                        style: TextStyle(
                            fontSize: AppText.overline,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '${resumen.margenPorcentaje.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: AppText.subtitle,
                          color: colorUtilidad),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (resumen.devoluciones > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Ya se descontaron ${AppConfig.formatoMoneda(resumen.devoluciones)} '
            'en mercancía devuelta (ingreso y costo).',
            style: const TextStyle(
                fontSize: AppText.small, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 24),
        const Text('Utilidad por producto',
            style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (resumen.porProducto.isEmpty)
          const Text('Sin datos en este rango.',
              style: TextStyle(color: AppColors.textSecondary))
        else
          Expanded(child: _listaUtilidadPorProducto(resumen)),
      ],
    );
  }

  /// Lista de utilidad por producto, virtualizada.
  ///
  /// Va en su propio `ListView.builder` y no como `...lista.map()` dentro de
  /// un Column: el desglose tiene una fila por producto vendido en el rango,
  /// que no tiene techo. Materializar 3.000 filas de golpe en un equipo de
  /// gama baja es justo el problema que documenta el informe de rendimiento.
  Widget _listaUtilidadPorProducto(ReporteUtilidadResumen resumen) {
    return ListView.builder(
      itemCount: resumen.porProducto.length,
      itemBuilder: (_, i) {
        final r = resumen.porProducto[i];
        final ingresos = (r['ingresos'] as num?)?.toDouble() ?? 0;
        final costos = (r['costos'] as num?)?.toDouble() ?? 0;
        final utilidadProducto = (r['utilidad'] as num?)?.toDouble() ?? 0;
        final unidades = (r['unidades'] as num?)?.toDouble() ?? 0;
        final margen = ingresos <= 0 ? 0.0 : (utilidadProducto / ingresos) * 100;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${r['nombre']} — Utilidad ${AppConfig.formatoMoneda(utilidadProducto)} '
            '(${margen.toStringAsFixed(1)}%) · '
            '${unidades.toStringAsFixed(0)} u. · '
            'Ingreso ${AppConfig.formatoMoneda(ingresos)} · '
            'Costo ${AppConfig.formatoMoneda(costos)}',
          ),
        );
      },
    );
  }

  /// Advertencia de que los montos de utilidad NO cubren todas las ventas del
  /// rango, porque hay líneas sin costo registrado (ventas anteriores a la
  /// migración v22, o productos que nunca tuvieron precio de compra).
  ///
  /// Presentar una utilidad parcial como si fuera total es peor que no
  /// mostrarla: el dueño toma decisiones de precio con un número que parece
  /// completo y no lo es.
  Widget _avisoCoberturaParcial(ReporteUtilidadResumen resumen) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cálculo parcial: cubre el ${resumen.coberturaPorcentaje.toStringAsFixed(0)}% '
                  'de las líneas vendidas en el rango.',
                  style: const TextStyle(
                      fontSize: AppText.body, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${resumen.lineasSinCosto} línea(s) no tienen costo registrado y quedan '
                  'fuera de los totales. El costo se guarda en cada venta desde esta '
                  'versión; las ventas anteriores no lo tienen y no es posible '
                  'reconstruirlo. Los productos sin precio de compra tampoco cuentan.',
                  style: const TextStyle(
                      fontSize: AppText.small, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
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
            Text(AppConfig.formatoMoneda(valor), style: TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.subtitle, color: color)),
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

  /// Etiqueta legible de un tipo de movimiento de inventario. Si llegara un
  /// tipo desconocido (una versión más nueva del backend), se muestra tal cual
  /// en vez de ocultarlo.
  String _etiquetaTipoMovimiento(String? tipo) {
    for (final (valor, etiqueta) in _tiposMovimiento) {
      if (valor == tipo) return etiqueta;
    }
    return tipo ?? '-';
  }

  /// `Movimiento_Inventario.fecha` se guarda en UTC; aquí se muestra en la
  /// hora del negocio, que es la única que el usuario reconoce.
  String _fechaMovimiento(Object? valor) {
    final fecha = DateTime.tryParse(valor?.toString() ?? '');
    if (fecha == null) return valor?.toString() ?? '-';
    return formatearFechaHora(fecha.toLocal().toIso8601String());
  }

  /// Movimientos de inventario del rango: qué entró, qué salió y por qué.
  ///
  /// Responde la pregunta que la bitácora de auditoría no responde ("¿dónde
  /// quedaron las 3 piezas que faltan?"), porque sigue la pieza y no la
  /// pantalla: cada fila dice cuánto había antes, cuánto quedó y con qué
  /// motivo se movió.
  Widget _buildMovimientosInventarioTab() {
    final resumen = movimientosInventario;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _tarjetaPiezas(
                'Piezas que entraron',
                resumen.piezasEntrada,
                Icons.south_west,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _tarjetaPiezas(
                'Piezas que salieron',
                resumen.piezasSalida,
                Icons.north_east,
                AppColors.info,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _tarjetaPiezas(
                'Piezas de merma',
                resumen.piezasMerma,
                Icons.delete_outline,
                AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String?>(
                initialValue: filtroTipoMovimiento,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Tipo de movimiento',
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                  for (final (valor, etiqueta) in _tiposMovimiento)
                    DropdownMenuItem<String?>(value: valor, child: Text(etiqueta)),
                ],
                onChanged: (v) {
                  setState(() => filtroTipoMovimiento = v);
                  _cargarMovimientosInventario();
                },
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Del $rangoTexto',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _headerMovimientosInventario(),
        const SizedBox(height: 8),
        Expanded(
          child: resumen.movimientos.isEmpty
              ? _emptyState('No hay movimientos de inventario en este rango.')
              : ListView.builder(
                  itemCount: resumen.movimientos.length,
                  itemBuilder: (_, i) => _filaMovimientoInventario(resumen.movimientos[i]),
                ),
        ),
      ],
    );
  }

  Widget _tarjetaPiezas(String titulo, int piezas, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppText.overline,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$piezas',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: AppText.subtitle,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerMovimientosInventario() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        children: [
          Expanded(flex: 16, child: Text("FECHA", style: auditoriaHeaderStyle)),
          Expanded(flex: 22, child: Text("PRODUCTO", style: auditoriaHeaderStyle)),
          Expanded(flex: 18, child: Text("TIPO", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("PIEZAS", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("EXISTENCIA", style: auditoriaHeaderStyle)),
          Expanded(flex: 20, child: Text("MOTIVO", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaMovimientoInventario(Map<String, dynamic> m) {
    const tiposEntrada = {
      'EntradaCompra',
      'AjustePositivo',
      'TransferenciaEntrada',
      'DevolucionVenta',
    };
    final esEntrada = tiposEntrada.contains(m['tipo_movimiento']);
    final color = esEntrada ? AppColors.success : AppColors.info;

    final referencia = m['referencia_tipo'] == null
        ? null
        : '${m['referencia_tipo']} ${m['referencia_id'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Expanded(flex: 16, child: Text(_fechaMovimiento(m['fecha']))),
          Expanded(
            flex: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m['producto']?.toString() ?? '-',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (m['sku'] != null)
                  Text(
                    m['sku'].toString(),
                    style: const TextStyle(
                      fontSize: AppText.overline,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(
              _etiquetaTipoMovimiento(m['tipo_movimiento']?.toString()),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              '${esEntrada ? '+' : '-'}${m['cantidad']}',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          Expanded(
            flex: 14,
            child: Text('${m['cantidad_anterior']} → ${m['cantidad_nueva']}'),
          ),
          Expanded(
            flex: 20,
            child: Text(
              [
                if (m['motivo'] != null) m['motivo'].toString(),
                if (referencia != null && referencia.isNotEmpty) referencia,
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
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
                  // `.builder` con el encabezado como fila 0: el `...map()`
                  // anterior construía una fila por movimiento de golpe, y
                  // `movimientos` sale de la bitácora, que no tiene techo.
                  : ListView.builder(
                      itemCount: movimientos.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _tablaMovimientosHeader(),
                              const SizedBox(height: 8),
                            ],
                          );
                        }
                        return _filaMovimiento(movimientos[i - 1]);
                      },
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
              (a) => DropdownMenuItem(value: a, child: Text(etiquetaAccionAuditoria(a))),
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
              (t) => DropdownMenuItem(value: t, child: Text(etiquetaModuloAuditoria(t))),
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
          Expanded(flex: 14, child: Text("ACCIÓN", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("MÓDULO", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("FOLIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 8, child: Text("CAJA", style: auditoriaHeaderStyle)),
          Expanded(flex: 18, child: Text("DESCRIPCIÓN", style: auditoriaHeaderStyle)),
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
            flex: 14,
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
                    Flexible(
                      child: Text(
                        etiquetaAccionAuditoria(m.accion),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.overline,
                          fontWeight: FontWeight.w800,
                          color: colorPorAccionAuditoria(m.accion),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(flex: 12, child: Text(etiquetaModuloAuditoria(m.tabla))),
          Expanded(flex: 10, child: Text(m.idRegistro?.toString() ?? '-')),
          Expanded(flex: 8, child: Text(m.idCaja?.toString() ?? '-')),
          Expanded(
            flex: 18,
            child: Text(m.descripcion, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarMovimientosPDF() async {
    if (movimientos.isEmpty) {
      Toast.info(context, 'No hay movimientos para exportar.');
      return;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, text: 'Movimientos por usuario'),
          pw.Paragraph(text: 'Generado el ${formatearFechaHora(DateTime.now().toIso8601String())}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Fecha y hora',
              'Usuario',
              'Acción',
              'Módulo',
              'Folio',
              'Caja',
              'Descripción',
            ],
            data: movimientos.map((m) {
              return [
                formatearFechaHora(m.fechaHora),
                m.usuario,
                etiquetaAccionAuditoria(m.accion),
                etiquetaModuloAuditoria(m.tabla),
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
                    else if (paginaSeleccionada == 4)
                      Expanded(child: _buildUtilidadTab())
                    else if (paginaSeleccionada == 5)
                      Expanded(child: _buildMovimientosInventarioTab())
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
    final mostrarFiltrosFecha = !vistaRestringida && paginaSeleccionada != 2 && paginaSeleccionada != 3;

    // El PDF de "Imprimir reporte" está armado para ventas y compras (resumen,
    // top de productos y listado). En las demás pestañas imprimía ese mismo
    // formato con datos de compras bajo un título ajeno, así que ahí no se
    // ofrece: para llevarse esos datos está Exportar CSV.
    final mostrarImprimir = paginaSeleccionada == 0 || paginaSeleccionada == 1;

    // Wrap (no Row): las etiquetas largas ("Movimientos por usuario", "Cuentas
    // por pagar") más los filtros de fecha no caben en una sola línea en
    // ventanas angostas. Con Row + Spacer eso desbordaba; el Wrap acomoda los
    // controles en varias líneas según el ancho, sin desbordar nunca.
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildTabButton(
          label: 'Ventas',
          icon: Icons.point_of_sale,
          selected: paginaSeleccionada == 0,
          onTap: () => setState(() => paginaSeleccionada = 0),
        ),
        _buildTabButton(
          label: 'Compras',
          icon: Icons.shopping_bag_outlined,
          selected: paginaSeleccionada == 1,
          onTap: () => setState(() => paginaSeleccionada = 1),
        ),
        if (!vistaRestringida) ...[
          _buildTabButton(
            label: 'Movimientos por usuario',
            icon: Icons.manage_accounts_outlined,
            selected: paginaSeleccionada == 2,
            onTap: () => setState(() => paginaSeleccionada = 2),
          ),
          _buildTabButton(
            label: 'Cuentas por pagar',
            icon: Icons.account_balance_wallet_outlined,
            selected: paginaSeleccionada == 3,
            onTap: () => setState(() => paginaSeleccionada = 3),
          ),
          _buildTabButton(
            label: 'Utilidad',
            icon: Icons.trending_up,
            selected: paginaSeleccionada == 4,
            onTap: () => setState(() => paginaSeleccionada = 4),
          ),
          _buildTabButton(
            label: 'Movimientos de inventario',
            icon: Icons.swap_vert,
            selected: paginaSeleccionada == 5,
            onTap: () => setState(() => paginaSeleccionada = 5),
          ),
        ],
        if (mostrarFiltrosFecha) ...[
          _buildRangeButton('7 días', () => _seleccionarRango(7)),
          _buildRangeButton('30 días', () => _seleccionarRango(30)),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
          if (mostrarImprimir)
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
        // Exportar está fuera de `mostrarFiltrosFecha` porque también aplica a
        // las pestañas sin rango de fechas (movimientos, cuentas por pagar).
        if (!vistaRestringida)
          OutlinedButton.icon(
            onPressed: _exportando ? null : _exportarReporte,
            icon: _exportando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_outlined, size: 18),
            label: Text(_exportando ? 'Exportando...' : 'Exportar CSV'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              AppConfig.formatoMoneda((esVentas ? ingresosTotales : gastoTotal)),
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
    return AppConfig.formatoMoneda((total / cantidad));
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
                color: Colors.white.withValues(alpha: 0.7),
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

  /// Panel de "más vendidos". Con [_ordenPorUtilidad] activo la lista deja de
  /// ordenarse por unidades y pasa a la utilidad de cada producto: el producto
  /// que más piezas mueve no es necesariamente el que más deja, y ordenar solo
  /// por volumen esconde justo eso (el refresco que vuela con 2 pesos de
  /// margen contra el artículo que se vende poco y deja 200).
  Widget _buildProductosPanel() {
    final esVentas = paginaSeleccionada == 0;
    final resumenUtilidad = utilidad;

    // El orden por utilidad necesita costos, que es justo lo que protege el
    // permiso `verGanancias`; sin él ni siquiera se ofrece el botón.
    final puedeOrdenarPorUtilidad =
        esVentas && !vistaRestringida && resumenUtilidad != null;
    final porUtilidad = puedeOrdenarPorUtilidad && _ordenPorUtilidad;

    final productos = !esVentas
        ? productosComprados
        : (porUtilidad ? resumenUtilidad.porProducto : productosVendidos);

    return _sectionPanel(
      title: esVentas ? 'Productos mas vendidos' : 'Productos mas comprados',
      icon: Icons.inventory_2_outlined,
      trailing: puedeOrdenarPorUtilidad
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _chipOrden('Unidades', !porUtilidad, () {
                  setState(() => _ordenPorUtilidad = false);
                }),
                const SizedBox(width: 6),
                _chipOrden('Utilidad', porUtilidad, () {
                  setState(() => _ordenPorUtilidad = true);
                }),
              ],
            )
          : null,
      child: productos.isEmpty
          ? _emptyState(
              esVentas
                  ? 'No hay productos vendidos en este rango.'
                  : 'No hay productos comprados en este rango.',
            )
          : ListView.separated(
              itemCount: productos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                        porUtilidad
                            ? AppConfig.formatoMoneda(
                                (item['utilidad'] as num?)?.toDouble() ?? 0)
                            : '${item['total']} uds',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: porUtilidad &&
                                  ((item['utilidad'] as num?)?.toDouble() ?? 0) < 0
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Píldora de selección de orden dentro del encabezado de un panel.
  Widget _chipOrden(String label, bool seleccionado, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: seleccionado ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: seleccionado ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppText.caption,
            fontWeight: FontWeight.w700,
            color: seleccionado ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
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
              separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    Widget? trailing,
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
              ?trailing,
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
            AppConfig.formatoMoneda(total),
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
