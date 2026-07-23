import 'package:flutter/material.dart';
import '../controllers/auditoria_controller.dart';
import '../controllers/auth_controller.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../views/home_view.dart';
import '../widgets/custom_alert.dart';


class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final usuarioController = TextEditingController();
  final passwordController = TextEditingController();
  final authController = Authcontroller();

  bool loading = false;
  bool ocultar = true;

void login() async {
  if (usuarioController.text.isEmpty ||
      passwordController.text.isEmpty) {

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Campos incompletos",
        mensaje: "Completa todos los campos para continuar.",
        icono: Icons.warning_amber_rounded,
        textoConfirmar: "Aceptar",

        onConfirm: () {},
      ),
    );

    return;
  }

  setState(() => loading = true);

  final resultado = await authController.login(
    usuarioController.text.trim(),
    passwordController.text.trim(),
  );

  if (!mounted) return;

  setState(() => loading = false);

  switch (resultado.status) {
    case LoginStatus.usuarioNoEncontrado:
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: "Usuario incorrecto",
          mensaje: "El usuario ingresado no existe.",
          icono: Icons.person_off_outlined,
          textoConfirmar: "Aceptar",

          onConfirm: () {},
        ),
      );
      break;

    case LoginStatus.contrasenaIncorrecta:
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: "Contraseña incorrecta",
          mensaje: "La contraseña ingresada es incorrecta.",
          icono: Icons.lock_outline,
          textoConfirmar: "Aceptar",

          onConfirm: () {},
        ),
      );
      break;

    case LoginStatus.success:
      final user = resultado.usuario!;

      SessionManager.setUser(
        id: user['id_usuario'] as int?,
        nombre: user['nombre']?.toString() ?? 'Admin',
        rol: user['rol']?.toString() ?? 'Administrador',
      );

      await AuditoriaController().registrar(
        tabla: 'Sesion',
        accion: 'LOGIN',
        descripcion: 'Inicio de sesión',
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: "Sesión iniciada",
          mensaje: "Bienvenido al sistema.",
          icono: Icons.check_circle_outline,
          textoConfirmar: "Continuar",

          onConfirm: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const HomeView(),
              ),
            );
          },
        ),
      );
      break;
  }
}

  @override
  void dispose() {
    usuarioController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
            ),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              
                  Container(
                    height: 90,
                    width: 90,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 50,
                      color: AppColors.primaryDark,
                    ),
                  ),

                  const SizedBox(height: 24),

                  
                  const Text(
                    "Punto de Venta",
                    style: TextStyle(
                      fontSize: AppText.display,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    "Inicia sesión para continuar",
                    style: TextStyle(
                      fontSize: AppText.body,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 👤 USUARIO
                  TextField(
                    controller: usuarioController,
                    decoration: InputDecoration(
                      labelText: "Usuario",
                      prefixIcon: const Icon(Icons.person_outline),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

              
                  TextField(
                    controller: passwordController,
                    obscureText: ocultar,
                    decoration: InputDecoration(
                      labelText: "Contraseña",
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          ocultar
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            ocultar = !ocultar;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: loading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Ingresar",
                              style: TextStyle(
                                fontSize: AppText.bodyLg,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "Sistema administrativo",
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppText.small,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}