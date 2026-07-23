import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import '../controllers/apartados_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../core/utils/pagos_mixtos.dart';
import '../services/ticket_apartado_service.dart';
import '../widgets/confirm_action.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';
import '../widgets/ventas/pagos_mixtos_section.dart';

/// Detalle de un apartado: productos, saldo pendiente, historial de abonos
/// y las acciones de Registrar abono / Liquidar / Cancelar.
class ApartadoDetalleView extends StatefulWidget {
  final int idApartado;

  const ApartadoDetalleView({super.key, required this.idApartado});

  @override
  State<ApartadoDetalleView> createState() => _ApartadoDetalleViewState();
}

class _ApartadoDetalleViewState extends State<ApartadoDetalleView> {
  final _controller = ApartadosController();

  Map<String, dynamic>? _detalle;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final detalle = await _controller.obtenerDetalle(widget.idApartado);
    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _cargando = false;
    });
  }

  double get _saldoPendiente => (_detalle!['saldo_pendiente'] as num).toDouble();

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'Pendiente':
        return AppColors.info;
      case 'Liquidado':
        return AppColors.success;
      case 'Cancelado':
        return AppColors.error;
      case 'Vencido':
        return AppColors.warning;
      default:
        return AppColors.disabled;
    }
  }

  Future<void> _mostrarDialogoPago({required bool liquidarCompleto}) async {
    var monto = liquidarCompleto ? _saldoPendiente : 0.0;
    var pagos = <Map<String, dynamic>>[];
    var resultado = validarPagosMixtos(total: 0, pagos: const []);
    final montoCtrl = TextEditingController(text: liquidarCompleto ? monto.toStringAsFixed(2) : '');

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      liquidarCompleto ? 'Liquidar apartado' : 'Registrar abono',
                      style: const TextStyle(fontSize: AppText.title, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (!liquidarCompleto)
                      TextField(
                        controller: montoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'Monto del abono (saldo: ${AppConfig.formatoMoneda(_saldoPendiente)})',
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setStateDialog(() {
                          final ingresado = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                          monto = math.max(0.0, math.min(ingresado, _saldoPendiente));
                        }),
                      ),
                    const SizedBox(height: 16),
                    if (monto > 0)
                      PagosMixtosSection(
                        key: ValueKey(monto),
                        total: monto,
                        onCambio: (p, r) => setStateDialog(() {
                          pagos = p;
                          resultado = r;
                        }),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: (monto > 0 && resultado.esValido)
                              ? () => Navigator.pop(context, true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                          ),
                          child: Text(liquidarCompleto ? 'Liquidar' : 'Registrar abono'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (confirmado != true) return;

    try {
      if (liquidarCompleto) {
        await _controller.liquidar(idApartado: widget.idApartado, pagos: pagos);
      } else {
        await _controller.registrarAbono(idApartado: widget.idApartado, montoAbono: monto, pagos: pagos);
      }

      await _imprimirRecibo(montoAbono: monto, pagos: pagos, cambio: resultado.cambio);
      await _cargar();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: liquidarCompleto ? 'Apartado liquidado' : 'Abono registrado',
          mensaje: liquidarCompleto
              ? 'El apartado se liquidó correctamente.'
              : 'El abono se registró correctamente.',
          icono: Icons.check_circle_outline,
          textoConfirmar: 'Aceptar',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'No se pudo procesar el pago',
          mensaje: e.toString().replaceFirst('Exception: ', ''),
          icono: Icons.error_outline,
        ),
      );
    }
  }

  Future<void> _imprimirRecibo({
    required double montoAbono,
    required List<Map<String, dynamic>> pagos,
    required double cambio,
  }) async {
    final saldoPendienteActual = await _controller.obtenerSaldoPendiente(widget.idApartado);
    final apartado = _detalle!['apartado'] as Map<String, dynamic>;
    final total = (apartado['total'] as num).toDouble();
    final items = _detalle!['items'] as List<Map<String, dynamic>>;

    final pdf = await TicketApartadoService.generarReciboAbono(
      idApartado: widget.idApartado,
      clienteNombre: apartado['cliente_nombre']?.toString() ?? 'Cliente',
      items: items,
      tipoAbono: 'abono',
      montoAbono: montoAbono,
      pagos: pagos,
      cambio: cambio,
      totalApartado: total,
      abonadoAFecha: total - saldoPendienteActual,
      saldoPendiente: saldoPendienteActual,
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _cancelar() async {
    final motivoCtrl = TextEditingController();

    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar apartado'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(hintText: 'Motivo de la cancelación'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, motivoCtrl.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (motivo == null || motivo.trim().isEmpty || !mounted) return;

    await confirmarAccion(
      context: context,
      tituloConfirmar: 'Cancelar apartado',
      mensajeConfirmar:
          '¿Seguro que deseas cancelar este apartado? La reserva de stock se liberará. '
          'Si el cliente ya pagó abonos, el reembolso (si aplica) se maneja fuera del sistema.',
      iconoConfirmar: Icons.warning_amber_rounded,
      textoConfirmar: 'Cancelar apartado',
      accion: () async {
        await _controller.cancelar(idApartado: widget.idApartado, motivo: motivo.trim());
        await _cargar();
      },
      tituloExito: 'Apartado cancelado',
      mensajeExito: 'El apartado ha sido cancelado y la reserva de stock liberada.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: 'Apartado #${widget.idApartado}', mostrarVolver: true),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _buildContenido(),
    );
  }

  Widget _buildContenido() {
    final apartado = _detalle!['apartado'] as Map<String, dynamic>;
    final items = _detalle!['items'] as List<Map<String, dynamic>>;
    final historial = _detalle!['historial_pagos'] as List<Map<String, dynamic>>;
    final estado = apartado['estado'] as String;
    final esPendienteOVencido = estado == 'Pendiente' || estado == 'Vencido';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    apartado['cliente_nombre']?.toString() ?? 'Cliente',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: AppText.title),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _colorEstado(estado).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(estado, style: TextStyle(color: _colorEstado(estado), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Creado: ${apartado['fecha_creacion']}'),
              if (apartado['fecha_limite'] != null) Text('Vence: ${apartado['fecha_limite']}'),
              const Divider(height: 32),
              const Text('Productos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.bodyLg)),
              const SizedBox(height: 10),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${item['producto_nombre']}')),
                        Text('${item['cantidad']} x ${AppConfig.formatoMoneda((item['precio_neto'] as num))}'),
                      ],
                    ),
                  )),
              const Divider(height: 32),
              _fila('Subtotal', (apartado['subtotal'] as num).toDouble()),
              if ((apartado['descuento_total'] as num) > 0)
                _fila('Descuento', -(apartado['descuento_total'] as num).toDouble()),
              _fila('Total', (apartado['total'] as num).toDouble(), destacado: true),
              _fila('Saldo pendiente', _saldoPendiente, destacado: true, color: AppColors.error),
              const Divider(height: 32),
              const Text('Historial de pagos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppText.bodyLg)),
              const SizedBox(height: 10),
              if (historial.isEmpty)
                const Text('Sin pagos registrados todavía.')
              else
                ...historial.map((abono) {
                  final pagosAbono = abono['pagos'] as List<Map<String, dynamic>>;
                  final desglose = pagosAbono.map((p) => '${p['metodo_pago']}: ${AppConfig.formatoMoneda((p['monto'] as num))}').join(', ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${abono['tipo']} · ${abono['fecha']} · $desglose')),
                        Text('${AppConfig.formatoMoneda((abono['monto'] as num))}'),
                      ],
                    ),
                  );
                }),
              if (esPendienteOVencido) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _mostrarDialogoPago(liquidarCompleto: false),
                        child: const Text('Registrar abono'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _mostrarDialogoPago(liquidarCompleto: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                        ),
                        child: const Text('Liquidar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _cancelar,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Cancelar apartado'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, double valor, {bool destacado = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: TextStyle(fontWeight: destacado ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${AppConfig.formatoMoneda(valor)}',
            style: TextStyle(fontWeight: destacado ? FontWeight.bold : FontWeight.normal, color: color),
          ),
        ],
      ),
    );
  }
}
