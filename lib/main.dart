import 'package:flutter/material.dart';
import 'controllers/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/database/database_helper.dart';
import 'core/theme/app_theme.dart';
import 'views/login_view.dart';
import 'views/setup_admin_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database;
  await AppConfig.cargar();
  runApp(const MyApp());
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
