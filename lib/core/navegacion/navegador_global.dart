import 'package:flutter/material.dart';

/// Llave del `Navigator` de la app, para poder navegar desde widgets que viven
/// **por encima** de él.
///
/// Hace falta por [BarraVentana]: se monta desde `MaterialApp.builder`, que
/// recibe el `Navigator` como `child`. Su `BuildContext` está arriba, así que
/// `Navigator.of(context)` desde ahí no encuentra nada y revienta en tiempo de
/// ejecución --no al compilar, que es lo que lo vuelve una trampa.
///
/// Se usa **solo** para eso. Cualquier pantalla normal está debajo del
/// Navigator y debe seguir usando `Navigator.of(context)`: navegar por una
/// variable global desde donde no hace falta esconde de dónde salió una
/// pantalla y rompe las pruebas de widget, que montan el árbol sin esta llave.
final GlobalKey<NavigatorState> navegadorGlobal = GlobalKey<NavigatorState>();

/// Empuja [builder] usando el navegador raíz. No hace nada si todavía no hay
/// árbol montado (por ejemplo, durante el arranque).
Future<void> abrirEnNavegadorGlobal(WidgetBuilder builder) async {
  final estado = navegadorGlobal.currentState;
  if (estado == null) return;
  await estado.push(MaterialPageRoute(builder: builder));
}
