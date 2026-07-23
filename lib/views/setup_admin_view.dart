import 'package:flutter/material.dart';

import '../controllers/usuarios_controller.dart';
import '../core/security/password_hasher.dart';
import '../core/theme/app_colors.dart';
import '../models/usuarios_model.dart';
import '../widgets/custom_alert.dart';
import 'login_view.dart';

/// Pantalla de primer arranque: crea la cuenta de administrador cuando la
/// instalación todavía no tiene ningún usuario, en vez de depender de una
/// credencial sembrada de fábrica.
class SetupAdminView extends StatefulWidget {
  const SetupAdminView({super.key});

  @override
  State<SetupAdminView> createState() => _SetupAdminViewState();
}

class _SetupAdminViewState extends State<SetupAdminView> {
  final _nombreController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmarController = TextEditingController();
  final _usuariosController = UsuariosController();

  bool _guardando = false;
  bool _ocultarPassword = true;

  void _mostrarAviso(String titulo, String mensaje, IconData icono) {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: titulo,
        mensaje: mensaje,
        icono: icono,
        textoConfirmar: "Aceptar",
        onConfirm: () {},
      ),
    );
  }

  Future<void> _crearAdministrador() async {
    final nombre = _nombreController.text.trim();
    final password = _passwordController.text;
    final confirmar = _confirmarController.text;

    if (nombre.isEmpty || password.isEmpty || confirmar.isEmpty) {
      _mostrarAviso(
        "Campos incompletos",
        "Completa todos los campos para continuar.",
        Icons.warning_amber_rounded,
      );
      return;
    }

    final errorPolitica = PasswordHasher.validate(password);
    if (errorPolitica != null) {
      _mostrarAviso("Contraseña débil", errorPolitica, Icons.lock_outline);
      return;
    }

    if (password != confirmar) {
      _mostrarAviso(
        "Las contraseñas no coinciden",
        "Verifica que ambos campos de contraseña sean iguales.",
        Icons.lock_outline,
      );
      return;
    }

    setState(() => _guardando = true);

    await _usuariosController.insertar(
      Usuarios(
        idUsuario: null,
        nombre: nombre,
        contra: password,
        rol: "Admin",
      ),
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Cuenta creada",
        mensaje:
            "La cuenta de administrador se creó correctamente. Ahora inicia sesión para continuar.",
        icono: Icons.check_circle_outline,
        textoConfirmar: "Continuar",
        onConfirm: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginView()),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _passwordController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
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
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 50,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Configuración inicial",
                    style: TextStyle(
                      fontSize: AppText.heading,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Crea la cuenta de administrador para empezar a usar el sistema.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _nombreController,
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
                    controller: _passwordController,
                    obscureText: _ocultarPassword,
                    decoration: InputDecoration(
                      labelText: "Contraseña",
                      helperText:
                          "Mínimo ${PasswordHasher.minLength} caracteres",
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _ocultarPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          setState(() => _ocultarPassword = !_ocultarPassword);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _confirmarController,
                    obscureText: _ocultarPassword,
                    decoration: InputDecoration(
                      labelText: "Confirmar contraseña",
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: AppColors.surfaceSubtle,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _crearAdministrador,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: _guardando
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Crear cuenta de administrador",
                              style: TextStyle(
                                fontSize: AppText.bodyLg,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
