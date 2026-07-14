import 'package:flutter/material.dart';
import '../models/pedidos_model.dart';

class DetallePedidoView extends StatelessWidget {
  final Pedidos pedido;

  const DetallePedidoView({super.key, required this.pedido});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Pedido #${pedido.idPedido}")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            ListTile(
              title: const Text("Cliente"),
              subtitle: Text("ID: ${pedido.idCliente}"),
            ),

            ListTile(
              title: const Text("Fecha"),
              subtitle: Text(pedido.fecha),
            ),

            ListTile(
              title: const Text("Estado"),
              subtitle: Text(pedido.estado),
            ),

            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: pedido.estado,
              items: ["pendiente", "entregado", "espera"]
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ))
                  .toList(),
              onChanged: (value) {
                // aquí luego actualizas DB
              },
              decoration: const InputDecoration(
                labelText: "Cambiar estado",
              ),
            ),
          ],
        ),
      ),
    );
  }
}