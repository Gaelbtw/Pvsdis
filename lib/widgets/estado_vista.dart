import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Los estados de una pantalla que carga datos: cargando, error y contenido.
///
/// Existe por un defecto que compartían casi todas las vistas de la app.
/// Todas cargaban así:
///
/// ```dart
/// final data = await controller.obtenerTodos();
/// if (!mounted) return;
/// setState(() { lista = data; cargando = false; });
/// ```
///
/// Sin un solo `try`. Si la consulta lanzaba —base bloqueada, disco lleno,
/// archivo corrupto— la línea que apaga el indicador nunca corría y la rueda
/// giraba **para siempre**, sin mensaje ni forma de reintentar. El error solo
/// llegaba a la consola, que el cliente no ve. La única salida era cerrar la
/// aplicación.
///
/// Se resuelve aquí y no en cada pantalla a propósito: son veinte vistas con
/// el mismo problema, y repetir el mismo bloque veinte veces garantiza que
/// alguna se quede sin él (que es exactamente lo que ya pasó con el indicador
/// de carga en cuatro de ellas).
class EstadoVista extends StatelessWidget {
  const EstadoVista({
    super.key,
    required this.cargando,
    this.error,
    this.onReintentar,
  });

  final bool cargando;

  /// Mensaje ya traducido a algo que una persona entienda. `null` si no hubo
  /// error. Tiene prioridad sobre [cargando]: un error deja de ser una espera.
  final String? error;

  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'No se pudieron cargar los datos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppText.title,
                fontWeight: FontWeight.w800,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppText.body,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (onReintentar != null) ...[
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh, size: 19),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
                  textStyle: const TextStyle(
                    fontSize: AppText.body,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado vacío de una lista o rejilla: no hay nada que mostrar, y eso no es
/// un error.
///
/// Vale la pena distinguirlo del error y de la carga. Una rejilla sin
/// resultados y sin este widget deja un rectángulo en blanco, y quien busca un
/// producto que escribió mal no sabe si no hay coincidencias o si la pantalla
/// se colgó.
class PanelVacio extends StatelessWidget {
  const PanelVacio({
    super.key,
    required this.mensaje,
    this.icono = Icons.inbox_outlined,
    this.detalle,
  });

  final String mensaje;
  final IconData icono;

  /// Segunda línea opcional: qué hacer al respecto ("Da de alta el primero",
  /// "Prueba con otro nombre").
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 46, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppText.bodyLg,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(height: 6),
            Text(
              detalle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppText.small,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
