import 'package:flutter/material.dart';

import '../controllers/caja_controller.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../models/caja_model.dart';
import '../widgets/nav_bar.dart';

/// Historial completo de cajas (abiertas y cerradas), de solo lectura: no
/// existe ninguna acción de edición aquí, a propósito — los cierres ya
/// confirmados no se modifican.
class HistorialCajasView extends StatefulWidget {
  const HistorialCajasView({super.key});

  @override
  State<HistorialCajasView> createState() => _HistorialCajasViewState();
}

class _HistorialCajasViewState extends State<HistorialCajasView> {
  final _cajaController = CajaController();

  bool cargando = true;
  List<Caja> cajas = [];

  bool get esAdmin => SessionManager.currentUserRole == 'Admin';

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    final lista = await _cajaController.obtenerHistorial(
      idUsuario: esAdmin ? null : SessionManager.currentUserId,
    );

    if (!mounted) return;
    setState(() {
      cajas = lista;
      cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomHeader(titulo: "Historial de Cajas", mostrarVolver: true),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : cajas.isEmpty
              ? const Center(
                  child: Text("Todavía no hay cajas registradas.", style: TextStyle(color: AppColors.textSecondary)),
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListView.separated(
                    itemCount: cajas.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _filaCaja(cajas[i]),
                  ),
                ),
    );
  }

  Widget _filaCaja(Caja caja) {
    final diferencia = caja.diferencia;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: caja.estaAbierta ? AppColors.success.withValues(alpha: 0.1) : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              caja.estado,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: AppText.caption,
                color: caja.estaAbierta ? AppColors.success : AppColors.textStrong,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConfig.turnoDeIso(caja.fechaApertura) == null
                      ? "Apertura: ${caja.fechaApertura}"
                      : "Apertura: ${caja.fechaApertura} · ${AppConfig.turnoDeIso(caja.fechaApertura)}",
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textStrong),
                ),
                Text(
                  caja.fechaCierre != null ? "Cierre: ${caja.fechaCierre}" : "Aún abierta",
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.caption),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "Fondo: ${AppConfig.formatoMoneda(caja.fondoInicial)}",
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: caja.efectivoEsperado == null
                ? const Text("—", style: TextStyle(color: AppColors.textSecondary))
                : Text(
                    "Esperado: ${AppConfig.formatoMoneda(caja.efectivoEsperado!)}",
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
          ),
          Expanded(
            flex: 2,
            child: caja.efectivoContado == null
                ? const Text("—", style: TextStyle(color: AppColors.textSecondary))
                : Text(
                    "Contado: ${AppConfig.formatoMoneda(caja.efectivoContado!)}",
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
          ),
          Expanded(
            flex: 2,
            child: diferencia == null
                ? const Text("—", style: TextStyle(color: AppColors.textSecondary))
                : Text(
                    "Dif: ${AppConfig.formatoMoneda(diferencia)}",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: diferencia == 0
                          ? AppColors.textPrimary
                          : diferencia > 0
                              ? AppColors.success
                              : AppColors.error,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
