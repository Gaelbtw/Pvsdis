import 'package:flutter/material.dart';
import '../widgets/custom_alert.dart';

class AgregarProductoView extends StatelessWidget {
  const AgregarProductoView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agregar Producto")),
      body: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [

            TextField(
              decoration: const InputDecoration(
                labelText: "Nombre del producto",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              decoration: const InputDecoration(
                labelText: "Precio",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                ),
                onPressed: () {
                  showDialog (
                    context: context,
                    builder: (_) => CustomAlert(
                      titulo: "Producto agregado",
                      mensaje: "El producto ha sido agregado exitosamente.",
                      icono: Icons.check_circle_outline,
                      textoConfirmar: "Aceptar",
                      onConfirm: () {
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
                child: const Text("Guardar"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}