import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Construye el [ThemeData] de la app a partir del color de marca ya
/// cargado en [AppColors]. Llamar después de [AppColors.actualizar].
class AppTheme {
  AppTheme._();

  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: ThemeData.light().textTheme.bodyMedium?.fontFamily,

      // Borde de los botones llenos, resuelto UNA vez aquí y no en cada
      // pantalla.
      //
      // Cuando el negocio elige un color de marca muy claro (blanco, por
      // ejemplo), un botón lleno sobre una tarjeta blanca es un rectángulo
      // invisible con texto flotando encima. El borde es lo único que dice
      // dónde termina el botón.
      //
      // Va en el tema porque las ~30 pantallas que arman su botón con
      // `ElevatedButton.styleFrom(...)` no definen `side`, así que este valor
      // les llega a todas sin tocar ni una. Si alguna necesitara otro borde,
      // basta con que lo declare y el suyo gana.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((_) {
            if (!AppColors.primaryNecesitaBorde) return BorderSide.none;
            return BorderSide(color: AppColors.bordePrimario);
          }),
        ),
      ),
    );
  }
}
