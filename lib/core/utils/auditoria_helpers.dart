import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Presentación de registros de auditoría (color/ícono por tipo de acción,
/// formato de fecha). Antes estas mismas funciones, byte por byte
/// idénticas, existían duplicadas en `inventario_view.dart` y
/// `auditorias_view.dart`.

const auditoriaHeaderStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  color: AppColors.textMuted,
);

Color colorPorAccionAuditoria(String accion) {
  switch (accion) {
    case "CREATE":
      return Colors.green.shade700;
    case "EDIT":
      return Colors.orange.shade800;
    case "DELETE":
      return Colors.red.shade700;
    default:
      return Colors.black87;
  }
}

IconData iconoPorAccionAuditoria(String accion) {
  switch (accion) {
    case "CREATE":
      return Icons.add_circle_outline;
    case "EDIT":
      return Icons.edit_outlined;
    case "DELETE":
      return Icons.delete_outline;
    default:
      return Icons.history;
  }
}

String formatearFechaHora(String value) {
  final fecha = DateTime.tryParse(value);
  if (fecha == null) return value;

  final dd = fecha.day.toString().padLeft(2, '0');
  final mm = fecha.month.toString().padLeft(2, '0');
  final yyyy = fecha.year.toString();
  final hh = fecha.hour.toString().padLeft(2, '0');
  final min = fecha.minute.toString().padLeft(2, '0');

  return "$dd/$mm/$yyyy $hh:$min";
}
