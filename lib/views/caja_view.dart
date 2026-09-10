import 'package:flutter/material.dart';

import '../core/utils/mensaje_error.dart';
import '../widgets/estado_vista.dart';

import '../controllers/caja_controller.dart';
import '../core/config/app_config.dart';
import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/caja_model.dart';
import '../models/conteo_denominaciones.dart';
import '../models/vista_corte.dart';
import '../services/ticket_cierre_caja_service.dart';
import '../services/ticket_corte_x_service.dart';
import '../services/impresion_service.dart';
import '../services/cajon_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/caja/contador_denominaciones.dart';
import '../widgets/caja/ledger_efectivo.dart';
import '../widgets/caja/panel_no_efectivo.dart';
import '../widgets/custom_alert.dart';
import '../widgets/form_dialog.dart';
import '../widgets/nav_bar.dart';
import '../widgets/toast.dart';
import 'historial_cajas_view.dart';

/// Lo que quedó de un cierre, para poder mostrarlo y reimprimirlo sin volver
/// a consultar la base: los valores ya se congelaron y no van a cambiar.
class _CierreHecho {
  const _CierreHecho({
    required this.caja,
    required this.resumen,
    required this.conteo,
    required this.contado,
    required this.diferencia,
  });

  final Caja caja;
  final ResumenCaja resumen;
  final ConteoDenominaciones conteo;
  final double contado;
  final double diferencia;

  String get fechaCierre => caja.fechaCierre ?? DateTime.now().toIso8601String();
}

/// Pantalla única de Caja. Tiene tres estados: sin caja abierta (formulario de
/// apertura), turno en curso (resumen + conteo + cierre) y cierre recién
/// hecho (el resultado del arqueo).
///
/// El tercero antes no existía: el resultado se mostraba en un diálogo con un
/// botón de "Entendido". Se cerraba y se perdía, y el cajero que quería volver
/// a ver cuánto le faltó ya no podía. Ahora el resultado ES la pantalla, y de
/// ahí se sale cuando se decide salir.
class CajaView extends StatefulWidget {
  const CajaView({super.key});

  @override
  State<CajaView> createState() => _CajaViewState();
}

class _CajaViewState extends State<CajaView> {
  final _cajaController = CajaController();

  bool cargando = true;


  /// Mensaje del último fallo al cargar, o `null`. Con esto la pantalla

  /// puede decir qué pasó y ofrecer reintentar, en vez de dejar la rueda

  /// girando para siempre.

  String? _errorCarga;
  Caja? cajaAbierta;
  ResumenCaja? resumen;
  ConteoDenominaciones conteo = ConteoDenominaciones.vacio;
  _CierreHecho? cierre;

  /// Arqueo ciego: quien cuenta el dinero no debe saber cuánto "debería"
  /// haber hasta después de haber declarado su conteo.
  ///
  /// Se aplica solo al cajero. El administrador es quien audita, no el
  /// auditado, y necesita el dato para operar. Mismo criterio que usa
  /// `VentasView.esCajero` para la política de descuentos.
  ///
  /// **Qué se oculta exactamente vive en [VistaCorte]**, no aquí: la regla es
  /// "todo sumando del efectivo esperado" y tiene una prueba que la sostiene.
  bool get arqueoCiego => SessionManager.isCajero;

  VistaCorte? get vista =>
      resumen == null ? null : VistaCorte(resumen: resumen!, aCiegas: arqueoCiego);

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    if (mounted) setState(() => _errorCarga = null);
    try {
      setState(() => cargando = true);

      // Sin sesión no hay caja que buscar. Antes se consultaba con el id 1,
      // así que se mostraba la caja de otro usuario.
      final idUsuario = SessionManager.currentUserId;
      final caja =
          idUsuario == null ? null : await _cajaController.obtenerCajaAbierta(idUsuario);

      ResumenCaja? nuevoResumen;
      if (caja != null) {
        nuevoResumen = await _cajaController.calcularResumenCaja(caja.idCaja!);
      }

      if (!mounted) return;
      setState(() {
        cajaAbierta = caja;
        resumen = nuevoResumen;
        conteo = ConteoDenominaciones.vacio;
        cierre = null;
        cargando = false;
      });
    } catch (e) {
      // Sin esto la bandera nunca se apagaba y la rueda giraba para
      // siempre: el error solo llegaba a la consola.
      if (!mounted) return;
      setState(() {
        cargando = false;
        _errorCarga = mensajeDeError(e);
      });
    }
  }

  double get contado => conteo.total;

  double get diferencia => resumen == null ? 0 : contado - resumen!.efectivoEsperado;

  // ------------------------------------------------------------- apertura

  void abrirCajaDialog() {
    final fondoCtrl =
        TextEditingController(text: AppConfig.actual.fondoCaja.toStringAsFixed(2));
    final observacionesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: "Abrir Caja",
        subtitulo: "Registra el fondo con el que arrancas tu turno.",
        textoGuardar: "Abrir",
        campos: [
          AppTextField(
            controller: fondoCtrl,
            hint: "Fondo inicial",
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            icon: Icons.payments,
          ),
          AppTextField(
            controller: observacionesCtrl,
            hint: "Observaciones (opcional)",
            icon: Icons.notes,
            maxLines: 2,
          ),
        ],
        onGuardar: () async {
          final fondo = double.tryParse(fondoCtrl.text.replaceAll(',', '.'));
          if (fondo == null) {
            showDialog(
              context: context,
              builder: (_) => const CustomAlert(
                titulo: 'Caja',
                mensaje: 'Ingresa un fondo inicial válido.',
                icono: Icons.error_outline,
              ),
            );
            return;
          }

          Navigator.pop(context);
          await _abrirCaja(fondo, observacionesCtrl.text);
        },
      ),
    ).whenComplete(() {
      // Creados por esta función, no por un State: sin esto no se liberan
      // nunca, tampoco si el diálogo se descarta sin guardar. En un turno se
      // abren decenas de estos.
      fondoCtrl.dispose();
      observacionesCtrl.dispose();
    });
  }

  Future<void> _abrirCaja(double fondo, String observaciones) async {
    try {
      await _cajaController.abrirCaja(fondoInicial: fondo, observaciones: observaciones);
      await cargar();

      if (!mounted) return;
      Toast.exito(context, 'Caja abierta correctamente');
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo abrir la caja. $mensaje');
    }
  }

  // --------------------------------------------------------------- cierre

  void confirmarCierre() {
    final r = resumen;
    if (r == null) return;

    if (conteo.sinCapturar) {
      Toast.error(context, 'Cuenta el cajón antes de cerrar.');
      return;
    }

    // El desglose ya está a la vista en la columna del conteo, así que el
    // diálogo no lo repite: solo confirma el total y advierte que no se
    // deshace. Con arqueo ciego tampoco puede mostrar el esperado ni la
    // diferencia — sería un oráculo: abrir, leer el número, cancelar y
    // corregir el conteo.
    final piezas = conteo.piezasBilletes;
    final desglose = StringBuffer()
      ..writeln('Efectivo contado: ${AppConfig.formatoMoneda(contado)}')
      ..writeln('$piezas ${piezas == 1 ? 'billete' : 'billetes'}'
          '${conteo.monedas > 0 ? ' + monedas' : ''}');

    if (!arqueoCiego) {
      desglose
        ..writeln('Esperado: ${AppConfig.formatoMoneda(r.efectivoEsperado)}')
        ..writeln('Diferencia: ${AppConfig.formatoMoneda(diferencia)}');
    }

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Cerrar caja",
        mensaje: "$desglose\nEl conteo queda registrado y no se puede modificar.",
        icono: Icons.point_of_sale,
        textoCancelar: "Cancelar",
        textoConfirmar: "Cerrar caja",
        onConfirm: _cerrarCaja,
      ),
    );
  }

  Future<void> _cerrarCaja() async {
    final caja = cajaAbierta;
    final r = resumen;
    if (caja == null || r == null) return;

    // Se capturan ANTES de tocar el estado: después de cerrar, `conteo` y
    // `resumen` se limpian y el resultado que se mostraría sería otro.
    final conteoFinal = conteo;
    final contadoFinal = contado;
    final diferenciaFinal = diferencia;

    try {
      await _cajaController.cerrarCaja(
        idCaja: caja.idCaja!,
        efectivoContado: contadoFinal,
        conteo: conteoFinal,
      );

      final hecho = _CierreHecho(
        caja: Caja(
          idCaja: caja.idCaja,
          idUsuario: caja.idUsuario,
          fechaApertura: caja.fechaApertura,
          fechaCierre: DateTime.now().toIso8601String(),
          fondoInicial: caja.fondoInicial,
          observacionesApertura: caja.observacionesApertura,
          estado: 'Cerrada',
        ),
        resumen: r,
        conteo: conteoFinal,
        contado: contadoFinal,
        diferencia: diferenciaFinal,
      );

      if (!mounted) return;
      setState(() {
        cajaAbierta = null;
        resumen = null;
        conteo = ConteoDenominaciones.vacio;
        cierre = hecho;
      });
      Toast.exito(context, 'Caja cerrada. El cierre se registró correctamente.');
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo cerrar la caja. $mensaje');
      return;
    }

    // Imprimir y abrir el cajón van DESPUÉS y en su propio try, a propósito.
    //
    // Antes iban dentro del mismo bloque que el cierre: si la impresora estaba
    // atorada o sin papel, el cierre ya se había grabado en la base pero el
    // cajero leía "No se pudo cerrar la caja" y volvía a intentarlo. El segundo
    // intento fallaba con "Esta caja ya fue cerrada" y ahí sí no entendía nada.
    //
    // Un papel que no salió no deshace un cierre. Se dice qué falló y el botón
    // de reimprimir queda a la vista en la misma pantalla.
    try {
      await _imprimirCierre(cierre!);
      await CajonService.abrirSiCorresponde();
    } catch (_) {
      if (!mounted) return;
      Toast.error(
        context,
        'La caja quedó cerrada, pero no se pudo imprimir el corte. '
        'Usa "Reimprimir corte".',
      );
    }
  }

  Future<void> _imprimirCierre(_CierreHecho hecho) async {
    final pdf = await TicketCierreCajaService.generarCierre(
      fechaApertura: hecho.caja.fechaApertura,
      fechaCierre: hecho.fechaCierre,
      cajero: SessionManager.currentUserName,
      resumen: hecho.resumen,
      conteo: hecho.conteo,
      contado: hecho.contado,
      diferencia: hecho.diferencia,
      // El corte es una entrega de dinero entre dos personas cuando quien
      // cierra no es el dueño. Si el dueño cierra su propia caja no hay a
      // quién entregarle nada y las líneas de firma son papel tirado.
      pedirFirmas: SessionManager.isCajero,
      observacionesApertura: hecho.caja.observacionesApertura,
    );
    await ImpresionService.imprimir(pdf);
  }

  Future<void> _reimprimir() async {
    final hecho = cierre;
    if (hecho == null) return;
    try {
      await _imprimirCierre(hecho);
      if (!mounted) return;
      Toast.exito(context, 'Corte reenviado a la impresora.');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo reimprimir el corte.');
    }
  }

  // ------------------------------------------ entrada / salida manual

  void _registrarMovimientoDialog({required bool esEntrada}) {
    final montoCtrl = TextEditingController();
    final conceptoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => FormDialog(
        titulo: esEntrada ? "Registrar entrada de efectivo" : "Registrar salida de efectivo",
        subtitulo: esEntrada
            ? "Dinero que entra a la caja por un motivo ajeno a la venta."
            : "Dinero que sale de la caja (pago menor, retiro, etc.).",
        textoGuardar: "Registrar",
        campos: [
          AppTextField(
            controller: montoCtrl,
            hint: "Monto",
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            icon: Icons.payments,
          ),
          AppTextField(
            controller: conceptoCtrl,
            hint: "Motivo",
            icon: Icons.notes,
            maxLines: 2,
          ),
        ],
        onGuardar: () async {
          final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.'));
          if (monto == null || monto <= 0) {
            Toast.error(context, 'Ingresa un monto válido.');
            return;
          }
          if (conceptoCtrl.text.trim().isEmpty) {
            Toast.error(context, 'Indica el motivo del movimiento.');
            return;
          }

          Navigator.pop(context);
          await _registrarMovimiento(
              esEntrada: esEntrada, monto: monto, concepto: conceptoCtrl.text);
        },
      ),
    ).whenComplete(() {
      // Creados por esta función, no por un State: sin esto no se liberan
      // nunca, tampoco si el diálogo se descarta sin guardar. En un turno se
      // abren decenas de estos.
      montoCtrl.dispose();
      conceptoCtrl.dispose();
    });
  }

  Future<void> _registrarMovimiento({
    required bool esEntrada,
    required double monto,
    required String concepto,
  }) async {
    try {
      await _cajaController.registrarMovimientoEfectivo(
        esEntrada: esEntrada,
        monto: monto,
        concepto: concepto,
      );

      // Recalcula el resumen sin tirar el conteo ya tecleado: registrar una
      // salida a media cuenta no debe obligar a contar el cajón otra vez.
      final caja = cajaAbierta;
      if (caja != null) {
        final nuevo = await _cajaController.calcularResumenCaja(caja.idCaja!);
        if (mounted) setState(() => resumen = nuevo);
      }

      if (!mounted) return;
      Toast.exito(
        context,
        esEntrada ? 'Entrada de efectivo registrada.' : 'Salida de efectivo registrada.',
      );
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().replaceFirst("Exception: ", "");
      Toast.error(context, 'No se pudo registrar el movimiento. $mensaje');
    }
  }

  // ---------------------------------------- Corte X (lectura sin cerrar)

  Future<void> _corteX() async {
    final caja = cajaAbierta;
    final r = resumen;
    if (caja == null || r == null) return;

    try {
      final pdf = await TicketCorteXService.generar(
        cajero: SessionManager.currentUserName,
        fechaApertura: caja.fechaApertura,
        fechaCorte: DateTime.now().toIso8601String(),
        resumen: r,
        // Si no, imprimir un Corte X sería la puerta trasera del arqueo
        // ciego: el cajero saca el ticket, lee el esperado y captura ese
        // mismo número al cerrar.
        ocultarEfectivo: arqueoCiego,
      );
      await ImpresionService.imprimir(pdf);
      if (!mounted) return;
      Toast.exito(context, 'Corte X generado. La caja sigue abierta.');
    } catch (e) {
      if (!mounted) return;
      Toast.error(context, 'No se pudo generar el Corte X.');
    }
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final hayCierre = cierre != null;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: CustomHeader(
        titulo: hayCierre ? "Caja cerrada" : "Caja",
        mostrarVolver: true,
        extraActions: [
          IconButton(
            tooltip: "Historial de cajas",
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistorialCajasView()),
            ),
          ),
        ],
      ),
      body: (cargando || _errorCarga != null)
          ? EstadoVista(cargando: cargando, error: _errorCarga, onReintentar: cargar)
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: hayCierre
                  ? _panelCierreHecho(cierre!)
                  : cajaAbierta == null
                      ? _panelSinCaja()
                      : _panelCajaAbierta(),
            ),
    );
  }

  Widget _panelSinCaja() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.point_of_sale, size: 64, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          const Text(
            "No tienes una caja abierta",
            style: TextStyle(
                fontSize: AppText.title,
                fontWeight: FontWeight.w800,
                color: AppColors.textStrong),
          ),
          const SizedBox(height: 8),
          const Text(
            "Abre tu caja para poder registrar ventas y devoluciones.",
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          _botonPrincipal(
            icono: Icons.lock_open,
            texto: "Abrir Caja",
            onTap: abrirCajaDialog,
            ancho: 260,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------- turno en curso

  Widget _panelCajaAbierta() {
    final v = vista!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 57, child: _columnaTurno(v)),
        const SizedBox(width: 16),
        Expanded(flex: 43, child: _columnaConteo()),
      ],
    );
  }

  Widget _columnaTurno(VistaCorte v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tarjetaTurno(v),
                const SizedBox(height: 12),
                LedgerEfectivo(vista: v),
                const SizedBox(height: 12),
                PanelNoEfectivo(
                  vista: v,
                  nota: arqueoCiego
                      ? 'para cuadrar tus vouchers — no lo cuentes'
                      : 'ya está en el banco — no lo cuentes',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _accionesDelTurno(),
      ],
    );
  }

  /// Quién, qué turno, desde cuándo y cuánto lleva vendido. Es lo primero que
  /// se pregunta al comparar dos cortes del mismo día.
  Widget _tarjetaTurno(VistaCorte v) {
    final caja = cajaAbierta!;
    final turno = AppConfig.turnoDeIso(caja.fechaApertura);
    final apertura = DateTime.tryParse(caja.fechaApertura);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLighter,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.point_of_sale, size: 21, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  turno == null
                      ? SessionManager.currentUserName
                      : '${SessionManager.currentUserName} · Turno ${turno.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: AppText.bodyLg,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  _descripcionApertura(apertura),
                  style: const TextStyle(
                      fontSize: AppText.small, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _dato('TICKETS', '${v.tickets}'),
          if (v.totalVendido != null) ...[
            const SizedBox(width: 16),
            Container(width: 1, height: 34, color: AppColors.border),
            const SizedBox(width: 16),
            _dato('VENDIDO', AppConfig.formatoMoneda(v.totalVendido!)),
          ],
        ],
      ),
    );
  }

  String _descripcionApertura(DateTime? apertura) {
    if (apertura == null) return 'Abierta el ${cajaAbierta!.fechaApertura}';

    final hhmm = '${apertura.hour.toString().padLeft(2, '0')}:'
        '${apertura.minute.toString().padLeft(2, '0')}';
    final transcurrido = DateTime.now().difference(apertura);
    final horas = transcurrido.inHours;
    final minutos = transcurrido.inMinutes.remainder(60);
    final duracion =
        horas > 0 ? '$horas h ${minutos.toString().padLeft(2, '0')} min' : '$minutos min';

    return 'Abierta $hhmm · lleva $duracion';
  }

  Widget _dato(String titulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: AppText.overline,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          valor,
          style: const TextStyle(
            fontSize: AppText.heading,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Entrada, salida y Corte X: cosas que se hacen DURANTE el turno. Por eso
  /// viven al pie de la columna del turno y no junto al botón de cerrar.
  Widget _accionesDelTurno() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // Entradas/salidas manuales solo para roles con el permiso (ver
        // matriz de permisos). El Corte X de lectura queda para cualquiera
        // que tenga la caja abierta.
        if (PermisosService.instancia.puedeActual(Permiso.movimientosCaja)) ...[
          _accion(
            icono: Icons.south_west,
            texto: 'Registrar entrada',
            color: AppColors.success,
            onTap: () => _registrarMovimientoDialog(esEntrada: true),
          ),
          _accion(
            icono: Icons.north_east,
            texto: 'Registrar salida',
            color: AppColors.error,
            onTap: () => _registrarMovimientoDialog(esEntrada: false),
          ),
        ],
        _accion(
          icono: Icons.receipt_long_outlined,
          texto: 'Corte X (lectura)',
          color: AppColors.textStrong,
          onTap: _corteX,
        ),
      ],
    );
  }

  Widget _accion({
    required IconData icono,
    required String texto,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icono, size: 17),
      label: Text(texto),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: color == AppColors.textStrong
              ? AppColors.border
              : color.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: AppText.small, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  // ------------------------------------------------------ columna derecha

  Widget _columnaConteo() {
    final piezas = conteo.piezasBilletes;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuenta el cajón',
                  style: TextStyle(
                    fontSize: AppText.title,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Teclea cuántos hay de cada uno. Tab para bajar, Enter para cerrar.',
                  style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: ContadorDenominaciones(
                onCambio: (nuevo) => setState(() => conteo = nuevo),
                onEnviar: confirmarCierre,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total contado',
                        style: TextStyle(
                          fontSize: AppText.body,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        piezas == 0
                            ? 'sin capturar'
                            : '$piezas ${piezas == 1 ? 'billete' : 'billetes'}'
                                '${conteo.monedas > 0 ? ' + monedas' : ''}',
                        style: const TextStyle(
                            fontSize: AppText.caption, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  AppConfig.formatoMoneda(contado),
                  style: const TextStyle(
                    fontSize: AppText.display,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
            child: arqueoCiego ? _notaCiego() : _diferenciaEnVivo(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            child: Column(
              children: [
                _botonPrincipal(
                  icono: Icons.print_outlined,
                  texto: 'Cerrar caja e imprimir corte',
                  onTap: confirmarCierre,
                ),
                const SizedBox(height: 8),
                const Text(
                  'El cierre no se puede deshacer.',
                  style: TextStyle(fontSize: AppText.caption, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Con arqueo ciego, en lugar de la diferencia en vivo va una nota: mostrarla
  /// mientras se teclea convertía el conteo en un "adivina el número".
  Widget _notaCiego() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 17, color: AppColors.textSecondary),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Este es tu conteo. Si cuadra o no lo sabrás en la siguiente pantalla.',
              style: TextStyle(
                  fontSize: AppText.small, color: AppColors.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diferenciaEnVivo() {
    final sinContar = conteo.sinCapturar;
    final cuadra = diferencia.abs() < 0.005;
    final color = sinContar || cuadra
        ? AppColors.textSecondary
        : diferencia > 0
            ? AppColors.success
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      decoration: BoxDecoration(
        color: sinContar || cuadra
            ? AppColors.surface
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            sinContar ? 'Diferencia' : (cuadra ? 'Cuadra exacto' : 'Diferencia'),
            style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700, color: color),
          ),
          Text(
            sinContar ? '—' : AppConfig.formatoMoneda(diferencia),
            style: TextStyle(
              fontSize: AppText.title,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ cierre ya hecho

  Widget _panelCierreHecho(_CierreHecho hecho) {
    // Después de cerrar se revela TODO, incluso a quien contó a ciegas: el
    // conteo ya quedó grabado y no se puede ajustar, así que ocultarlo ahora
    // no protegería nada y sí dejaría al cajero sin saber cómo le fue.
    final v = VistaCorte(resumen: hecho.resumen, aCiegas: false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 57,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _veredicto(hecho),
                const SizedBox(height: 12),
                LedgerEfectivo(
                  vista: v,
                  titulo: 'De dónde salió el esperado',
                  notaTotal: 'esto es lo que estaba tapado mientras contabas',
                ),
                const SizedBox(height: 12),
                PanelNoEfectivo(
                  vista: v,
                  nota: '${AppConfig.formatoMoneda(v.totalNoEfectivo)} en total',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(flex: 43, child: _columnaConteoFinal(hecho)),
      ],
    );
  }

  Widget _veredicto(_CierreHecho hecho) {
    final cuadra = hecho.diferencia.abs() < 0.005;
    final sobra = hecho.diferencia > 0;
    final color = cuadra ? AppColors.success : (sobra ? AppColors.success : AppColors.error);
    final esperado = hecho.resumen.efectivoEsperado;
    final porcentaje = esperado.abs() < 0.005
        ? null
        : (hecho.diferencia.abs() / esperado.abs() * 100);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              cuadra ? Icons.check_circle_outline : Icons.error_outline,
              size: 25,
              color: color,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cuadra
                      ? 'El conteo cuadró exacto'
                      : sobra
                          ? 'Sobraron ${AppConfig.formatoMoneda(hecho.diferencia)}'
                          : 'Faltaron ${AppConfig.formatoMoneda(hecho.diferencia.abs())}',
                  style: TextStyle(
                    fontSize: AppText.title,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  cuadra || porcentaje == null
                      ? 'El conteo ya quedó registrado.'
                      : '${porcentaje.toStringAsFixed(1)} % de lo esperado · el conteo ya quedó registrado',
                  style: const TextStyle(
                      fontSize: AppText.small, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _dato('ESPERADO', AppConfig.formatoMoneda(esperado)),
          const SizedBox(width: 26),
          _dato('CONTADO', AppConfig.formatoMoneda(hecho.contado)),
        ],
      ),
    );
  }

  Widget _columnaConteoFinal(_CierreHecho hecho) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu conteo',
                  style: TextStyle(
                    fontSize: AppText.title,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Queda guardado así, tal cual lo capturaste.',
                  style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
              child: Column(
                children: [
                  for (final r in hecho.conteo.renglones)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.etiqueta,
                              style: const TextStyle(
                                  fontSize: AppText.body, color: AppColors.textSecondary),
                            ),
                          ),
                          Text(
                            AppConfig.formatoMoneda(r.importe),
                            style: const TextStyle(
                              fontSize: AppText.body,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total contado',
                          style: TextStyle(
                            fontSize: AppText.body,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        AppConfig.formatoMoneda(hecho.contado),
                        style: const TextStyle(
                          fontSize: AppText.heading,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (hecho.diferencia.abs() >= 0.005) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 17, color: AppColors.warning),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            hecho.diferencia > 0
                                ? 'Un sobrante no se corrige aquí. Se registra como salida de '
                                    'efectivo en la caja siguiente, con su motivo. Los cierres '
                                    'no se editan.'
                                : 'Un faltante no se corrige aquí. Si aparece el dinero, se '
                                    'registra como entrada de efectivo en la caja siguiente, '
                                    'con su motivo. Los cierres no se editan.',
                            style: const TextStyle(
                              fontSize: AppText.small,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            child: Column(
              children: [
                _botonPrincipal(
                  icono: Icons.print_outlined,
                  texto: 'Reimprimir corte',
                  onTap: _reimprimir,
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await cargar();
                          if (mounted) abrirCajaDialog();
                        },
                        style: _estiloSecundario(),
                        child: const Text('Abrir caja nueva'),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: _estiloSecundario(),
                        child: const Text('Ir a inicio'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- comunes

  ButtonStyle _estiloSecundario() => OutlinedButton.styleFrom(
        foregroundColor: AppColors.textStrong,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      );

  Widget _botonPrincipal({
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
    double? ancho,
  }) {
    return SizedBox(
      width: ancho,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icono, size: 19),
        label: Text(texto),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(fontSize: AppText.bodyLg, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}
