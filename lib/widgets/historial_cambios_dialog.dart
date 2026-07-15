import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/auditoria_helpers.dart';
import '../models/auditoria_model.dart';

/// Diálogo modal de "historial de cambios": lista de auditoría con buscador,
/// usado desde Inventario. Antes vivía completo dentro de
/// `inventario_view.dart` (~110 líneas del diálogo + la fila).
Future<void> mostrarHistorialCambios(
  BuildContext context, {
  required String titulo,
  required String subtitulo,
  required List<Auditoria> cambios,
}) {
  String filtro = "";

  return showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setDialogState) {
        final filtrados = cambios.where((c) {
          final texto = filtro.toLowerCase();

          return c.usuario.toLowerCase().contains(texto) ||
              c.accion.toLowerCase().contains(texto) ||
              c.tabla.toLowerCase().contains(texto) ||
              c.descripcion.toLowerCase().contains(texto) ||
              (c.idRegistro?.toString().contains(filtro) ?? false);
        }).toList();

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 820,
            height: 620,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, color: AppColors.primaryDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: "Cerrar",
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitulo,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  onChanged: (value) {
                    setDialogState(() => filtro = value);
                  },
                  decoration: InputDecoration(
                    hintText: "Buscar por usuario, producto, accion o folio...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: filtrados.isEmpty
                      ? const Center(child: Text("No hay cambios registrados"))
                      : ListView.separated(
                          itemCount: filtrados.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _filaCambio(filtrados[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _filaCambio(Auditoria cambio) {
  final color = colorPorAccionAuditoria(cambio.accion);

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(iconoPorAccionAuditoria(cambio.accion), color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cambio.descripcion,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Usuario: ${cambio.usuario}  |  Fecha: ${formatearFechaHora(cambio.fechaHora)}  |  Registro: ${cambio.idRegistro ?? '-'}",
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            cambio.accion,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}
