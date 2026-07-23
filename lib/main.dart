import 'package:flutter/material.dart';
import 'controllers/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/backend_config.dart';
import 'core/database/database_helper.dart';
import 'core/sync/auth_service.dart';
import 'core/sync/network/sync_prefs_store.dart';
import 'core/sync/sync_scheduler.dart';
import 'core/theme/app_theme.dart';
import 'views/login_view.dart';
import 'views/setup_admin_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database;
  await AppConfig.cargar();
  await _inicializarSync();
  // Arranca el ciclo automático de sync (corrida inmediata + cada 2 min). No
  // se hace `await`: no debe demorar el arranque de la UI, y el motor ya
  // maneja internamente el caso sin sesión/sin conexión (no-op barato).
  SyncScheduler.instancia.iniciar();
  runApp(const MyApp());
}

/// Deja lista la sesión de sincronización antes de arrancar la UI: (1) apunta
/// `BackendConfig` a la URL que este dispositivo tenga guardada (si nunca se
/// configuró, se queda con el default), y (2) carga a memoria la sesión de
/// sync persistida (`AuthService.inicializar`) para que sobreviva un reinicio
/// de la app. Ninguno de los dos pasos hace red ni bloquea si el backend está
/// caído -- la app puede seguir operando 100% offline como siempre.
Future<void> _inicializarSync() async {
  final urlBackend = await SyncPrefsStore().leerUrlBackend();
  if (urlBackend != null) BackendConfig.actualizar(urlBackend);
  await AuthService.instancia.inicializar();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.actual.nombreNegocio,
      debugShowCheckedModeBanner: false,
      home: const _AppEntryPoint(),
      theme: AppTheme.build(),
    );
  }
}

/// Decide la primera pantalla: si la instalación todavía no tiene ningún
/// usuario (primer arranque) exige crear la cuenta de administrador en vez
/// de sembrar una credencial por defecto; si ya existen usuarios, va al login.
class _AppEntryPoint extends StatelessWidget {
  const _AppEntryPoint();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Authcontroller().existenUsuarios(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data! ? const LoginView() : const SetupAdminView();
      },
    );
  }
}
