import 'package:flutter/material.dart';

/// Clasificación de un nivel de stock frente a su mínimo configurado.
/// Antes esta misma regla (agotado / bajo / disponible) se calculaba por
/// separado en dos lugares distintos de `inventario_view.dart` (una vez
/// para las tarjetas de resumen, otra vez por fila de la tabla).
enum EstadoStock { agotado, bajo, disponible }

EstadoStock clasificarStock(int stock, int stockMinimo) {
  if (stock == 0) return EstadoStock.agotado;
  if (stock <= stockMinimo) return EstadoStock.bajo;
  return EstadoStock.disponible;
}

extension EstadoStockPresentacion on EstadoStock {
  String get etiqueta => switch (this) {
        EstadoStock.agotado => "Agotado",
        EstadoStock.bajo => "Inventario bajo",
        EstadoStock.disponible => "Disponible",
      };

  Color get color => switch (this) {
        EstadoStock.agotado => Colors.red,
        EstadoStock.bajo => Colors.orange,
        EstadoStock.disponible => Colors.green,
      };

  IconData get icono => switch (this) {
        EstadoStock.agotado => Icons.cancel,
        EstadoStock.bajo => Icons.warning_amber,
        EstadoStock.disponible => Icons.check_circle,
      };
}
