import 'package:flutter/material.dart';

import '../core/database/database_helper.dart';
import '../core/sync/outbox/sync_outbox_inspector.dart';
import '../core/sync/sync_scheduler.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';

/// Diagnóstico de la sincronización: qué cambios locales faltan por subir y
/// cuáles quedaron atorados (dead-letter) y necesitan que el usuario decida.
/// Cubre el requisito de "detectar problemas de sincronización" de forma
/// accionable -- las filas fallidas se pueden reintentar o descartar aquí.
class SyncProblemasView extends StatefulWidget {
  const SyncProblemasView({super.key});

  @override
  State<SyncProblemasView> createState() => _SyncProblemasViewState();
}

class _SyncProblemasViewState extends State<SyncProblemasView> {
  final _inspector = SyncOutboxInspector();

  bool _cargando = true;
  List<OutboxItem> _pendientes = const [];
  List<OutboxItem> _fallidas = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final datos = await _inspector.cargar();
    if (!mounted) return;
    setState(() {
      _pendientes = datos.pendientes;
      _fallidas = datos.fallidas;
      _cargando = false;
    });
  }

  Future<void> _sincronizarAhora() async {
    await SyncScheduler.instancia.sincronizarAhora();
    await _cargar();
  }

  Future<void> _reintentar(OutboxItem item) async {
    _inspector.reintentar(await DatabaseHelper().database, item.id);
    await _cargar();
  }

  Future<void> _descartar(OutboxItem item) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'Descartar cambio',
        mensaje:
            'Este cambio (${item.entidad} · ${item.operacion}) no llegará a la nube. Esta acción no se puede deshacer. ¿Descartar?',
        icono: Icons.delete_outline,
        color: AppColors.error,
        textoConfirmar: 'Descartar',
        textoCancelar: 'Cancelar',
        esDestructivo: true,
        onConfirm: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );
    if (confirmado != true) return;
    await _inspector.descartar(await DatabaseHelper().database, item.id);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomHeader(titulo: 'Pendientes y problemas de sync', mostrarVolver: true),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _barraResumen(),
                      const SizedBox(height: 20),
                      if (_fallidas.isNotEmpty) ...[
                        _tituloGrupo('Requieren atención', _fallidas.length, AppColors.error),
                        const SizedBox(height: 12),
                        ..._fallidas.map((i) => _tarjetaFallida(i)),
                        const SizedBox(height: 24),
                      ],
                      _tituloGrupo('Pendientes de subir', _pendientes.length, AppColors.primaryDark),
                      const SizedBox(height: 12),
                      if (_pendientes.isEmpty && _fallidas.isEmpty)
                        _vacio()
                      else if (_pendientes.isEmpty)
                        _lineaInfo('No hay cambios en cola. Todo lo que faltaba ya se subió.')
                      else
                        ..._pendientes.map((i) => _tarjetaPendiente(i)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _barraResumen() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_pendientes.length} pendientes · ${_fallidas.length} con problema',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                const Text('Desliza hacia abajo para actualizar.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _sincronizarAhora,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar ahora'),
          ),
        ],
      ),
    );
  }

  Widget _tituloGrupo(String titulo, int conteo, Color color) => Row(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text('$conteo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      );

  Widget _tarjetaFallida(OutboxItem item) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _encabezadoItem(item),
            if (item.ultimoError != null) ...[
              const SizedBox(height: 8),
              Text(item.ultimoError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _descartar(item),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Descartar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _reintentar(item),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _tarjetaPendiente(OutboxItem item) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: _encabezadoItem(item),
      );

  Widget _encabezadoItem(OutboxItem item) {
    final chips = <Widget>[
      _chip(item.operacion),
      if (item.esperandoPrerrequisito) _chip('esperando datos', color: AppColors.primaryDark),
      if (!item.esDeadLetter && !item.esperandoPrerrequisito && item.intentos > 0)
        _chip('${item.intentos} intento(s)', color: AppColors.warning),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(item.entidad,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
            Text(item.fechaCreacion.split('T').first,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );
  }

  Widget _chip(String texto, {Color color = AppColors.textSecondary}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _vacio() => Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.cloud_done_outlined, size: 48, color: AppColors.success),
            const SizedBox(height: 12),
            const Text('Todo al día',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('No hay cambios pendientes de subir a la nube.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _lineaInfo(String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texto, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );
}
