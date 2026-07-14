import 'package:flutter/material.dart';
import 'ventas_view.dart';
import 'clientes_view.dart';
import 'compras_view.dart';
import 'proveedores_view.dart';
import '../widgets/nav_bar.dart';

class CajeroView extends StatefulWidget {
  const CajeroView({super.key});

  @override
  State<CajeroView> createState() => _CajeroViewState();
}

class _CajeroViewState extends State<CajeroView> {

  int index = 0;

  final List<Widget> pantallas = [
    const VentasView(),
    const ClientesView(),
    const ComprasView(),
    const ProveedorView(),
  ];

  final List<String> titulos = [
    "Ventas",
    "Clientes",
    "Compras",
    "Proveedores",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomHeader(
        titulo: titulos[index],
        mostrarVolver: true,
      ),
      body: pantallas[index],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) {
          setState(() {
            index = i;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: "Ventas",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: "Clientes",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: "Compras",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: "Proveedores",
          ),
        ],
      ),
    );
  }
}