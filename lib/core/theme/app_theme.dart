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
    );
  }
}
