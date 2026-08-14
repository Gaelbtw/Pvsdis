import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/cliente_model.dart';

/// Qué eligió el cajero en el buscador de clientes.
class SeleccionCliente {
  /// El cliente elegido, o `null` si escogió "Consumidor final".
  final Cliente? cliente;

  const SeleccionCliente(this.cliente);
}

/// Buscador rápido de clientes para asignarle uno a la venta en curso.
///
/// Hasta ahora el cliente solo podía llegar desde la pantalla de Clientes (se
/// pasaba por constructor a `VentasView`): si el cajero ya había empezado a
/// cobrar y el cliente pedía que se registrara a su nombre —para su crédito, su
/// historial o una factura posterior—, había que cancelar la venta y volver a
/// empezar desde el otro módulo.
///
/// Devuelve `null` si se cerró sin elegir (no cambiar nada), o una
/// [SeleccionCliente] que puede traer el cliente o `null` para quitarlo.
Future<SeleccionCliente?> mostrarSeleccionarClienteDialog(
  BuildContext context, {
  required Future<List<Cliente>> Function() cargarClientes,
  Cliente? actual,
}) {
  return showDialog<SeleccionCliente>(
    context: context,
    builder: (_) => _SeleccionarClienteDialog(
      cargarClientes: cargarClientes,
      actual: actual,
    ),
  );
}

class _SeleccionarClienteDialog extends StatefulWidget {
  final Future<List<Cliente>> Function() cargarClientes;
  final Cliente? actual;

  const _SeleccionarClienteDialog({
    required this.cargarClientes,
    this.actual,
  });

  @override
  State<_SeleccionarClienteDialog> createState() => _SeleccionarClienteDialogState();
}

class _SeleccionarClienteDialogState extends State<_SeleccionarClienteDialog> {
  final _busquedaCtrl = TextEditingController();

  List<Cliente> _todos = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final clientes = await widget.cargarClientes();
    if (!mounted) return;
    setState(() {
      _todos = clientes;
      _cargando = false;
    });
  }

  /// El filtro es en memoria y no una consulta por tecla: el catálogo de
  /// clientes de un negocio cabe de sobra en memoria, y una consulta por
  /// pulsación haría parpadear la lista justo cuando hay alguien esperando en
  /// la caja.
  List<Cliente> get _filtrados {
    final consulta = _busquedaCtrl.text.trim().toLowerCase();
    if (consulta.isEmpty) return _todos;

    return _todos.where((c) {
      return c.nombre.toLowerCase().contains(consulta) ||
          (c.telefono?.toLowerCase().contains(consulta) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return AlertDialog(
      title: const Text('Cliente de la venta'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _busquedaCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o teléfono...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.surfaceAlt,
                child: Icon(Icons.person_outline, color: AppColors.textSecondary),
              ),
              title: const Text('Consumidor final'),
              subtitle: const Text('Venta sin cliente asignado'),
              selected: widget.actual == null,
              onTap: () => Navigator.pop(context, const SeleccionCliente(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : filtrados.isEmpty
                      ? const Center(child: Text('Ningún cliente coincide.'))
                      : ListView.separated(
                          itemCount: filtrados.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final cliente = filtrados[i];
                            final esActual = cliente.idCliente == widget.actual?.idCliente;

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryLighter,
                                child: Text(
                                  cliente.nombre.isEmpty
                                      ? '?'
                                      : cliente.nombre.characters.first.toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDarker,
                                  ),
                                ),
                              ),
                              title: Text(cliente.nombre),
                              subtitle: cliente.telefono == null || cliente.telefono!.isEmpty
                                  ? null
                                  : Text(cliente.telefono!),
                              trailing: esActual
                                  ? const Icon(Icons.check_circle, color: AppColors.success)
                                  : null,
                              onTap: () => Navigator.pop(context, SeleccionCliente(cliente)),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
