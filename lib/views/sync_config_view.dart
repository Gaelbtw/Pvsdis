import 'package:flutter/material.dart';

import '../core/config/backend_config.dart';
import '../core/sync/auth_service.dart';
import '../core/sync/models/sync_auth_models.dart';
import '../core/sync/network/api_exceptions.dart';
import '../core/sync/network/conectividad_probe.dart';
import '../core/sync/network/sync_prefs_store.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';
import 'sync_problemas_view.dart';

/// Configuración de la sesión de sincronización con la nube (backend EsqPos):
/// a qué backend apunta este dispositivo y con qué cuenta del negocio inicia
/// sesión. Es el interruptor general del sync -- sin una sesión iniciada aquí,
/// el dispositivo sigue vendiendo 100% offline pero nada se sube a la nube.
///
/// Opera sobre `AuthService.instancia` (la misma sesión compartida que leen
/// los controladores al encolar cambios) y persiste la URL con
/// [SyncPrefsStore] para que sobreviva reinicios. Vive bajo Configuración, ya
/// gated a rol Admin.
class SyncConfigView extends StatefulWidget {
  const SyncConfigView({super.key});

  @override
  State<SyncConfigView> createState() => _SyncConfigViewState();
}

class _SyncConfigViewState extends State<SyncConfigView> {
  final _urlCtrl = TextEditingController(text: BackendConfig.baseUrl);
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _prefs = SyncPrefsStore();
  final _probe = ConectividadProbe();

  bool _guardandoUrl = false;
  bool _probando = false;
  bool _iniciandoSesion = false;
  bool _ocultarPassword = true;

  SesionSync? get _sesion => AuthService.instancia.sesionActual;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      await _aviso('URL vacía', 'Escribe la dirección del backend antes de guardar.', esError: true);
      return;
    }

    setState(() => _guardandoUrl = true);
    BackendConfig.actualizar(url);
    await _prefs.guardarUrlBackend(BackendConfig.baseUrl);
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = BackendConfig.baseUrl; // refleja la URL ya normalizada
      _guardandoUrl = false;
    });
    await _aviso('URL guardada', 'Este dispositivo apuntará a:\n${BackendConfig.baseUrl}');
  }

  Future<void> _probarConexion() async {
    // Guarda la URL primero para que la prueba use exactamente lo que el
    // usuario ve en el campo, no una versión anterior.
    BackendConfig.actualizar(_urlCtrl.text.trim());
    setState(() => _probando = true);
    final hay = await _probe.hayConexion();
    if (!mounted) return;
    setState(() => _probando = false);
    if (hay) {
      await _aviso('Conexión exitosa', 'El backend respondió correctamente.', esExito: true);
    } else {
      await _aviso(
        'Sin respuesta',
        'No se pudo contactar al backend en ${BackendConfig.baseUrl}. Revisa la URL y que el servidor esté encendido.',
        esError: true,
      );
    }
  }

  Future<void> _iniciarSesion() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      await _aviso('Datos incompletos', 'Escribe el correo y la contraseña.', esError: true);
      return;
    }

    // La URL vigente manda: si el usuario la cambió sin presionar "Guardar",
    // igual iniciamos sesión contra la que está en pantalla (y la persistimos,
    // porque una sesión válida implica que esa URL sirve).
    BackendConfig.actualizar(_urlCtrl.text.trim());
    await _prefs.guardarUrlBackend(BackendConfig.baseUrl);

    setState(() => _iniciandoSesion = true);
    try {
      await AuthService.instancia.login(email, password);
      if (!mounted) return;
      _passwordCtrl.clear();
      setState(() => _iniciandoSesion = false);
      await _aviso('Sesión iniciada', 'Este dispositivo ya está conectado a la nube.', esExito: true);
    } on ErrorApi catch (e) {
      if (!mounted) return;
      setState(() => _iniciandoSesion = false);
      await _aviso('No se pudo iniciar sesión', e.mensaje, esError: true);
    }
  }

  Future<void> _cerrarSesion() async {
    setState(() => _iniciandoSesion = true);
    await AuthService.instancia.logout();
    if (!mounted) return;
    setState(() => _iniciandoSesion = false);
    await _aviso('Sesión cerrada', 'Este dispositivo dejará de sincronizar hasta volver a iniciar sesión.');
  }

  Future<void> _aviso(String titulo, String mensaje, {bool esExito = false, bool esError = false}) {
    final color = esExito
        ? AppColors.success
        : esError
            ? AppColors.error
            : AppColors.primary;
    final icono = esExito
        ? Icons.check_circle_outline
        : esError
            ? Icons.error_outline
            : Icons.info_outline;
    return showDialog(
      context: context,
      builder: (_) => CustomAlert(titulo: titulo, mensaje: mensaje, icono: icono, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomHeader(titulo: 'Sincronización con la nube', mostrarVolver: true),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _seccionEstado(),
              const SizedBox(height: 20),
              _seccionBackend(),
              const SizedBox(height: 20),
              _sesion == null ? _seccionLogin() : _seccionSesionActiva(),
              const SizedBox(height: 20),
              _accesoProblemas(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta({required Widget child}) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _tituloSeccion(String titulo, String subtitulo) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitulo, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );

  Widget _seccionEstado() {
    final sesion = _sesion;
    final conectado = sesion != null;
    final color = conectado ? AppColors.success : AppColors.textSecondary;
    return _tarjeta(
      child: Row(
        children: [
          Icon(conectado ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: color, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conectado ? 'Conectado a la nube' : 'Sin conectar a la nube',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  conectado
                      ? 'Sesión activa como ${sesion.email}. Las ventas y movimientos se suben automáticamente.'
                      : 'Este dispositivo opera offline. Configura el backend e inicia sesión para sincronizar.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionBackend() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Servidor', 'Dirección del backend al que apunta este dispositivo.'),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL del backend',
              hintText: 'http://192.168.1.100:5242',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _probando ? null : _probarConexion,
                  icon: _probando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Probar conexión'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _guardandoUrl ? null : _guardarUrl,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionLogin() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Iniciar sesión', 'Usa la cuenta del negocio registrada en la nube.'),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Correo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _ocultarPassword,
            onSubmitted: (_) => _iniciarSesion(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_ocultarPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _ocultarPassword = !_ocultarPassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _iniciandoSesion ? null : _iniciarSesion,
              icon: _iniciandoSesion
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('Iniciar sesión'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionSesionActiva() {
    final sesion = _sesion!;
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _tituloSeccion('Sesión activa', 'Cuenta con la que este dispositivo sincroniza.'),
          const SizedBox(height: 16),
          _dato('Usuario', sesion.nombreCompleto),
          _dato('Correo', sesion.email),
          if (sesion.roles.isNotEmpty) _dato('Roles', sesion.roles.join(', ')),
          if (sesion.sucursalId != null) _dato('Sucursal', sesion.sucursalId!),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _iniciandoSesion ? null : _cerrarSesion,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accesoProblemas() {
    return _tarjeta(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SyncProblemasView()),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: AppColors.primaryDark, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pendientes y problemas',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('Revisa qué falta por subir y resuelve los cambios atorados.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(etiqueta,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
            Expanded(child: Text(valor, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
          ],
        ),
      );
}
