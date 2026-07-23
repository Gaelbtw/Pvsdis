import 'package:flutter/material.dart';

import '../controllers/cuentas_por_pagar_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../models/proveedores_model.dart';
import '../widgets/nav_bar.dart';
import 'cuentas_por_pagar_view.dart';

/// Ficha del proveedor: total comprado, total pagado, saldo pendiente,
/// compras vencidas e historial de pagos. Llega desde el ícono "Ver cuenta"
/// en `proveedores_view.dart`.
class ProveedorDetalleView extends StatefulWidget {
  final Proveedores proveedor;

  const ProveedorDetalleView({super.key, required this.proveedor});

  @override
  State<ProveedorDetalleView> createState() => _ProveedorDetalleViewState();
}

class _ProveedorDetalleViewState extends State<ProveedorDetalleView> {
  final _controller = CuentasPorPagarController();

  bool cargando = true;
  Map<String, dynamic> resumen = {};
  List<Map<String, dynamic>> historialReciente = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final idProveedor = widget.proveedor.idProveedor!;
    final resultados = await Future.wait([
      _controller.resumenProveedor(idProveedor),
      _controller.obtenerCuentas(idProveedor: idProveedor),
    ]);

    if (!mounted) return;
    setState(() {
      resumen = resultados[0] as Map<String, dynamic>;
      historialReciente = resultados[1] as List<Map<String, dynamic>>;
      cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: widget.proveedor.nombre, mostrarVolver: true),
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
                    Text(
                      widget.proveedor.nombre,
                      style: const TextStyle(fontSize: AppText.heading, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    if (widget.proveedor.telefono.isNotEmpty)
                      Text(
                        widget.proveedor.telefono,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _stat('Total comprado', resumen['total_comprado'], AppColors.primaryLighter),
                        const SizedBox(width: 16),
                        _stat('Total pagado', resumen['total_pagado'], AppColors.success),
                        const SizedBox(width: 16),
                        _stat('Saldo pendiente', resumen['saldo_pendiente'], AppColors.error),
                        const SizedBox(width: 16),
                        _statEntero('Compras vencidas', resumen['compras_vencidas'], AppColors.warning),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text(
                          'Historial de compras y pagos',
                          style: TextStyle(fontSize: AppText.bodyLg, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CuentasPorPagarView(
                                  idProveedorInicial: widget.proveedor.idProveedor,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Ver todas las cuentas'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: historialReciente.isEmpty
                          ? const Center(
                              child: Text(
                                'Este proveedor todavía no tiene compras registradas.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              itemCount: historialReciente.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _filaCompra(historialReciente[i]),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _stat(String label, dynamic valor, Color color) {
    final numero = (valor as num?)?.toDouble() ?? 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(AppConfig.formatoMoneda(numero), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.subtitle)),
          ],
        ),
      ),
    );
  }

  Widget _statEntero(String label, dynamic valor, Color color) {
    final numero = (valor as num?)?.toInt() ?? 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: AppText.overline, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text('$numero', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: AppText.subtitle)),
          ],
        ),
      ),
    );
  }

  Widget _filaCompra(Map<String, dynamic> cuenta) {
    final total = (cuenta['total'] as num).toDouble();
    final saldo = (cuenta['saldo'] as num).toDouble();
    final estado = cuenta['estado'] as String;
    final vencida = (cuenta['vencida'] as int) == 1;
    final fecha = DateTime.tryParse(cuenta['fecha']?.toString() ?? '');

    final color = vencida
        ? AppColors.error
        : estado == 'Pagada'
            ? AppColors.success
            : estado == 'Parcial'
                ? AppColors.warning
                : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Compra #${cuenta['id_compra']}'
              '${fecha == null ? '' : '  ·  ${fecha.day}/${fecha.month}/${fecha.year}'}',
            ),
          ),
          Text(AppConfig.formatoMoneda(total), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(
              vencida ? 'Vencida' : estado,
              style: TextStyle(color: color, fontSize: AppText.overline, fontWeight: FontWeight.w800),
            ),
          ),
          if (saldo > 0) ...[
            const SizedBox(width: 8),
            Text('Saldo: ${AppConfig.formatoMoneda(saldo)}', style: const TextStyle(color: AppColors.error, fontSize: AppText.caption)),
          ],
        ],
      ),
    );
  }
}
