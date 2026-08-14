import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/app_info.dart';
import 'core/config/backend_config.dart';
import 'core/database/database_helper.dart';
import 'core/database/db_exceptions.dart';
import 'core/licencia/licencia_service.dart';
import 'core/security/login_throttle.dart';
import 'core/security/throttle_archivo_store.dart';
import 'core/sync/auth_service.dart';
import 'core/sync/network/sync_prefs_store.dart';
import 'core/sync/sync_scheduler.dart';
import 'core/theme/app_theme.dart';
import 'views/error_arranque_view.dart';
import 'views/login_view.dart';
import 'views/setup_admin_view.dart';
import 'widgets/barra_ventana.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La versión se lee antes que nada para que, si el arranque falla, la
  // pantalla de error ya pueda decir de qué versión se trata: es el primer
  // dato que hace falta para diagnosticar por teléfono.
  await AppInfo.cargar();

  // Abrir la base es el único paso del arranque que puede fallar de forma
  // irrecuperable. Si el archivo viene de una versión más nueva, se aborta
  // aquí: seguir adelante corrompería datos del negocio.
  try {
    await DatabaseHelper().database;
  } on BaseDeDatosMasNuevaException catch (e) {
    await _arrancarPantallaDeError(
      titulo: 'No se pudo abrir el sistema',
      mensaje: e.mensajeParaElUsuario,
      detalle: 'Esquema del archivo : v${e.versionArchivo}\n'
          'Esquema de esta app : v${e.versionApp}\n'
          'Versión instalada   : ${AppInfo.versionCompleta}\n'
          'Archivo             : ${e.rutaArchivo}',
    );
    return;
  }

  await AppConfig.cargar();

  // Evalúa la licencia una vez al arrancar. Nunca lanza y nunca bloquea el
  // arranque: sin licencia --que es el estado de todos los clientes hasta que
  // se compile una clave pública-- reporta `sinLicencia` y todo funciona igual
  // que siempre.
  await LicenciaService.instancia.cargar();

  // Restaura el contador de intentos fallidos de login. Sin esto vivía solo
  // en memoria y bastaba cerrar y reabrir el .exe para ponerlo a cero, así
  // que la escalada de espera no frenaba un ataque por fuerza bruta contra un
  // PIN de 4 dígitos. Los contadores caducan solos (ver
  // `LoginThrottle.ventanaFallos`), así que un corte de luz no deja la caja
  // bloqueada.
  await LoginThrottle.instancia.cargar(ThrottleArchivoStore());

  await _inicializarSync();
  // Arranca el ciclo automático de sync (corrida inmediata + cada 2 min). No
  // se hace `await`: no debe demorar el arranque de la UI, y el motor ya
  // maneja internamente el caso sin sesión/sin conexión (no-op barato).
  SyncScheduler.instancia.iniciar();

  // Ventana sin barra de título nativa: se oculta la barra de Windows (la que
  // decía "Pv Control") y la app dibuja sus propios controles (ver
  // [BarraVentana], montada desde MaterialApp.builder).
  await windowManager.ensureInitialized();
  const opcionesVentana = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(940, 620),
    center: true,
    title: 'Punto de Venta',
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(opcionesVentana, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

/// Muestra [ErrorArranqueApp] en una ventana chica y CON barra de título
/// nativa.
///
/// La barra propia ([BarraVentana]) no se usa aquí a propósito: vive dentro de
/// `MyApp` y depende del color de marca que se guarda en la base de datos —la
/// misma que acaba de fallar. Con la barra nativa, el usuario siempre puede
/// mover o cerrar la ventana aunque todo lo demás esté roto.
Future<void> _arrancarPantallaDeError({
  required String titulo,
  required String mensaje,
  String? detalle,
}) async {
  await windowManager.ensureInitialized();
  const opciones = WindowOptions(
    size: Size(760, 660),
    center: true,
    title: 'Pv Control',
  );
  windowManager.waitUntilReadyToShow(opciones, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(ErrorArranqueApp(titulo: titulo, mensaje: mensaje, detalle: detalle));
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

  // Si este dispositivo ya configuró la sincronización (guardó un servidor o
  // tiene sesión), se muestra el badge de nube en la barra superior. Si nunca
  // se activó, queda oculto (ver [SyncScheduler.configurada]).
  if (urlBackend != null || AuthService.instancia.estaAutenticado) {
    SyncScheduler.instancia.marcarConfigurada();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.actual.nombreNegocio,
      debugShowCheckedModeBanner: false,
      // Monta la barra de ventana propia por encima de todas las pantallas.
      builder: (context, child) => Column(
        children: [
          const BarraVentana(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
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
