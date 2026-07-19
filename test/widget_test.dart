// Smoke test de arranque de la app real, reemplazando el contador de
// ejemplo que dejaba `flutter create` (esta app no tiene ningún contador).
//
// Pumpea directamente las dos pantallas reales entre las que decide
// `_AppEntryPoint` (instalación nueva sin usuarios -> SetupAdminView; ya
// existe un usuario -> LoginView) y confirma que cada una renderiza sin
// lanzar. No se pasa por `MyApp`/`_AppEntryPoint` con su `FutureBuilder`
// sobre una consulta real a la base de datos: dentro de `testWidgets`,
// mezclar esa espera asíncrona real con el reloj falso de
// `AutomatedTestWidgetsFlutterBinding` resultó frágil (colgó
// `pumpAndSettle`/`runAsync` de forma intermitente). Pumpear la pantalla
// concreta es el patrón estándar y no depende de esa mecánica.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pvapp/views/login_view.dart';
import 'package:pvapp/views/setup_admin_view.dart';

void main() {
  testWidgets('SetupAdminView (instalación nueva) renderiza sus campos y botón principal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetupAdminView()));
    await tester.pump();

    expect(find.text('Configuración inicial'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Crear cuenta de administrador'), findsOneWidget);
  });

  testWidgets('LoginView renderiza sus campos y botón de ingreso', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginView()));
    await tester.pump();

    expect(find.text('Punto de Venta'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2)); // usuario + contraseña
    expect(find.widgetWithText(ElevatedButton, 'Ingresar'), findsOneWidget);
  });
}
