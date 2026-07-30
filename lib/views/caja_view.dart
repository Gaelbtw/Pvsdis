import 'package:flutter/material.dart';

import '../controllers/caja_controller.dart';
import '../core/config/app_config.dart';
import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/caja_model.dart';
import '../services/ticket_cierre_caja_service.dart';
import '../services/ticket_corte_x_service.dart';
import '../services/impresion_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';
import '../widgets/toast.dart';
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
      Toast.exito(context, 'Caja abierta correctamente');
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo abrir la caja. $mensaje');
    }
  }

  void confirmarCierre() {
    final r = resumen;
    if (r == null) return;

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Cerrar caja",
        mensaje: "Fondo inicial: ${AppConfig.formatoMoneda(r.fondoInicial)}\n"
            "Ventas efectivo: ${AppConfig.formatoMoneda(r.ventasEfectivo)}\n"
            "Ventas tarjeta: ${AppConfig.formatoMoneda(r.ventasTarjeta)}\n"
            "Ventas transferencia: ${AppConfig.formatoMoneda(r.ventasTransferencia)}\n"
            "${r.totalAnticipos > 0 ? 'Anticipos de apartados: ${AppConfig.formatoMoneda(r.totalAnticipos)}\n' : ''}"
            "Cambio entregado: ${AppConfig.formatoMoneda(r.cambioEntregado)}\n"
            "Devoluciones: ${AppConfig.formatoMoneda(r.devoluciones)}\n"
            "Efectivo esperado: ${AppConfig.formatoMoneda(r.efectivoEsperado)}\n"
            "Efectivo contado: ${AppConfig.formatoMoneda(contado)}\n"
            "Diferencia: ${AppConfig.formatoMoneda(diferencia)}\n\n"
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
        resumen: r,
        contado: contado,
        diferencia: diferencia,
        observacionesApertura: caja.observacionesApertura,
      );

      await ImpresionService.imprimir(pdf);

      await cargar();

      if (!mounted) return;
      Toast.exito(context, 'Caja cerrada. El cierre se registró correctamente.');
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo cerrar la caja. $mensaje');
    }
  }

  // 💵 ENTRADA / SALIDA MANUAL DE EFECTIVO
  void _registrarMovimientoDialog({required bool esEntrada}) {
    final montoCtrl = TextEditingController();
    final conceptoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: esEntrada ? "Registrar entrada de efectivo" : "Registrar salida de efectivo",
        subtitulo: esEntrada
            ? "Dinero que entra a la caja por un motivo ajeno a la venta."
            : "Dinero que sale de la caja (pago menor, retiro, etc.).",
        textoGuardar: "Registrar",
        campos: [
          AppTextField(
            controller: montoCtrl,
            hint: "Monto",
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            icon: Icons.payments,
          ),
          AppTextField(
            controller: conceptoCtrl,
            hint: "Motivo",
            icon: Icons.notes,
            maxLines: 2,
          ),
        ],
        onGuardar: () async {
          final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.'));
          if (monto == null || monto <= 0) {
            Toast.error(context, 'Ingresa un monto válido.');
            return;
          }
          if (conceptoCtrl.text.trim().isEmpty) {
            Toast.error(context, 'Indica el motivo del movimiento.');
            return;
          }

          Navigator.pop(context);
          await _registrarMovimiento(esEntrada: esEntrada, monto: monto, concepto: conceptoCtrl.text);
        },
      ),
    );
  }

  Future<void> _registrarMovimiento({
    required bool esEntrada,
    required double monto,
    required String concepto,
  }) async {
    try {
      await _cajaController.registrarMovimientoEfectivo(
        esEntrada: esEntrada,
        monto: monto,
        concepto: concepto,
      );
      await cargar();

      if (!mounted) return;
      Toast.exito(
        context,
        esEntrada ? 'Entrada de efectivo registrada.' : 'Salida de efectivo registrada.',
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo registrar el movimiento. $mensaje');
    }
  }

  // 🧾 CORTE X (lectura sin cerrar el turno)
  Future<void> _corteX() async {
    final caja = cajaAbierta;
    final r = resumen;
    if (caja == null || r == null) return;

    try {
      final pdf = await TicketCorteXService.generar(
        cajero: SessionManager.currentUserName,
        fechaApertura: caja.fechaApertura,
        fechaCorte: DateTime.now().toIso8601String(),
        resumen: r,
      );
      await ImpresionService.imprimir(pdf);
      if (!mounted) return;
      Toast.exito(context, 'Corte X generado. La caja sigue abierta.');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo generar el Corte X.');
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
            style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w800, color: AppColors.textStrong),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Resumen de caja",
              style: TextStyle(fontSize: AppText.titleLg, fontWeight: FontWeight.w800, color: AppColors.textStrong),
            ),
            const SizedBox(height: 4),
            Text(
              AppConfig.turnoDeIso(cajaAbierta!.fechaApertura) == null
                  ? "Abierta el ${cajaAbierta!.fechaApertura}"
                  : "Abierta el ${cajaAbierta!.fechaApertura} · Turno ${AppConfig.turnoDeIso(cajaAbierta!.fechaApertura)}",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
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
                if (r.entradasEfectivo > 0)
                  _statCard("Entradas de efectivo", r.entradasEfectivo, Icons.south_west),
                if (r.salidasEfectivo > 0)
                  _statCard("Salidas de efectivo", r.salidasEfectivo, Icons.north_east),
                _statCard("Efectivo esperado", r.efectivoEsperado, Icons.point_of_sale),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              "Movimientos y arqueo",
              style: TextStyle(fontSize: AppText.subtitle, fontWeight: FontWeight.w800, color: AppColors.textStrong),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Entradas/salidas manuales solo para roles con el permiso
                // (ver matriz de permisos). El Corte X de lectura queda para
                // cualquiera que tenga la caja abierta.
                if (PermisosService.instancia.puedeActual(Permiso.movimientosCaja)) ...[
                  OutlinedButton.icon(
                    onPressed: () => _registrarMovimientoDialog(esEntrada: true),
                    icon: const Icon(Icons.south_west, size: 18),
                    label: const Text("Registrar entrada"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _registrarMovimientoDialog(esEntrada: false),
                    icon: const Icon(Icons.north_east, size: 18),
                    label: const Text("Registrar salida"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _corteX,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text("Corte X (lectura)"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textStrong,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              "Cerrar caja",
              style: TextStyle(fontSize: AppText.subtitle, fontWeight: FontWeight.w800, color: AppColors.textStrong),
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
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Diferencia", style: TextStyle(color: AppColors.textSecondary)),
                      Text(
                        AppConfig.formatoMoneda(diferencia),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppText.subtitle,
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
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
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark, size: 22),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.caption, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            AppConfig.formatoMoneda(value),
            style: const TextStyle(fontSize: AppText.subtitle, fontWeight: FontWeight.w800, color: AppColors.textStrong),
          ),
        ],
      ),
    );
  }
}
