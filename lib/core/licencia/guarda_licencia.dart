import 'package:flutter/material.dart';

import '../../views/licencia_view.dart';
import 'licencia_service.dart';

/// Punto único donde se decide si una acción administrativa puede ejecutarse
/// con la licencia actual, y qué se le dice al usuario cuando no.
///
/// Existe para que los puntos de uso sean una sola línea y para que el mensaje
/// sea idéntico en todos: si cada pantalla escribiera el suyo, en tres meses
/// habría cuatro redacciones distintas de la misma mala noticia y ninguna
/// diría cómo resolverla.
///
/// **Nunca se pone delante de vender, cobrar, imprimir un ticket o cerrar
/// caja.** Ver [FuncionLicenciada].
class GuardaLicencia {
  GuardaLicencia._();

  /// `true` si se puede continuar. Si no, muestra el diálogo explicativo con
  /// un atajo a la pantalla de licencia y devuelve `false`.
  ///
  /// Uso:
  /// ```dart
  /// onTap: () async {
  ///   if (!await GuardaLicencia.permite(context, FuncionLicenciada.reportes)) {
  ///     return;
  ///   }
  ///   // ...abrir la pantalla
  /// }
  /// ```
  static Future<bool> permite(
    BuildContext context,
    FuncionLicenciada funcion,
  ) async {
    final estado = LicenciaService.instancia.estado;
    if (estado.permite(funcion)) return true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline_rounded, size: 32),
        title: const Text('Función no disponible'),
        content: Text(
          '${estado.mensaje}\n\n'
          'Vender, cobrar, imprimir tickets y cerrar caja siguen funcionando '
          'con normalidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LicenciaView()),
              );
            },
            child: const Text('Ver licencia'),
          ),
        ],
      ),
    );
    return false;
  }
}
