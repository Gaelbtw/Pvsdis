import 'package:flutter/material.dart';
import '../controllers/auth_controller.dart';
import '../core/session/session_manager.dart';
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

  final user = await authController.login(
    usuarioController.text.trim(),
    passwordController.text.trim(),
  );

  if (!mounted) return;

  setState(() => loading = false);

  if (user == null) {

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

  } else if (user.isEmpty) {

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

  } else {
    SessionManager.setUser(
      id: user['id_usuario'] as int?,
      nombre: user['nombre']?.toString() ?? 'Admin',
      rol: user['rol']?.toString() ?? 'Administrador',
    );

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
              builder: (_) => HomeView(
                rol: user['rol'],
              ),
            ),
          );
        },
      ),
    );
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
      backgroundColor: const Color(0xFFF5F6FA),
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
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              
                  Container(
                    height: 90,
                    width: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2C500).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 50,
                      color: Color(0xFFD9A600),
                    ),
                  ),

                  const SizedBox(height: 24),

                  
                  const Text(
                    "Punto de Venta",
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    "Inicia sesión para continuar",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
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
                      fillColor: const Color(0xFFF8F9FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
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
                      fillColor: const Color(0xFFF8F9FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
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
                        backgroundColor: const Color(0xFFF2C500),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "Sistema administrativo",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
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