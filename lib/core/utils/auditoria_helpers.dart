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
    case "LOGIN":
    case "APERTURA_CAJA":
    case "ACTIVAR":
      return AppColors.success;
    case "EDIT":
    case "DESCUENTO":
    case "PROMOCION":
    case "ABONO_PROVEEDOR":
      return AppColors.warning;
    case "DELETE":
    case "CANCEL":
    case "DEVOLUCION":
      return AppColors.error;
    case "CIERRE_CAJA":
    case "LOGOUT":
    case "DESACTIVAR":
      return AppColors.textSecondary;
    default:
      return AppColors.textPrimary;
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
    case "LOGIN":
      return Icons.login;
    case "LOGOUT":
      return Icons.logout;
    case "APERTURA_CAJA":
      return Icons.point_of_sale;
    case "CIERRE_CAJA":
      return Icons.lock_clock_outlined;
    case "CANCEL":
      return Icons.cancel_outlined;
    case "DEVOLUCION":
      return Icons.assignment_return_outlined;
    case "ACTIVAR":
      return Icons.toggle_on_outlined;
    case "DESACTIVAR":
      return Icons.toggle_off_outlined;
    case "DESCUENTO":
      return Icons.sell_outlined;
    case "PROMOCION":
      return Icons.local_offer_outlined;
    case "ABONO_PROVEEDOR":
      return Icons.payments_outlined;
    default:
      return Icons.history;
  }
}

/// Todas las acciones que efectivamente se registran hoy en `Auditorias`,
/// usadas para poblar filtros (dropdown de acción en Auditorías y en el
/// reporte de movimientos por usuario) sin dejar valores reales fuera.
const accionesAuditoria = [
  'CREATE',
  'EDIT',
  'DELETE',
  'LOGIN',
  'LOGOUT',
  'APERTURA_CAJA',
  'CIERRE_CAJA',
  'CANCEL',
  'DEVOLUCION',
  'ACTIVAR',
  'DESACTIVAR',
  'DESCUENTO',
  'PROMOCION',
  'ABONO_PROVEEDOR',
];

/// Valores reales de `tabla` (módulo) usados como origen de un registro de
/// auditoría. Fija (no derivada de resultados ya filtrados) para que el
/// dropdown de módulo en el reporte de movimientos por usuario no pierda su
/// selección cuando otro filtro deja la tabla actual sin resultados.
const modulosAuditoria = [
  'Ventas',
  'Compras',
  'Clientes',
  'Proveedores',
  'Productos',
  'Inventario',
  'Usuarios',
  'Promociones',
  'Apartados',
  'Cajas',
  'Sesion',
  'Configuracion',
];

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
