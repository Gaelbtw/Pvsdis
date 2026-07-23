import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../controllers/caja_controller.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/caja_model.dart';
import '../services/ticket_cierre_caja_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';
import 'historial_cajas_view.dart';

/// Pantalla única de Caja: muestra el formulario de apertura si el usuario
/// actual no tiene ninguna caja abierta, o el resumen en vivo + cierre si
/// ya tiene una. El acceso al historial vive como acción del encabezado.
class CajaView extends StatefulWidget {
  const CajaView({super.key});

  @override
  State<CajaView> createState() => _CajaViewState();
}

class _CajaViewState extends State<CajaView> {
  final _cajaController = CajaController();

  bool cargando = true;
  Caja? cajaAbierta;
  ResumenCaja? resumen;

  final contadoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    contadoCtrl.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() => cargando = true);

    final idUsuario = SessionManager.currentUserId ?? 1;
    final caja = await _cajaController.obtenerCajaAbierta(idUsuario);

    ResumenCaja? nuevoResumen;
    if (caja != null) {
      nuevoResumen = await _cajaController.calcularResumenCaja(caja.idCaja!);
    }

    if (!mounted) return;
    setState(() {
      cajaAbierta = caja;
      resumen = nuevoResumen;
      contadoCtrl.clear();
      cargando = false;
    });
  }

  double get contado => double.tryParse(contadoCtrl.text.replaceAll(',', '.')) ?? 0;

  double get diferencia => resumen == null ? 0 : contado - resumen!.efectivoEsperado;

  void abrirCajaDialog() {
    final fondoCtrl = TextEditingController(text: AppConfig.actual.fondoCaja.toStringAsFixed(2));
    final observacionesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: "Abrir Caja",
        subtitulo: "Registra el fondo con el que arrancas tu turno.",
        textoGuardar: "Abrir",
        campos: [
          AppTextField(
            controller: fondoCtrl,
            hint: "Fondo inicial",
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            icon: Icons.payments,
          ),
          AppTextField(
            controller: observacionesCtrl,
            hint: "Observaciones (opcional)",
            icon: Icons.notes,
            maxLines: 2,
          ),
        ],
        onGuardar: () async {
          final fondo = double.tryParse(fondoCtrl.text.replaceAll(',', '.'));
          if (fondo == null) {
            showDialog(
              context: context,
              builder: (_) => const CustomAlert(
                titulo: 'Caja',
                mensaje: 'Ingresa un fondo inicial válido.',
                icono: Icons.error_outline,
              ),
            );
            return;
          }

          Navigator.pop(context);
          await _abrirCaja(fondo, observacionesCtrl.text);
        },
      ),
    );
  }

  Future<void> _abrirCaja(double fondo, String observaciones) async {
    try {
      await _cajaController.abrirCaja(fondoInicial: fondo, observaciones: observaciones);
      await cargar();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Caja abierta',
          mensaje: 'Tu caja quedó abierta correctamente.',
          icono: Icons.check_circle,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'No se pudo abrir la caja',
          mensaje: mensaje,
          icono: Icons.error_outline,
        ),
      );
    }
  }

  void confirmarCierre() {
    final r = resumen;
    if (r == null) return;

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Cerrar caja",
        mensaje: "Fondo inicial: \$${r.fondoInicial.toStringAsFixed(2)}\n"
            "Ventas efectivo: \$${r.ventasEfectivo.toStringAsFixed(2)}\n"
            "Ventas tarjeta: \$${r.ventasTarjeta.toStringAsFixed(2)}\n"
            "Ventas transferencia: \$${r.ventasTransferencia.toStringAsFixed(2)}\n"
            "${r.totalAnticipos > 0 ? 'Anticipos de apartados: \$${r.totalAnticipos.toStringAsFixed(2)}\n' : ''}"
            "Cambio entregado: \$${r.cambioEntregado.toStringAsFixed(2)}\n"
            "Devoluciones: \$${r.devoluciones.toStringAsFixed(2)}\n"
            "Efectivo esperado: \$${r.efectivoEsperado.toStringAsFixed(2)}\n"
            "Efectivo contado: \$${contado.toStringAsFixed(2)}\n"
            "Diferencia: \$${diferencia.toStringAsFixed(2)}\n\n"
            "¿Confirmas el cierre? Esta acción no se puede deshacer.",
        icono: Icons.point_of_sale,
        textoCancelar: "Cancelar",
        textoConfirmar: "Cerrar caja",
        onConfirm: _cerrarCaja,
      ),
    );
  }

  Future<void> _cerrarCaja() async {
    final caja = cajaAbierta;
    final r = resumen;
    if (caja == null || r == null) return;

    try {
      await _cajaController.cerrarCaja(idCaja: caja.idCaja!, efectivoContado: contado);

      final pdf = await TicketCierreCajaService.generarCierre(
        fechaApertura: caja.fechaApertura,
        fechaCierre: DateTime.now().toIso8601String(),
        cajero: SessionManager.currentUserName,
        fondo: r.fondoInicial,
        efectivo: r.ventasEfectivo,
        tarjeta: r.ventasTarjeta,
        transferencia: r.ventasTransferencia,
        cambioEntregado: r.cambioEntregado,
        devoluciones: r.devoluciones,
        total: r.totalVentas,
        contado: contado,
        esperado: r.efectivoEsperado,
        diferencia: diferencia,
        observacionesApertura: caja.observacionesApertura,
      );

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());

      await cargar();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => const CustomAlert(
          titulo: 'Caja cerrada',
          mensaje: 'El cierre se registró correctamente.',
          icono: Icons.check_circle_outline,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'No se pudo cerrar la caja',
          mensaje: mensaje,
          icono: Icons.error_outline,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(
        titulo: "Caja",
        mostrarVolver: true,
        extraActions: [
          IconButton(
            tooltip: "Historial de cajas",
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistorialCajasView()),
            ),
          ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: cajaAbierta == null ? _panelSinCaja() : _panelCajaAbierta(),
            ),
    );
  }

  Widget _panelSinCaja() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.point_of_sale, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            "No tienes una caja abierta",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textStrong),
          ),
          const SizedBox(height: 8),
          const Text(
            "Abre tu caja para poder registrar ventas y devoluciones.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: abrirCajaDialog,
            icon: const Icon(Icons.lock_open),
            label: const Text("Abrir Caja"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelCajaAbierta() {
    final r = resumen!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.cardShadow,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Resumen de caja",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textStrong),
            ),
            const SizedBox(height: 4),
            Text(
              "Abierta el ${cajaAbierta!.fechaApertura}",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _statCard("Fondo inicial", r.fondoInicial, Icons.savings_outlined),
                _statCard("Efectivo", r.ventasEfectivo, Icons.attach_money),
                _statCard("Tarjeta", r.ventasTarjeta, Icons.credit_card),
                _statCard("Transferencia", r.ventasTransferencia, Icons.account_balance_outlined),
                _statCard("Cambio entregado", r.cambioEntregado, Icons.currency_exchange),
                _statCard("Devoluciones", r.devoluciones, Icons.assignment_return_outlined),
                _statCard("Efectivo esperado", r.efectivoEsperado, Icons.point_of_sale),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              "Cerrar caja",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: AppTextField(
                controller: contadoCtrl,
                hint: "Efectivo contado",
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                icon: Icons.payments,
                fillColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: contadoCtrl,
              builder: (_, child) {
                return Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: diferencia == 0
                        ? AppColors.surface
                        : diferencia > 0
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Diferencia", style: TextStyle(color: AppColors.textSecondary)),
                      Text(
                        "\$${diferencia.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: diferencia == 0
                              ? AppColors.textPrimary
                              : diferencia > 0
                                  ? AppColors.success
                                  : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 320,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: confirmarCierre,
                icon: const Icon(Icons.lock),
                label: const Text("Cerrar Caja"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, double value, IconData icon) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 22),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            "\$${value.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textStrong),
          ),
        ],
      ),
    );
  }
}
