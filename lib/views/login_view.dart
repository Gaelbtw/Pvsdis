import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/auditoria_controller.dart';
import '../core/config/app_info.dart';
import '../controllers/auth_controller.dart';
import '../core/security/permisos_service.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../views/home_view.dart';
import '../core/security/permisos.dart';


class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final usuarioController = TextEditingController();
  final passwordController = TextEditingController();
  final pinController = TextEditingController();
  final authController = Authcontroller();

  bool loading = false;
  bool ocultar = true;
  bool modoPin = false;
  String? _error;

  void login() async {
    final usuario = usuarioController.text.trim();
    final password = passwordController.text.trim();

    if (usuario.isEmpty || password.isEmpty) {
      setState(() => _error = "Escribe tu usuario y contraseña.");
      return;
    }

    setState(() {
      loading = true;
      _error = null;
    });

    // `login` lanza cuando el throttle exige esperar (ver LoginThrottle):
    // ese mensaje sí se muestra tal cual, porque es accionable y no revela
    // nada sobre si la cuenta existe.
    final LoginResult resultado;
    try {
      resultado = await authController.login(usuario, password);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    if (!mounted) return;
    setState(() => loading = false);

    switch (resultado.status) {
      case LoginStatus.usuarioNoEncontrado:
      case LoginStatus.contrasenaIncorrecta:
        // Un solo mensaje genérico, en línea (no popup): es menos invasivo y
        // no revela si el usuario existe o no.
        setState(() => _error = "Usuario o contraseña incorrectos.");
        break;

      case LoginStatus.success:
        await _entrar(resultado.usuario!);
        break;
    }
  }

  void loginPin() async {
    final pin = pinController.text.trim();

    if (pin.isEmpty) {
      setState(() => _error = "Escribe tu PIN.");
      return;
    }

    setState(() {
      loading = true;
      _error = null;
    });

    final LoginResult resultado;
    try {
      resultado = await authController.loginConPin(pin);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
        pinController.clear();
      });
      return;
    }

    if (!mounted) return;
    setState(() => loading = false);

    if (resultado.status == LoginStatus.success) {
      await _entrar(resultado.usuario!);
    } else {
      if (!mounted) return;
      setState(() {
        _error = "PIN incorrecto.";
        pinController.clear();
      });
    }
  }

  /// Paso común tras autenticar (por contraseña o PIN): fija la sesión, carga
  /// la matriz de permisos del rol, deja registro y entra al inicio.
  Future<void> _entrar(Map<String, dynamic> user) async {
    SessionManager.setUser(
      id: user['id_usuario'] as int?,
      nombre: user['nombre']?.toString() ?? '',
      // Sin rol legible NO se asume administrador: se cae al rol de menor
      // privilegio. Antes el default era 'Administrador'.
      rol: user['rol']?.toString() ?? Roles.cajero,
    );
    await PermisosService.instancia.cargar();
    await AuditoriaController().registrar(
      tabla: 'Sesion',
      accion: 'LOGIN',
      descripcion: 'Inicio de sesión',
    );
    if (!mounted) return;
    // Directo al inicio, sin modal de "bienvenido".
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeView()));
  }

  @override
  void dispose() {
    usuarioController.dispose();
    passwordController.dispose();
    pinController.dispose();
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
                      color: AppColors.primary.withValues(alpha: 0.15),
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

                  const SizedBox(height: 32),

                  // Credenciales: usuario+contraseña, o solo PIN según el modo.
                  if (!modoPin) ...[
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
                      onSubmitted: (_) => login(),
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
                  ] else
                    // 🔢 PIN (identifica al usuario por sí solo)
                    TextField(
                      controller: pinController,
                      obscureText: ocultar,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      autofocus: true,
                      onSubmitted: (_) => loginPin(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: const TextStyle(
                        fontSize: AppText.display,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        labelText: "PIN",
                        prefixIcon: const Icon(Icons.pin_outlined),
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
                          onPressed: () => setState(() => ocultar = !ocultar),
                        ),
                      ),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: AppColors.error, fontSize: AppText.small, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: loading ? null : (modoPin ? loginPin : login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                        elevation: 0,
                        side: BorderSide(color: AppColors.primaryDark, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: loading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: AppColors.primaryDark,
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

                  const SizedBox(height: 12),

                  // Alternar entre contraseña y PIN.
                  TextButton.icon(
                    onPressed: loading
                        ? null
                        : () => setState(() {
                              modoPin = !modoPin;
                              _error = null;
                              ocultar = true;
                            }),
                    icon: Icon(modoPin ? Icons.password_outlined : Icons.pin_outlined, size: 18),
                    label: Text(modoPin ? "Entrar con usuario y contraseña" : "Entrar con PIN"),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  ),

                  // Versión visible desde la primera pantalla, sin iniciar
                  // sesión. Es el dato que se pide en cada llamada de soporte,
                  // y aquí lo puede leer cualquiera que esté frente al equipo
                  // -- incluido el cajero que no tiene acceso a Configuración.
                  const SizedBox(height: 8),
                  Text(
                    'Versión ${AppInfo.version}',
                    style: const TextStyle(
                      fontSize: AppText.caption,
                      color: AppColors.textSecondary,
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