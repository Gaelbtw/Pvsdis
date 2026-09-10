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

  /// Colores de marca que el negocio puede elegir en Configuracion.
  ///
  /// Vive aqui y no en `ConfiguracionView` porque es sistema de diseno, no de
  /// una pantalla: la prueba que exige 4.5:1 de contraste entre cada color y
  /// su tinta mide ESTA lista, no una copia que se desincronizaria al primer
  /// color nuevo.
  ///
  /// El verde, el naranja y el verde azulado son un tono mas oscuros que los
  /// que habia (`#16A34A`, `#EA580C`, `#0D9488`). No fue gusto: medidos contra
  /// las dos tintas posibles llegaban a 4.28:1, 3.97:1 y 3.77:1, todos por
  /// debajo del minimo legible de 4.5:1. Un negocio que hubiera elegido
  /// cualquiera de los tres tenia botones que no se leen, con cualquier tinta,
  /// y no habia forma de arreglarlo sin cambiar el color.
  static const List<Color> paletaMarca = [
    Color(0xFFF2C500), // dorado (por omision)
    Color(0xFF2563EB), // azul
    Color(0xFF15803D), // verde
    Color(0xFFDC2626), // rojo
    Color(0xFF9333EA), // morado
    Color(0xFFC2410C), // naranja
    Color(0xFF0F766E), // verde azulado
    Color(0xFF334155), // gris azulado oscuro
    Color(0xFF1F1D1A), // negro, calido, del mismo tono que la tinta de la app
    Color(0xFFFFFFFF), // blanco
  ];

  static void actualizar(Color nuevoPrimario) {
    _primary = nuevoPrimario;
  }

  static Color get primary => _primary;

  /// Texto/ícono que va sobre [primary].
  ///
  /// Antes esto era `luminancia > 0.5 ? black87 : white`. El umbral de 0.5
  /// suena razonable y no lo es: la luminancia no es lineal con lo que el ojo
  /// percibe, y con colores de marca de tono medio elegia el lado equivocado.
  /// Ahora se calcula el contraste real contra las dos tintas y gana la que
  /// mas separa, que es la definicion que usa WCAG y la que decide si un
  /// cajero puede leer el boton de cobrar a un metro de distancia.
  static Color get onPrimary => tintaSobre(_primary);

  /// La tinta (oscura o blanca) que mejor se lee sobre [fondo].
  ///
  /// Publica porque no solo los botones la necesitan: la paloma del selector
  /// de color en Configuracion se dibujaba siempre blanca, asi que sobre una
  /// muestra clara desaparecia y no se sabia cual estaba elegido.
  static Color tintaSobre(Color fondo) =>
      contraste(textPrimary, fondo) >= contraste(Colors.white, fondo)
          ? textPrimary
          : Colors.white;

  /// Razon de contraste WCAG entre dos colores, de 1 (identicos) a 21
  /// (negro sobre blanco). El minimo legible para texto normal es 4.5.
  static double contraste(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final claro = la > lb ? la : lb;
    final oscuro = la > lb ? lb : la;
    return (claro + 0.05) / (oscuro + 0.05);
  }

  /// `true` cuando el color de marca casi no se distingue del fondo de las
  /// tarjetas, como pasa si alguien elige blanco.
  ///
  /// Sin esto, un boton lleno de color de marca sobre una tarjeta blanca es
  /// un rectangulo invisible con texto flotando encima. El borde no es adorno:
  /// es lo unico que dice donde termina el boton.
  static bool get primaryNecesitaBorde => contraste(_primary, background) < 1.5;

  /// Borde para ese caso. Se deriva del propio color de marca (no es un gris
  /// fijo) para que el boton siga viendose de la marca y no de la plantilla.
  static Color get bordePrimario => _sombrear(_primary, -0.22);

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

  /// Un solo paso por encima de [display], y con un uso concreto: el TOTAL de
  /// la venta.
  ///
  /// La escala nace de los tamaños que ya existían en las pantallas, y por eso
  /// se cortaba en 28. Pero el total es lo único que leen a la vez el cajero
  /// **y el cliente parado del otro lado del mostrador**, a más de un metro y
  /// en diagonal. Es el número que se reclama cuando no coincide con lo que la
  /// persona esperaba pagar.
  ///
  /// No usarlo para nada más: si empieza a aparecer en títulos, deja de
  /// significar "esto es lo que se cobra".
  ///
  /// El valor sale de `PanelCobro`, donde ya estaba escrito a mano con este
  /// comentario: *"Tamaño literal a propósito: es el número dominante de la
  /// pantalla, por encima de la escala tipográfica normal"*. Alguien ya había
  /// llegado a la misma conclusión; esto solo le pone nombre para que el
  /// siguiente no tenga que volver a justificarlo.
  static const double hero = 46;
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
