import 'package:flutter/material.dart';

import '../controllers/apartados_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/config/app_config.dart';
import '../widgets/nav_bar.dart';
import 'apartado_detalle_view.dart';
import 'nuevo_apartado_view.dart';

/// Lista de apartados: cliente, total, saldo pendiente y estado. Tocar una
/// fila abre el detalle (abonos/liquidar/cancelar); "Nuevo apartado" abre el
/// flujo de creación.
class ApartadosView extends StatefulWidget {
  const ApartadosView({super.key});

  @override
  State<ApartadosView> createState() => _ApartadosViewState();
}

class _ApartadosViewState extends State<ApartadosView> {
  final _controller = ApartadosController();

  List<Map<String, dynamic>> _apartados = [];
  List<Map<String, dynamic>> _filtrados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await _controller.obtenerTodos();
    if (!mounted) return;
    setState(() {
      _apartados = data;
      _filtrados = data;
      _cargando = false;
    });
  }

  void _buscar(String query) {
    if (query.isEmpty) {
      setState(() => _filtrados = _apartados);
      return;
    }
    final q = query.toLowerCase();
    setState(() {
      _filtrados = _apartados
          .where((a) => (a['cliente_nombre']?.toString() ?? '').toLowerCase().contains(q))
          .toList();
    });
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: 'Apartados', mostrarVolver: true),
      body: _cargando
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
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 320,
                          child: TextField(
                            onChanged: _buscar,
                            decoration: InputDecoration(
                              hintText: 'Buscar por cliente...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NuevoApartadoView()),
                            );
                            _cargar();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Nuevo apartado'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Reservas de productos con anticipo, abonos y liquidación',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: _filtrados.isEmpty
                          ? const Center(child: Text('No hay apartados registrados'))
                          : ListView.separated(
                              itemCount: _filtrados.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final a = _filtrados[i];
                                final estado = a['estado'] as String;
                                final saldo = (a['saldo_pendiente'] as num?)?.toDouble() ?? 0;
                                final total = (a['total'] as num?)?.toDouble() ?? 0;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ApartadoDetalleView(idApartado: a['id_apartado'] as int),
                                      ),
                                    );
                                    _cargar();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceAlt,
                                      borderRadius: BorderRadius.circular(AppRadius.lg),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    a['cliente_nombre']?.toString() ?? 'Cliente',
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: AppText.bodyLg,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: _colorEstado(estado).withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(AppRadius.pill),
                                                    ),
                                                    child: Text(
                                                      estado,
                                                      style: TextStyle(
                                                        fontSize: AppText.overline,
                                                        fontWeight: FontWeight.w700,
                                                        color: _colorEstado(estado),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Total: ${AppConfig.formatoMoneda(total)}   ·   '
                                                'Saldo: ${AppConfig.formatoMoneda(saldo)}',
                                                style: const TextStyle(
                                                    color: AppColors.textSecondary, fontSize: AppText.caption),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
