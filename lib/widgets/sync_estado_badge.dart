import 'package:flutter/material.dart';

import '../core/sync/sync_scheduler.dart';
import '../core/theme/app_colors.dart';

/// Indicador compacto del estado de sincronización para la barra superior
/// ([CustomHeader]). Escucha `SyncScheduler.instancia.estado` y se repinta
/// solo cuando cambia; tocarlo dispara una sincronización manual
/// ("Sincronizar ahora"). Cubre el requisito de "sincronización transparente":
/// el cajero ve de un vistazo si está al día, cuántos cambios faltan por
/// subir, o si perdió la conexión.
class SyncEstadoBadge extends StatelessWidget {
  const SyncEstadoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoSyncUI>(
      valueListenable: SyncScheduler.instancia.estado,
      builder: (context, estado, _) {
        final v = _visual(estado);
        final sincronizando = estado.fase == FaseSync.sincronizando;

        return Tooltip(
          message: v.tooltip,
          child: InkWell(
            onTap: sincronizando ? null : () => SyncScheduler.instancia.sincronizarAhora(),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: v.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: v.color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sincronizando)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(v.color)),
                    )
                  else
                    Icon(v.icono, size: 16, color: v.color),
                  if (v.etiqueta != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      v.etiqueta!,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppText.caption, color: v.color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _VisualEstado _visual(EstadoSyncUI estado) {
    if (estado.fase == FaseSync.sincronizando) {
      return const _VisualEstado(_azul, Icons.sync, 'Sincronizando', 'Sincronizando con la nube…');
    }

    if (estado.pendientes > 0) {
      return _VisualEstado(
        _naranja,
        Icons.cloud_upload_outlined,
        '${estado.pendientes}',
        '${estado.pendientes} ${estado.pendientes == 1 ? 'cambio pendiente' : 'cambios pendientes'} de subir. Toca para sincronizar.',
      );
    }

    final resultado = estado.ultimoResultado;
    if (resultado == null) {
      return const _VisualEstado(
        AppColors.textSecondary,
        Icons.cloud_queue,
        null,
        'Aún no se ha sincronizado. Toca para sincronizar ahora.',
      );
    }

    if (resultado.completo) {
      return _VisualEstado(
        _verde,
        Icons.cloud_done_outlined,
        null,
        'Al día${_desde(estado.ultimaSincronizacion)}. Toca para sincronizar ahora.',
      );
    }

    // Ciclo no completo: sin conexión, sin sesión, o error a mitad de camino.
    return _VisualEstado(
      AppColors.textSecondary,
      Icons.cloud_off_outlined,
      null,
      '${resultado.error ?? 'Sin conexión con la nube'}. Toca para reintentar.',
    );
  }

  String _desde(DateTime? momento) {
    if (momento == null) return '';
    final hora = momento.hour % 12 == 0 ? 12 : momento.hour % 12;
    final minuto = momento.minute.toString().padLeft(2, '0');
    final periodo = momento.hour >= 12 ? 'p.m.' : 'a.m.';
    return ' (última: $hora:$minuto $periodo)';
  }

  static const _verde = AppColors.success;
  static const _naranja = AppColors.warning;
  static const _azul = AppColors.info;
}

class _VisualEstado {
  const _VisualEstado(this.color, this.icono, this.etiqueta, this.tooltip);
  final Color color;
  final IconData icono;
  final String? etiqueta;
  final String tooltip;
}
