import 'package:flutter/material.dart';

import '../../models/configuracion_model.dart';
import '../../services/configuracion_service.dart';
import '../theme/app_colors.dart';

/// Caché estático de la configuración del negocio, cargado una vez al
/// iniciar la app (mismo patrón que [SessionManager]). Permite leer nombre,
/// moneda, IVA, mensaje de ticket, etc. desde cualquier parte del código
/// —incluidos los servicios de generación de tickets, que no son widgets y
/// no tienen `BuildContext`— sin volver a consultar la base de datos cada
/// vez.
class AppConfig {
  AppConfig._();

  static Configuracion? _actual;

  static Configuracion get actual => _actual ?? Configuracion.porDefecto();

  static Future<void> cargar() async {
    _actual = await ConfiguracionService().obtener();
    AppColors.actualizar(Color(_actual!.colorPrimario));
  }

  /// Se llama después de guardar cambios en la pantalla de Configuración,
  /// para que el resto de la sesión actual use los datos nuevos de
  /// inmediato (el color de marca requiere reiniciar la app para
  /// reflejarse en el ThemeData ya construido).
  static void actualizar(Configuracion nueva) {
    _actual = nueva;
    AppColors.actualizar(Color(nueva.colorPrimario));
  }

  /// Formatea un monto con el símbolo de moneda configurado, ej. "$125.00".
  static String formatoMoneda(num valor) {
    return '${actual.simboloMoneda}${valor.toStringAsFixed(2)}';
  }
}
