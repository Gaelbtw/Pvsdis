import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Los atajos de teclado del punto de venta, listados.
///
/// Existen ocho atajos y hasta ahora solo uno se anunciaba en pantalla (el F4
/// impreso en el botón de cobrar): quien no estuvo el día que se explicaron
/// trabajaba con el mouse. Se abre con F1, que es donde la gente ya busca
/// ayuda.
Future<void> mostrarAtajosDialog(BuildContext context) {
  const atajos = <(String, String)>[
    ('F1', 'Ver esta lista'),
    ('F2', 'Ir al buscador'),
    ('F3', 'Asignar o cambiar el cliente'),
    ('F4', 'Cobrar la venta'),
    ('F7', 'Poner la venta en espera'),
    ('F8', 'Ver las ventas en espera'),
    ('F9', 'Reimprimir el último ticket'),
    ('↑ ↓', 'Moverse entre las líneas del carrito'),
    ('Supr', 'Quitar la línea seleccionada'),
    ('Shift + Supr', 'Vaciar el carrito'),
    ('Esc', 'Limpiar el buscador y la selección'),
    ('12 * código', 'Escanear doce piezas de un mismo producto'),
  ];

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Atajos de teclado'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sirven para cobrar sin soltar el teclado ni el lector.',
              style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            for (final (tecla, accion) in atajos)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(minWidth: 96),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        tecla,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: AppText.caption,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(accion, style: const TextStyle(fontSize: AppText.small)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
