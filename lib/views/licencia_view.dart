import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/licencia/licencia.dart';
import '../core/licencia/licencia_service.dart';
import '../core/theme/app_colors.dart';
import '../widgets/nav_bar.dart';
import '../widgets/toast.dart';

/// Pantalla de licencia y activación.
///
/// El flujo completo son dos minutos: el cliente copia su código de
/// instalación, te lo manda por WhatsApp, tú emites el `.lic` con
/// `tool/emitir_licencia.dart` y él lo importa aquí.
///
/// El botón de copiar existe para que nadie teclee el código a mano. Un
/// carácter mal copiado produce una licencia que no sirve y una llamada de
/// soporte que empieza con "sí lo escribí bien".
class LicenciaView extends StatefulWidget {
  const LicenciaView({super.key});

  @override
  State<LicenciaView> createState() => _LicenciaViewState();
}

class _LicenciaViewState extends State<LicenciaView> {
  String? _codigo;
  EstadoLicencia _estado = LicenciaService.instancia.estado;
  bool _importando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final codigo = await LicenciaService.instancia.codigoEquipo();
    final estado = await LicenciaService.instancia.cargar();
    if (!mounted) return;
    setState(() {
      _codigo = codigo;
      _estado = estado;
    });
  }

  Future<void> _importar() async {
    final elegido = await FilePicker.pickFiles(
      dialogTitle: 'Elige tu archivo de licencia',
      // Sin filtro por extensión a propósito: WhatsApp Desktop guarda los
      // adjuntos renombrados y el archivo puede llegar como .lic.txt o sin
      // extensión. Filtrar aquí lo dejaría invisible en el diálogo.
      type: FileType.any,
    );

    final ruta = elegido?.files.single.path;
    if (ruta == null) return;

    setState(() => _importando = true);
    try {
      final estado =
          await LicenciaService.instancia.importar(await File(ruta).readAsString());
      if (!mounted) return;
      setState(() => _estado = estado);
      Toast.exito(context, 'Licencia activada.');
    } on LicenciaInvalidaException catch (e) {
      if (!mounted) return;
      _mostrarError(e.motivo);
    } catch (e) {
      if (!mounted) return;
      _mostrarError('No se pudo leer el archivo: $e');
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  void _mostrarError(String mensaje) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo activar'),
        content: SelectableText(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: CustomHeader(
        titulo: 'Licencia',
        mostrarVolver: Navigator.canPop(context),
        mostrarInfo: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tarjetaEstado(),
                const SizedBox(height: 18),
                _tarjetaCodigo(),
                const SizedBox(height: 18),
                _tarjetaImportar(),
                if (_estado.relojSospechoso) ...[
                  const SizedBox(height: 18),
                  _tarjetaReloj(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- tarjetas

  Widget _tarjetaEstado() {
    final (color, icono, titulo) = switch (_estado.situacion) {
      SituacionLicencia.vigente => (
          AppColors.success,
          Icons.verified_outlined,
          'Licencia vigente'
        ),
      SituacionLicencia.porVencer => (
          AppColors.warning,
          Icons.schedule_outlined,
          'Por vencer'
        ),
      SituacionLicencia.enGracia => (
          AppColors.warning,
          Icons.error_outline_rounded,
          'Vencida'
        ),
      SituacionLicencia.vencida => (
          AppColors.error,
          Icons.lock_outline_rounded,
          'Vencida — funciones limitadas'
        ),
      SituacionLicencia.otroEquipo => (
          AppColors.error,
          Icons.devices_other_outlined,
          'Licencia de otra computadora'
        ),
      SituacionLicencia.invalida => (
          AppColors.error,
          Icons.gpp_bad_outlined,
          'Licencia no válida'
        ),
      SituacionLicencia.sinLicencia => (
          AppColors.textSecondary,
          Icons.info_outline_rounded,
          LicenciaService.instancia.activo
              ? 'Sin licencia registrada'
              : 'Sistema sin licenciamiento'
        ),
    };

    final l = _estado.licencia;

    return _tarjeta(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: AppText.subtitle,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _estado.situacion == SituacionLicencia.sinLicencia &&
                    !LicenciaService.instancia.activo
                ? 'Esta versión no requiere licencia. Todas las funciones '
                    'están disponibles.'
                : _estado.mensaje,
            style: const TextStyle(
              fontSize: AppText.body,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          if (l != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _dato('Negocio', l.negocio),
            _dato('Edición', l.edicion.nombre),
            _dato('Cajas autorizadas', '${l.cajas}'),
            _dato('Emitida', Licencia.soloFecha(l.emitida)),
            _dato('Vence', Licencia.soloFecha(l.expira)),
            _dato('Equipo autorizado', l.huella, mono: true),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaCodigo() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CÓDIGO DE INSTALACIÓN DE ESTA COMPUTADORA',
            style: TextStyle(
              fontSize: AppText.caption,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _codigo ?? '...',
                  style: const TextStyle(
                    fontSize: AppText.heading,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _codigo == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _codigo!));
                        Toast.info(context, 'Código copiado.');
                      },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copiar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Manda este código a quien te vendió el sistema para que te emita '
            'tu licencia. Cópialo con el botón: si lo tecleas a mano y se va '
            'un carácter, la licencia que te manden no va a servir.',
            style: TextStyle(
              fontSize: AppText.small,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaImportar() {
    return _tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVAR',
            style: TextStyle(
              fontSize: AppText.caption,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Cuando recibas tu archivo .lic, guárdalo en la computadora y '
            'elígelo aquí.',
            style: TextStyle(
              fontSize: AppText.small,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _importando ? null : _importar,
              icon: _importando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_open_outlined, size: 18),
              label: Text(
                _importando ? 'Verificando...' : 'Importar archivo de licencia',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                textStyle: const TextStyle(
                  fontSize: AppText.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaReloj() => _tarjeta(
        color: AppColors.warning,
        child: const Text(
          'La fecha de esta computadora está atrasada respecto a la última que '
          'registró el sistema. No bloquea nada, pero conviene revisar la fecha '
          'y hora de Windows: con la fecha mal, los cortes de caja y los '
          'reportes por día salen mal.',
          style: TextStyle(
            fontSize: AppText.small,
            height: 1.45,
            color: AppColors.textPrimary,
          ),
        ),
      );

  // ------------------------------------------------------------ auxiliares

  Widget _tarjeta({required Widget child, Color? color}) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: color == null
              ? Border.all(color: AppColors.border)
              : Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: AppColors.cardShadow,
        ),
        child: child,
      );

  Widget _dato(String etiqueta, String valor, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: AppText.small,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: SelectableText(
                valor,
                style: TextStyle(
                  fontSize: AppText.small,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ),
          ],
        ),
      );
}
