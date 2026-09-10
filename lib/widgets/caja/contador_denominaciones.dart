import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../models/conteo_denominaciones.dart';

/// Conteo del cajon, denominacion por denominacion.
///
/// Sustituye al campo unico de "efectivo contado". Ese campo pedia un numero
/// que el cajero calculaba fuera del sistema, con la calculadora del celular
/// y con prisa, al final de un turno de ocho horas. Aqui teclea cantidades
/// —numeros de un digito casi siempre— y la suma la hace la maquina.
///
/// El orden de los renglones es el orden en que se apilan los billetes al
/// contar, del mayor al menor. No es estetico: es que el dedo y la vista
/// vayan por el mismo camino que las manos.
///
/// Con Tab se baja de renglon y con Enter en el ultimo se cierra la caja, de
/// modo que un cierre completo no necesita tocar el mouse.
class ContadorDenominaciones extends StatefulWidget {
  const ContadorDenominaciones({
    super.key,
    required this.onCambio,
    this.onEnviar,
    this.autoenfocar = true,
  });

  /// Se dispara en cada tecla, con el conteo completo ya recalculado.
  final ValueChanged<ConteoDenominaciones> onCambio;

  /// Enter en el campo de monedas (el ultimo). Normalmente, cerrar la caja.
  final VoidCallback? onEnviar;

  final bool autoenfocar;

  @override
  State<ContadorDenominaciones> createState() => _ContadorDenominacionesState();
}

class _ContadorDenominacionesState extends State<ContadorDenominaciones> {
  late final Map<int, TextEditingController> _billetes;
  final _monedasCtrl = TextEditingController();

  ConteoDenominaciones _conteo = ConteoDenominaciones.vacio;

  @override
  void initState() {
    super.initState();
    _billetes = {
      for (final d in ConteoDenominaciones.denominaciones) d: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _billetes.values) {
      c.dispose();
    }
    _monedasCtrl.dispose();
    super.dispose();
  }

  void _recalcular() {
    var conteo = ConteoDenominaciones(
      monedas: double.tryParse(_monedasCtrl.text.replaceAll(',', '.')) ?? 0,
    );
    for (final entrada in _billetes.entries) {
      conteo = conteo.conBillete(entrada.key, int.tryParse(entrada.value.text) ?? 0);
    }
    setState(() => _conteo = conteo);
    widget.onCambio(conteo);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < ConteoDenominaciones.denominaciones.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _renglonBillete(ConteoDenominaciones.denominaciones[i], primero: i == 0),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 12),
        _renglonMonedas(),
      ],
    );
  }

  Widget _renglonBillete(int denominacion, {required bool primero}) {
    final cantidad = _conteo.cantidadDe(denominacion);

    return Row(
      children: [
        _etiqueta('${AppConfig.actual.simboloMoneda}$denominacion'),
        const SizedBox(width: 10),
        _campo(
          controller: _billetes[denominacion]!,
          autoenfocar: primero && widget.autoenfocar,
          ancho: 64,
          alineacion: TextAlign.center,
          soloEnteros: true,
          accion: TextInputAction.next,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            cantidad == 0 ? '—' : AppConfig.formatoMoneda(_conteo.subtotalDe(denominacion)),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: AppText.body,
              fontWeight: cantidad == 0 ? FontWeight.w400 : FontWeight.w700,
              color: cantidad == 0 ? AppColors.textSecondary : AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _renglonMonedas() {
    return Row(
      children: [
        _etiqueta('Monedas', pequena: true),
        const SizedBox(width: 10),
        _campo(
          controller: _monedasCtrl,
          autoenfocar: false,
          ancho: 110,
          alineacion: TextAlign.right,
          soloEnteros: false,
          accion: TextInputAction.done,
          prefijo: AppConfig.actual.simboloMoneda,
          onEnviar: widget.onEnviar,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'al bulto, sin separar',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: AppText.small, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _etiqueta(String texto, {bool pequena = false}) {
    return Container(
      width: 74,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: pequena ? AppText.small : AppText.body,
          fontWeight: FontWeight.w800,
          color: AppColors.textStrong,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required bool autoenfocar,
    required double ancho,
    required TextAlign alineacion,
    required bool soloEnteros,
    required TextInputAction accion,
    String? prefijo,
    VoidCallback? onEnviar,
  }) {
    return SizedBox(
      width: ancho,
      height: 38,
      child: TextField(
        controller: controller,
        autofocus: autoenfocar,
        textAlign: alineacion,
        textInputAction: accion,
        keyboardType: soloEnteros
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          if (soloEnteros)
            FilteringTextInputFormatter.digitsOnly
          else
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        onChanged: (_) => _recalcular(),
        onSubmitted: onEnviar == null ? null : (_) => onEnviar(),
        style: const TextStyle(
          fontSize: AppText.bodyLg,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        decoration: InputDecoration(
          // Sin esto el campo reserva el alto de Material y desborda los 38px.
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          prefixText: prefijo,
          prefixStyle: const TextStyle(
            fontSize: AppText.body,
            color: AppColors.textSecondary,
          ),
          filled: true,
          fillColor: AppColors.background,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
