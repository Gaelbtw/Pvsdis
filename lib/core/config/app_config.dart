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

  static int? _aMinutos(String hhmm) {
    final partes = hhmm.split(':');
    if (partes.length != 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// Turno operativo ("Matutino"/"Vespertino") al que corresponde [momento],
  /// según los horarios configurados en Configuración. `null` si cae fuera de
  /// ambos turnos. Rango semiabierto `[inicio, fin)` para que el minuto de
  /// traslape (p. ej. 14:00, fin del matutino e inicio del vespertino) cuente
  /// una sola vez, del lado del vespertino.
  static String? turnoPara(DateTime momento) {
    final minuto = momento.hour * 60 + momento.minute;
    final c = actual;
    final im = _aMinutos(c.horaInicioMatutino);
    final fm = _aMinutos(c.horaFinMatutino);
    final iv = _aMinutos(c.horaInicioVespertino);
    final fv = _aMinutos(c.horaFinVespertino);

    bool dentro(int? ini, int? fin) => ini != null && fin != null && minuto >= ini && minuto < fin;

    if (dentro(iv, fv)) return 'Vespertino';
    if (dentro(im, fm)) return 'Matutino';
    return null;
  }

  /// Turno operativo actual según la hora del sistema (`null` fuera de turno).
  static String? get turnoActual => turnoPara(DateTime.now());

  /// Turno de una fecha ISO (p. ej. `Caja.fechaApertura`), para etiquetar
  /// cortes/sesiones. `null` si la fecha no parsea o cae fuera de turno.
  static String? turnoDeIso(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    return dt == null ? null : turnoPara(dt);
  }
}
