import 'package:flutter/material.dart';

/// Paleta centralizada de la app. El color de marca (`primary`) es
/// configurable por el negocio desde Configuración; sus variantes se
/// derivan automáticamente para no tener que guardar/editar cada tono a
/// mano. Los neutros (fondo, texto) no son configurables, solo están
/// centralizados aquí para no repetirlos en cada vista.
///
/// Es un caché estático (mismo patrón que [SessionManager]) para poder
/// leerlo desde cualquier lugar, incluidos widgets sin acceso cómodo a un
/// `BuildContext` y servicios de generación de tickets que no son widgets.
class AppColors {
  AppColors._();

  static Color _primary = const Color(0xFFF2C500);

  static void actualizar(Color nuevoPrimario) {
    _primary = nuevoPrimario;
  }

  static Color get primary => _primary;

  /// Texto/ícono que va sobre [primary]: negro o blanco según el
  /// contraste, para que un color de marca oscuro siga siendo legible.
  static Color get onPrimary =>
      _primary.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

  static Color get primaryDark => _sombrear(_primary, -0.18);
  static Color get primaryDarker => _sombrear(_primary, -0.32);
  static Color get primaryLight => _aclarar(_primary, 0.72);
  static Color get primaryLighter => _aclarar(_primary, 0.85);

  // Neutros del sistema de diseño (fijos, no configurables).
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF8F6F2);
  static const surfaceAlt = Color(0xFFFCFBF9);
  static const surfaceSubtle = Color(0xFFF9FAFC);
  static const border = Color(0xFFF0EBE5);
  static const borderLight = Color(0xFFECE5DB);
  static const textPrimary = Color(0xFF2D2B28);
  static const textSecondary = Color(0xFF6E6A64);

  /// Texto de énfasis: casi tan oscuro como [textPrimary] (más oscuro que
  /// [textSecondary]), para números/etiquetas en negrita que deben resaltar.
  /// Antes se llamaba `textMuted`, un nombre que mentía: no es tenue -- para
  /// texto de verdad tenue usar [textSecondary].
  static const textStrong = Color(0xFF3C3935);

  // Colores semánticos (fijos, NO son color de marca): estado de la
  // operación, nunca deben derivarse de `primary`. Los valores igualan a
  // los `Colors.red/green/orange` que ya se usaban sueltos en varias
  // pantallas (stock, ventas canceladas, apartados, cajas, pagos), solo
  // que ahora centralizados en un único lugar.
  static const error = Color(0xFFD32F2F); // Colors.red.shade700
  static const success = Color(0xFF2E7D32); // Colors.green.shade700 (~700)
  static const warning = Color(0xFFEF6C00); // Colors.orange.shade800
  static const info = Color(0xFF2563EB); // azul informativo/de estado (NO es color de marca)
  static final disabled = Colors.grey.shade400;

  /// Sombra estándar de tarjeta, repetida antes como
  /// `BoxShadow(color: Color(0x11000000), ...)` en más de una decena de
  /// pantallas.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x11000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  static Color _sombrear(Color color, double cantidad) {
    final hsl = HSLColor.fromColor(color);
    final l = (hsl.lightness + cantidad).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  static Color _aclarar(Color color, double cantidad) {
    return Color.lerp(color, Colors.white, cantidad) ?? color;
  }
}

/// Escala tipográfica centralizada (tamaños en px), para reemplazar los ~17
/// `fontSize:` sueltos que había repartidos por las vistas. Los tamaños
/// dominantes se conservan; los outliers poco usados se acercaron al paso más
/// cercano (9,10→overline; 14→small; 17→bodyLg; 26→heading; 30,32→display).
/// Solo cubre las PANTALLAS -- los tickets PDF (`lib/services`) tienen su
/// propia tipografía de impresión y no usan esta escala.
class AppText {
  AppText._();

  static const double overline = 11; // 9, 10, 11
  static const double caption = 12; // 12
  static const double small = 13; // 13, 14
  static const double body = 15; // 15
  static const double bodyLg = 16; // 16, 17
  static const double subtitle = 18; // 18
  static const double title = 20; // 20
  static const double titleLg = 22; // 22
  static const double heading = 24; // 24, 26
  static const double display = 28; // 28, 30, 32
}

/// Radios de borde centralizados, para reemplazar los ~10 valores sueltos de
/// `BorderRadius.circular(N)`. Cuatro pasos: chico, medio, grande y píldora.
class AppRadius {
  AppRadius._();

  static const double sm = 12; // 8, 10, 12
  static const double md = 16; // 14, 16, 18
  static const double lg = 20; // 20, 22, 24
  static const double pill = 28; // 28
}
