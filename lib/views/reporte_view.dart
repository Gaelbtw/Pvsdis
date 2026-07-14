import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/custom_alert.dart';
import '../core/session/session_manager.dart';
import '../core/database/database_helper.dart';
import '../services/ticket_compras_service.dart';
import '../services/ticket_service.dart';
import '../widgets/nav_bar.dart';

class ReporteView extends StatefulWidget {
  const ReporteView({super.key});

  @override
  State<ReporteView> createState() => _ReporteViewState();
}

class _ReporteViewState extends State<ReporteView> {
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

  bool get esCajero =>
      SessionManager.currentUserRole == "Cajero";
  int? get usuarioId =>
      SessionManager.currentUserId;

  String get rangoTexto => '${_formatDate(desde)} - ${_formatDate(hasta)}';

  String get tituloReporte =>
      paginaSeleccionada == 0 ? 'Reporte de Ventas' : 'Reporte de Compras';

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() => cargando = true);

    try {
      await _cargarReportesVentas();
      await _cargarReportesCompras();
    } finally {
      if (mounted) {
        setState(() => cargando = false);
      }
    }
  }

Future<void> _cargarReportesVentas() async {
  final db = await DatabaseHelper().database;

  final fechaInicio =
      desde.toIso8601String().substring(0, 10);

  final fechaFin =
      hasta.toIso8601String().substring(0, 10);

  final filtroUsuario =
      esCajero ? 'AND id_usuario = ?' : '';

  final params = esCajero
      ? [fechaInicio, fechaFin, usuarioId]
      : [fechaInicio, fechaFin];

  // RESUMEN
  final summary = await db.rawQuery(
    '''
    SELECT
      COUNT(*) as ventas,
      IFNULL(SUM(total), 0) as ingresos
    FROM Ventas
    WHERE date(fecha) BETWEEN date(?) AND date(?)
    $filtroUsuario
    ''',
    params,
  );

  // PRODUCTOS
  final productos = await db.rawQuery(
    '''
    SELECT
      Producto.nombre,
      SUM(Detalle_Venta.cantidad) as total

    FROM Detalle_Venta

    INNER JOIN Ventas
      ON Ventas.id_venta = Detalle_Venta.id_venta

    INNER JOIN Producto
      ON Producto.id_producto = Detalle_Venta.id_producto

    WHERE date(Ventas.fecha)
      BETWEEN date(?) AND date(?)

    ${esCajero ? 'AND Ventas.id_usuario = ?' : ''}

    GROUP BY Producto.nombre
    ORDER BY total DESC
    LIMIT 10
    ''',
    params,
  );

  // VENTAS
  final ventas = await db.rawQuery(
    '''
    SELECT
      Ventas.id_venta,
      Ventas.fecha,
      Ventas.total,
      Ventas.metodo_pago,
      Clientes.nombre as cliente

    FROM Ventas

    LEFT JOIN Clientes
      ON Clientes.id_cliente = Ventas.id_cliente

    WHERE date(fecha)
      BETWEEN date(?) AND date(?)

    $filtroUsuario

    ORDER BY fecha DESC
    LIMIT 20
    ''',
    params,
  );

  if (!mounted) return;

  setState(() {
    totalVentas =
        summary.first['ventas'] as int? ?? 0;

    ingresosTotales =
        (summary.first['ingresos'] as num?)
            ?.toDouble() ??
        0;

    productosVendidos = productos;

    ventasRecientes = ventas;
  });
}

  Future<void> _cargarReportesCompras() async {
  final db = await DatabaseHelper().database;
  final fechaInicio = desde.toIso8601String().substring(0, 10);
  final fechaFin = hasta.toIso8601String().substring(0, 10);

  final summary = await db.rawQuery(
    '''
    SELECT
      COUNT(*) as compras,
      IFNULL(SUM(total), 0) as gasto
    FROM Compras
    WHERE date(fecha) BETWEEN date(?) AND date(?)
    ${esCajero ? 'AND id_usuario = ?' : ''}
    ''',
    esCajero
        ? [fechaInicio, fechaFin, SessionManager.currentUserId]
        : [fechaInicio, fechaFin],
  );

  final productos = await db.rawQuery(
    '''
    SELECT
      Producto.nombre,
      SUM(IFNULL(Detalle_Compra.cantidad, 1)) as total
    FROM Detalle_Compra
    INNER JOIN Compras ON Compras.id_compra = Detalle_Compra.id_compra
    INNER JOIN Producto ON Producto.id_producto = Detalle_Compra.id_producto
    WHERE date(Compras.fecha) BETWEEN date(?) AND date(?)
    ${esCajero ? 'AND Compras.id_usuario = ?' : ''}
    GROUP BY Producto.nombre
    ORDER BY total DESC
    LIMIT 10
    ''',
    esCajero
        ? [fechaInicio, fechaFin, SessionManager.currentUserId]
        : [fechaInicio, fechaFin],
  );

  final compras = await db.rawQuery(
    '''
    SELECT
      Compras.id_compra,
      Compras.fecha,
      Compras.total,
      Proveedores.nombre as proveedor
    FROM Compras
    LEFT JOIN Proveedores 
      ON Proveedores.id_proveedor = Compras.id_proveedor
    WHERE date(Compras.fecha) BETWEEN date(?) AND date(?)
    ${esCajero ? 'AND Compras.id_usuario = ?' : ''}
    ORDER BY Compras.fecha DESC
    LIMIT 20
    ''',
    esCajero
        ? [fechaInicio, fechaFin, SessionManager.currentUserId]
        : [fechaInicio, fechaFin],
  );

  if (!mounted) return;

  setState(() {
    totalCompras = summary.first['compras'] as int? ?? 0;
    gastoTotal = (summary.first['gasto'] as num?)?.toDouble() ?? 0;
    productosComprados = productos;
    comprasRecientes = compras;
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
                    'La Lomita',
                    style: pw.TextStyle(
                      fontSize: 24,
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
                  borderRadius: pw.BorderRadius.circular(8),
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
                '\$${(esVentas ? ingresosTotales : gastoTotal).toStringAsFixed(2)}',
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            esVentas ? 'Productos mas vendidos' : 'Productos mas comprados',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          _pdfProductos(productos),
          pw.SizedBox(height: 24),
          pw.Text(
            esVentas ? 'Ventas registradas' : 'Compras registradas',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
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
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
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
          ? const ['Folio', 'Fecha', 'Cliente', 'Pago', 'Total']
          : const ['Folio', 'Fecha', 'Proveedor', 'Total'],
      data: movimientos.map((item) {
        final fecha = DateTime.tryParse(item['fecha']?.toString() ?? '');
        if (esVentas) {
          return [
            '#${item['id_venta']}',
            fecha == null ? '' : _formatDate(fecha),
            item['cliente']?.toString() ?? 'Final',
            item['metodo_pago']?.toString() ?? 'efectivo',
            '\$${((item['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
          ];
        }

        return [
          '#${item['id_compra']}',
          fecha == null ? '' : _formatDate(fecha),
          item['proveedor']?.toString() ?? 'Sin proveedor',
          '\$${((item['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
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
  final db = await DatabaseHelper().database;

  final detalles = await db.rawQuery(
    '''
    SELECT Producto.nombre, Detalle_Venta.cantidad, Detalle_Venta.precio
    FROM Detalle_Venta
    INNER JOIN Producto ON Producto.id_producto = Detalle_Venta.id_producto
    WHERE Detalle_Venta.id_venta = ?
    ''',
    [idVenta],
  );

  final carrito = detalles.map((item) {
    return {
      'id_producto': null,
      'nombre': item['nombre'],
      'precio': item['precio'],
      'cantidad': item['cantidad'],
    };
  }).toList();

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: 'Ticket de venta #$idVenta',
      mensaje:
          'Cliente: ${cliente.isNotEmpty ? cliente : 'Consumidor final'}\n\n'
          'Fecha: ${_formatDate(DateTime.parse(fecha))}\n'
          'Método: $metodoPago\n\n'
          'Total: \$${total.toStringAsFixed(2)}\n\n'
          '¿Deseas imprimir el ticket?',
      icono: Icons.receipt_long,
      textoCancelar: 'Cerrar',
      textoConfirmar: 'Imprimir',

      onConfirm: () async {
        final pdf = await TicketService.generarTicket(
          carrito: carrito,
          total: total,
          metodoPago: metodoPago,
          recibido: total,
          cambio: 0,
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
  final db = await DatabaseHelper().database;

  final detalles = await db.rawQuery(
    '''
    SELECT Producto.nombre, Detalle_Compra.cantidad, Detalle_Compra.precio
    FROM Detalle_Compra
    INNER JOIN Producto ON Producto.id_producto = Detalle_Compra.id_producto
    WHERE Detalle_Compra.id_compra = ?
    ''',
    [idCompra],
  );

  final carrito = detalles.map((item) {
    return {
      'nombre': item['nombre'],
      'cantidad': item['cantidad'] ?? 1,
      'precio_compra': item['precio'],
    };
  }).toList();

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
          'Total: \$${total.toStringAsFixed(2)}\n\n'
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: CustomHeader(titulo: tituloReporte, mostrarVolver: true),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildToolbar(),
                    const SizedBox(height: 20),
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
        const SizedBox(width: 18),
        if (!esCajero)
        _buildRangeButton('7 dias', () => _seleccionarRango(7)),
        const SizedBox(width: 8),
        if (!esCajero)
        _buildRangeButton('30 dias', () => _seleccionarRango(30)),
        const SizedBox(width: 8),
        if (!esCajero)
        OutlinedButton.icon(
          onPressed: _seleccionarFechasPersonalizadas,
          icon: const Icon(Icons.date_range, size: 18),
          label: const Text('Rango'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const Spacer(),
        if (!esCajero)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F6F2),
            borderRadius: BorderRadius.circular(14),
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
        if (!esCajero)
        ElevatedButton.icon(
          onPressed: _imprimirReporte,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('Imprimir reporte'),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFFF2C500),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF2C500) : const Color(0xFFF8F6F2),
          borderRadius: BorderRadius.circular(14),
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
        backgroundColor: const Color(0xFFF8F6F2),
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          color: const Color(0xFFFFF3C4),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: esVentas ? Icons.payments_outlined : Icons.account_balance_wallet,
          label: esVentas ? 'Ingresos totales' : 'Gasto total',
          value:
              '\$${(esVentas ? ingresosTotales : gastoTotal).toStringAsFixed(2)}',
          color: const Color(0xFFE8F0D5),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: Icons.trending_up,
          label: esVentas ? 'Ticket promedio' : 'Compra promedio',
          value: _promedioTexto(esVentas),
          color: const Color(0xFFF3E1C7),
        ),
      ],
    );
  }

  String _promedioTexto(bool esVentas) {
    final cantidad = esVentas ? totalVentas : totalCompras;
    final total = esVentas ? ingresosTotales : gastoTotal;

    if (cantidad == 0) return '\$0.00';
    return '\$${(total / cantidad).toStringAsFixed(2)}';
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
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
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
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
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
                    color: const Color(0xFFF9FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3C4),
                          borderRadius: BorderRadius.circular(10),
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
        color: const Color(0xFFF8F6F2),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3C4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
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
    final cliente = venta['cliente']?.toString() ?? 'Consumidor final';
    final metodoPago = venta['metodo_pago']?.toString() ?? 'efectivo';

    return _movementTile(
      icon: Icons.point_of_sale,
      title: 'Venta #${venta['id_venta']}',
      subtitle:
          '${fecha == null ? 'Sin fecha' : _formatDate(fecha)}  |  $cliente  |  $metodoPago',
      total: total,
      onReceipt: () => _mostrarRecibo(
        venta['id_venta'] as int,
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
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3C4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '\$${total.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(width: 8),
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
          Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
