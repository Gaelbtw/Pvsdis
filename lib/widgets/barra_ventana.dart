import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/actualizacion/actualizacion_service.dart';
import '../core/licencia/licencia_service.dart';
import '../core/navegacion/navegador_global.dart';
import '../core/theme/app_colors.dart';
import '../views/licencia_view.dart';

/// Barra superior mínima que reemplaza la barra de título nativa de Windows
/// (la que decía "Pv Control"). Se integra con el fondo de la app: a la
/// izquierda una zona para arrastrar/mover la ventana, y a la derecha los
/// botones de minimizar, maximizar/restaurar y cerrar.
///
/// Se coloca una sola vez, por encima de todas las pantallas, desde
/// `MaterialApp.builder`.
class BarraVentana extends StatelessWidget {
  const BarraVentana({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controles(),
        const BannerLicencia(),
        const BannerActualizacion(),
      ],
    );
  }

  Widget _controles() {
    return Container(
      height: 34,
      color: AppColors.background,
      child: Row(
        children: [
          // Zona arrastrable para mover la ventana (ocupa el resto del ancho).
          Expanded(
            child: DragToMoveArea(
              child: const SizedBox.expand(),
            ),
          ),
          _BotonVentana(
            icono: Icons.remove_rounded,
            onTap: () => windowManager.minimize(),
          ),
          _BotonVentana(
            icono: Icons.crop_square_rounded,
            iconoSize: 14,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _BotonVentana(
            icono: Icons.close_rounded,
            onTap: () => windowManager.close(),
            colorHover: AppColors.error,
            colorIconoHover: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// Franja de aviso cuando la licencia venció, es de otro equipo o el archivo
/// no es válido.
///
/// Va aquí y no dentro de una pantalla porque tiene que verse **en todas**,
/// incluida la de entrada: quien decide pagar la renovación es el dueño, y no
/// siempre es quien está frente a la caja. Un aviso escondido en Configuración
/// no lo ve nadie hasta que ya está bloqueado.
///
/// No se muestra en `porVencer`: para eso está el aviso de una sola vez al
/// abrir. Una franja permanente durante quince días se vuelve parte del
/// paisaje y deja de comunicar.
class BannerLicencia extends StatelessWidget {
  const BannerLicencia({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EstadoLicencia>(
      valueListenable: LicenciaService.instancia.estadoNotificador,
      builder: (context, estado, _) {
        if (!estado.requiereBanner) return const SizedBox.shrink();

        final color =
            estado.estaDegradada ? AppColors.error : AppColors.warning;

        return Material(
          color: Color.alphaBlend(
            color.withValues(alpha: 0.10),
            AppColors.background,
          ),
          child: InkWell(
            onTap: () => abrirEnNavegadorGlobal((_) => const LicenciaView()),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: color.withValues(alpha: 0.35)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      estado.mensaje,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.small,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Ver licencia',
                    style: TextStyle(
                      fontSize: AppText.caption,
                      fontWeight: FontWeight.w800,
                      color: color,
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Aviso discreto de que hay una versión nueva publicada.
///
/// **Discreto y no modal, a propósito.** Un modal al abrir interrumpe a quien
/// llega a las 8 de la mañana a abrir la caja, y lo único que consigue es que
/// aprenda a cerrarlo sin leerlo. Esta franja se puede ignorar todo el día y
/// sigue ahí al cierre, que es cuando de verdad conviene actualizar.
///
/// Descarga y verifica el SHA256, pero **no instala nada**: correr el
/// instalador es una decisión del negocio. Regla número uno de un punto de
/// venta: una actualización nunca se aplica sola a media venta.
class BannerActualizacion extends StatefulWidget {
  const BannerActualizacion({super.key});

  @override
  State<BannerActualizacion> createState() => _BannerActualizacionState();
}

class _BannerActualizacionState extends State<BannerActualizacion> {
  bool _descargando = false;
  String? _rutaLista;
  String? _error;

  Future<void> _descargar(Actualizacion actualizacion) async {
    setState(() {
      _descargando = true;
      _error = null;
    });

    try {
      final ruta = await ActualizacionService.instancia.descargar(actualizacion);
      if (!mounted) return;
      setState(() => _rutaLista = ruta);
      // Dejar el archivo seleccionado en el Explorador: pedirle a alguien que
      // navegue a mano hasta AppData es donde se pierde media actualización.
      unawaited(Process.run('explorer', ['/select,', ruta]));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Actualizacion?>(
      valueListenable: ActualizacionService.instancia.disponible,
      builder: (context, actualizacion, _) {
        if (actualizacion == null) return const SizedBox.shrink();

        final color = _error != null ? AppColors.error : AppColors.info;

        final String texto;
        if (_error != null) {
          texto = _error!;
        } else if (_rutaLista != null) {
          texto = 'Actualización lista en la carpeta que se abrió. '
              'Ejecútala con la caja cerrada y sin ventas en curso.';
        } else {
          final notas =
              actualizacion.notas.isEmpty ? '' : '  ${actualizacion.notas}';
          final aviso = actualizacion.cambiaEsquema
              ? '  Conviene respaldar antes: esta versión actualiza la '
                  'información guardada.'
              : '';
          texto = 'Hay una versión nueva (${actualizacion.version}).$notas$aviso';
        }

        return Material(
          color: Color.alphaBlend(
            color.withValues(alpha: 0.08),
            AppColors.background,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.30)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _rutaLista != null
                      ? Icons.check_circle_outline_rounded
                      : Icons.system_update_alt_rounded,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppText.small,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (_rutaLista == null)
                  TextButton(
                    onPressed:
                        _descargando ? null : () => _descargar(actualizacion),
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      _descargando ? 'Descargando...' : 'Descargar',
                      style: const TextStyle(
                        fontSize: AppText.caption,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BotonVentana extends StatefulWidget {
  final IconData icono;
  final VoidCallback onTap;
  final double iconoSize;
  final Color? colorHover;
  final Color? colorIconoHover;

  const _BotonVentana({
    required this.icono,
    required this.onTap,
    this.iconoSize = 16,
    this.colorHover,
    this.colorIconoHover,
  });

  @override
  State<_BotonVentana> createState() => _BotonVentanaState();
}

class _BotonVentanaState extends State<_BotonVentana> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 34,
          alignment: Alignment.center,
          color: _hover ? (widget.colorHover ?? AppColors.surfaceAlt) : Colors.transparent,
          child: Icon(
            widget.icono,
            size: widget.iconoSize,
            color: _hover ? (widget.colorIconoHover ?? AppColors.textPrimary) : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
