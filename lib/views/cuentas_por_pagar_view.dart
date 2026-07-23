import 'package:flutter/material.dart';

import '../controllers/cuentas_por_pagar_controller.dart';
import '../controllers/proveedor_controller.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../core/utils/pagos_mixtos.dart';
import '../models/proveedores_model.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';

/// Pantalla de cuentas por pagar a proveedores: resumen de deuda total,
/// lista de cuentas pendientes con filtros, registrar abonos y ver el
/// historial de pagos de cada compra. Solo Administrador (ver
/// `configuracion_view.dart`, que es el único lugar que enlaza aquí).
class CuentasPorPagarView extends StatefulWidget {
  /// Si se pasa, la lista arranca filtrada a este proveedor (llegando desde
  /// `ProveedorDetalleView`).
  final int? idProveedorInicial;

  const CuentasPorPagarView({super.key, this.idProveedorInicial});

  @override
  State<CuentasPorPagarView> createState() => _CuentasPorPagarViewState();
}

class _CuentasPorPagarViewState extends State<CuentasPorPagarView> {
  final _controller = CuentasPorPagarController();
  final _proveedorController = ProveedorController();

  bool cargando = true;
  double deudaTotal = 0;
  List<Map<String, dynamic>> cuentas = [];
  List<Proveedores> proveedores = [];

  int? filtroProveedorId;
  String filtroEstado = 'Todas';
  DateTime? filtroDesde;
  DateTime? filtroHasta;
  bool soloVencidas = false;

  static const _estados = ['Todas', 'Pendiente', 'Parcial', 'Pagada'];

  @override
  void initState() {
    super.initState();
    filtroProveedorId = widget.idProveedorInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);

    final resultados = await Future.wait([
      _proveedorController.obtenerTodos(),
      _controller.deudaTotal(),
      _controller.obtenerCuentas(
        idProveedor: filtroProveedorId,
        estado: filtroEstado == 'Todas' ? null : filtroEstado,
        desde: filtroDesde,
        hasta: filtroHasta,
        soloVencidas: soloVencidas,
      ),
    ]);

    if (!mounted) return;
    setState(() {
      proveedores = resultados[0] as List<Proveedores>;
      deudaTotal = resultados[1] as double;
      cuentas = resultados[2] as List<Map<String, dynamic>>;
      cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SessionManager.isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const CustomHeader(titulo: "Cuentas por pagar", mostrarVolver: true),
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
      appBar: const CustomHeader(titulo: "Cuentas por pagar", mostrarVolver: true),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _resumenDeuda(),
                    const SizedBox(height: 20),
                    _filtros(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: cuentas.isEmpty
                          ? _emptyState()
                          : ListView.separated(
                              itemCount: cuentas.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _filaCuenta(cuentas[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _resumenDeuda() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryLighter,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Deuda total con proveedores",
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                "${AppConfig.formatoMoneda(deudaTotal)}",
                style: const TextStyle(fontSize: AppText.display, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown<int?>(
          label: 'Proveedor',
          value: filtroProveedorId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            ...proveedores.map((p) => DropdownMenuItem(value: p.idProveedor, child: Text(p.nombre))),
          ],
          onChanged: (v) {
            setState(() => filtroProveedorId = v);
            _cargar();
          },
        ),
        _dropdown<String>(
          label: 'Estado',
          value: filtroEstado,
          items: _estados.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {
            setState(() => filtroEstado = v!);
            _cargar();
          },
        ),
        OutlinedButton.icon(
          onPressed: _seleccionarFechas,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(
            filtroDesde == null || filtroHasta == null
                ? 'Rango de fechas'
                : '${_formatDate(filtroDesde!)} - ${_formatDate(filtroHasta!)}',
          ),
        ),
        if (filtroDesde != null)
          TextButton(
            onPressed: () {
              setState(() {
                filtroDesde = null;
                filtroHasta = null;
              });
              _cargar();
            },
            child: const Text('Limpiar fechas'),
          ),
        FilterChip(
          label: const Text('Solo vencidas'),
          selected: soloVencidas,
          onSelected: (v) {
            setState(() => soloVencidas = v);
            _cargar();
          },
        ),
      ],
    );
  }

  Widget _dropdown<T>({
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

  Future<void> _seleccionarFechas() async {
    final desde = await showDatePicker(
      context: context,
      initialDate: filtroDesde ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (desde == null || !mounted) return;

    final hasta = await showDatePicker(
      context: context,
      initialDate: filtroHasta ?? DateTime.now(),
      firstDate: desde,
      lastDate: DateTime.now(),
    );
    if (hasta == null) return;

    setState(() {
      filtroDesde = desde;
      filtroHasta = DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59);
    });
    await _cargar();
  }

  Color _colorEstado(String estado, bool vencida) {
    if (vencida) return AppColors.error;
    switch (estado) {
      case 'Pagada':
        return AppColors.success;
      case 'Parcial':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _filaCuenta(Map<String, dynamic> cuenta) {
    final idCompra = cuenta['id_compra'] as int;
    final total = (cuenta['total'] as num).toDouble();
    final pagado = (cuenta['pagado'] as num).toDouble();
    final saldo = (cuenta['saldo'] as num).toDouble();
    final estado = cuenta['estado'] as String;
    final vencida = (cuenta['vencida'] as int) == 1;
    final proveedor = cuenta['proveedor']?.toString() ?? 'Sin proveedor';
    final fecha = DateTime.tryParse(cuenta['fecha']?.toString() ?? '');
    final fechaVencimiento = DateTime.tryParse(cuenta['fecha_vencimiento']?.toString() ?? '');
    final folio = cuenta['folio_factura']?.toString();
    final estadoTexto = vencida ? 'Vencida' : estado;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$proveedor  ·  Compra #$idCompra',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppText.body),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${fecha == null ? '' : _formatDate(fecha)}'
                      '${fechaVencimiento == null ? '' : '  ·  Vence: ${_formatDate(fechaVencimiento)}'}'
                      '${folio == null || folio.isEmpty ? '' : '  ·  Folio: $folio'}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.caption),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _colorEstado(estado, vencida).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  estadoTexto,
                  style: TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w800,
                    color: _colorEstado(estado, vencida),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _dato('Total', total),
              _dato('Pagado', pagado),
              _dato('Saldo', saldo, destacar: true),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _mostrarHistorial(idCompra, proveedor),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Historial'),
              ),
              if (saldo > 0)
                ElevatedButton.icon(
                  onPressed: () => _mostrarDialogoAbono(idCompra, proveedor, saldo),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Registrar abono'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dato(String label, double valor, {bool destacar = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
          Text(
            '${AppConfig.formatoMoneda(valor)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: destacar ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: AppColors.success),
          const SizedBox(height: 12),
          const Text(
            'No hay cuentas con estos filtros.',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _mostrarHistorial(int idCompra, String proveedor) async {
    final historial = await _controller.obtenerHistorialPagos(idCompra);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Historial de pagos · $proveedor'),
        content: SizedBox(
          width: 420,
          child: historial.isEmpty
              ? const Text('Todavía no hay abonos registrados para esta compra.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: historial.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final abono = historial[i];
                    final fecha = DateTime.tryParse(abono['fecha']?.toString() ?? '');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${AppConfig.formatoMoneda((abono['monto'] as num))}'
                          '  ·  ${abono['metodos'] ?? ''}'),
                      subtitle: Text(
                        '${fecha == null ? '' : _formatDate(fecha)}'
                        '${abono['usuario'] == null ? '' : '  ·  ${abono['usuario']}'}'
                        '${abono['referencia'] == null ? '' : '  ·  Ref: ${abono['referencia']}'}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoAbono(int idCompra, String proveedor, double saldoPendiente) async {
    final montoCtrl = TextEditingController(text: saldoPendiente.toStringAsFixed(2));
    final referenciaCtrl = TextEditingController();
    final observacionesCtrl = TextEditingController();
    String metodoPago = metodosPagoDisponibles.first;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => FormDialog(
          titulo: 'Registrar abono',
          subtitulo: '$proveedor · Saldo pendiente: ${AppConfig.formatoMoneda(saldoPendiente)}',
          campos: [
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto del abono'),
            ),
            DropdownButtonFormField<String>(
              initialValue: metodoPago,
              decoration: const InputDecoration(labelText: 'Método de pago'),
              items: metodosPagoDisponibles
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setDialogState(() => metodoPago = v!),
            ),
            TextField(
              controller: referenciaCtrl,
              decoration: const InputDecoration(labelText: 'Referencia / folio (opcional)'),
            ),
            TextField(
              controller: observacionesCtrl,
              decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
            ),
          ],
          onGuardar: () async {
            final monto = double.tryParse(montoCtrl.text.trim());
            if (monto == null || monto <= 0) {
              showDialog(
                context: dialogContext,
                builder: (_) => const CustomAlert(
                  titulo: 'Monto inválido',
                  mensaje: 'Ingresa un monto válido mayor a cero.',
                  icono: Icons.warning_amber_rounded,
                  textoConfirmar: 'Aceptar',
                ),
              );
              return;
            }

            try {
              await _controller.registrarAbono(
                idCompra: idCompra,
                monto: monto,
                pagos: [
                  {'metodo_pago': metodoPago, 'monto': monto}
                ],
                referencia: referenciaCtrl.text,
                observaciones: observacionesCtrl.text,
              );

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);

              if (!mounted) return;
              await _cargar();

              if (!mounted) return;
              showDialog(
                context: context,
                builder: (_) => const CustomAlert(
                  titulo: 'Abono registrado',
                  mensaje: 'El pago se registró correctamente.',
                  icono: Icons.check_circle_outline,
                  textoConfirmar: 'Aceptar',
                ),
              );
            } catch (e) {
              showDialog(
                context: dialogContext,
                builder: (_) => CustomAlert(
                  titulo: 'No se pudo registrar el abono',
                  mensaje: e.toString().replaceFirst('Exception: ', ''),
                  icono: Icons.error_outline,
                  textoConfirmar: 'Aceptar',
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
