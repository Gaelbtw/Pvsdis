import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/pagos_mixtos.dart';

class _FilaPago {
  String metodoPago;
  final TextEditingController controller;

  _FilaPago({required this.metodoPago, String montoInicial = ''})
      : controller = TextEditingController(text: montoInicial);
}

/// Sección inline (no modal, para no restarle velocidad al cajero) donde se
/// captura uno o varios pagos que en conjunto deben cubrir el total de la
/// venta. Precarga una fila de Efectivo con el total (el caso más común) y
/// la mantiene sincronizada mientras el cajero no haya tocado nada; en
/// cuanto edita algo, deja de "seguir" el total automáticamente para no
/// pisar lo que ya escribió.
class PagosMixtosSection extends StatefulWidget {
  final double total;
  final void Function(List<Map<String, dynamic>> pagos, ResultadoValidacionPagos resultado) onCambio;

  const PagosMixtosSection({
    super.key,
    required this.total,
    required this.onCambio,
  });

  @override
  State<PagosMixtosSection> createState() => _PagosMixtosSectionState();
}

class _PagosMixtosSectionState extends State<PagosMixtosSection> {
  final List<_FilaPago> _filas = [];
  bool _autoSync = true;

  @override
  void initState() {
    super.initState();
    _filas.add(_FilaPago(
      metodoPago: metodosPagoDisponibles.first,
      montoInicial: _formatoInicial(widget.total),
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
  }

  @override
  void didUpdateWidget(covariant PagosMixtosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoSync && _filas.length == 1 && oldWidget.total != widget.total) {
      _filas.first.controller.text = _formatoInicial(widget.total);
      WidgetsBinding.instance.addPostFrameCallback((_) => _notificar());
    }
  }

  @override
  void dispose() {
    for (final fila in _filas) {
      fila.controller.dispose();
    }
    super.dispose();
  }

  String _formatoInicial(double valor) => valor > 0 ? valor.toStringAsFixed(2) : '';

  List<Map<String, dynamic>> get _pagosActuales => _filas
      .map((f) => {
            'metodo_pago': f.metodoPago,
            'monto': double.tryParse(f.controller.text.replaceAll(',', '.')) ?? 0,
          })
      .toList();

  List<PagoIngresado> get _pagosIngresados => _pagosActuales
      .map((p) => PagoIngresado(metodoPago: p['metodo_pago'] as String, monto: p['monto'] as double))
      .toList();

  ResultadoValidacionPagos get _resultado =>
      validarPagosMixtos(total: widget.total, pagos: _pagosIngresados);

  void _notificar() {
    if (!mounted) return;
    widget.onCambio(_pagosActuales, _resultado);
  }

  List<String> _metodosDisponiblesPara(_FilaPago actual) {
    final usados = _filas.where((f) => f != actual).map((f) => f.metodoPago).toSet();
    return metodosPagoDisponibles.where((m) => m == actual.metodoPago || !usados.contains(m)).toList();
  }

  void _agregarFila() {
    final usados = _filas.map((f) => f.metodoPago).toSet();
    final disponibles = metodosPagoDisponibles.where((m) => !usados.contains(m)).toList();
    if (disponibles.isEmpty) return;

    setState(() {
      _autoSync = false;
      _filas.add(_FilaPago(metodoPago: disponibles.first));
    });
    _notificar();
  }

  void _eliminarFila(_FilaPago fila) {
    setState(() {
      _autoSync = false;
      fila.controller.dispose();
      _filas.remove(fila);
    });
    _notificar();
  }

  @override
  Widget build(BuildContext context) {
    final resultado = _resultado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Pagos",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ..._filas.map(
          (fila) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<String>(
                    value: fila.metodoPago,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: _metodosDisponiblesPara(fila)
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (valor) {
                      if (valor == null) return;
                      setState(() {
                        _autoSync = false;
                        fila.metodoPago = valor;
                      });
                      _notificar();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: fila.controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "\$0.00",
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) {
                      _autoSync = false;
                      setState(() {});
                      _notificar();
                    },
                  ),
                ),
                if (_filas.length > 1) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _eliminarFila(fila),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_filas.length < metodosPagoDisponibles.length)
          TextButton.icon(
            onPressed: _agregarFila,
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Agregar método"),
          ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: resultado.esValido ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _filaResumen("Total", widget.total),
              _filaResumen("Pagado", resultado.totalPagado),
              if (resultado.restante > 0) _filaResumen("Restante", resultado.restante, color: AppColors.error),
              if (resultado.cambio > 0)
                _filaResumen("Cambio", resultado.cambio, color: AppColors.success),
              if (!resultado.esValido && resultado.mensajeError != null) ...[
                const SizedBox(height: 6),
                Text(
                  resultado.mensajeError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filaResumen(String etiqueta, double valor, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: TextStyle(color: color ?? Colors.black87)),
          Text(
            "\$${valor.toStringAsFixed(2)}",
            style: TextStyle(fontWeight: FontWeight.bold, color: color ?? Colors.black87),
          ),
        ],
      ),
    );
  }
}
