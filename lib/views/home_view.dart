import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/session/session_manager.dart';
import '../widgets/menu_card.dart';
import 'auditorias_view.dart';
import 'base_datos_view.dart';
import 'clientes_view.dart';
import 'cortecaja_view.dart';
import 'inventario_view.dart';
import 'login_view.dart';
import 'pedidos_view.dart';
import 'productos_view.dart';
import 'proveedores_view.dart';
import 'reporte_view.dart';
import 'usuarios_view.dart';
import 'ventas_view.dart';
import 'compras_view.dart';
import 'configuracion_view.dart';
import '../widgets/nav_bar.dart';

class HomeView extends StatelessWidget {
  final String rol;

  const HomeView({
    super.key,
    required this.rol,
  });

  bool get esAdmin => rol == "Admin";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: CustomHeader(
        titulo: "Menu",
        mostrarVolver: false,

        extraActions: [
          if (esAdmin)
            IconButton(
              tooltip: "Configuracion",
              icon: const Icon(
                Icons.settings,
                color: Colors.black87,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfiguracionView(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(
              Icons.logout,
              color: Colors.black87,
            ),

            onPressed: () {
              SessionManager.clear();

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const LoginView(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),

        child: Container(
          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(28),

            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),

          child: LayoutBuilder(
            builder: (context, constraints) {

              int columnas = 2;

              if (constraints.maxWidth >= 700) {
                columnas = 4;
              }

              if (constraints.maxWidth >= 1100) {
                columnas = 5;
              }

              return GridView.count(
                crossAxisCount: columnas,

                mainAxisSpacing: 18,
                crossAxisSpacing: 18,

                childAspectRatio:
                    constraints.maxWidth >= 700 ? 1.15 : 1.3,

                children: [

                  // PRODUCTOS
                  if (esAdmin)
                  MenuCard(
                    title: "Productos",
                    subtitle: "Gestion de productos",
                    icon: Icons.inventory,
                    color: AppColors.primaryLighter,

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProductosView(),
                        ),
                      );
                    },
                  ),

                  // VENTAS
                  MenuCard(
                    title: "Ventas",
                    subtitle: "Registrar ventas",
                    icon: Icons.point_of_sale,
                    color: AppColors.primaryLighter,

                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VentasView(),
                        ),
                      );
                    },
                  ),

                  // CLIENTES
                    MenuCard(
                      title: "Clientes",
                      subtitle: "Base de clientes",
                      icon: Icons.people,
                      color: AppColors.primaryLight,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ClientesView(),
                          ),
                        );
                      },
                    ),

                  // INVENTARIO
                    MenuCard(
                      title: "Inventario",
                      subtitle: "Control de inventario",
                      icon: Icons.inventory_2,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InventarioView(),
                          ),
                        );
                      },
                    ),

                  // PROVEEDORES
                  if (esAdmin)
                    MenuCard(
                      title: "Proveedores",
                      subtitle: "Gestion de proveedores",
                      icon: Icons.local_shipping,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProveedorView(),
                          ),
                        );
                      },
                    ),

                  // USUARIOS
                  if (esAdmin)
                    MenuCard(
                      title: "Usuarios",
                      subtitle: "Gestion de usuarios",
                      icon: Icons.person,
                      color: AppColors.primaryLight,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UsuariosView(),
                          ),
                        );
                      },
                    ),

                  // REPORTES
                    MenuCard(
                      title: "Reportes",
                      subtitle: "Analisis",
                      icon: Icons.bar_chart,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReporteView(),
                          ),
                        );
                      },
                    ),

                  // COMPRAS
                    MenuCard(
                      title: "Compras",
                      subtitle: "Compras a proveedores",
                      icon: Icons.money,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ComprasView(),
                          ),
                        );
                      },
                    ),

                  // PEDIDOS
                    MenuCard(
                      title: "Pedidos",
                      subtitle: "Gestion de pedidos",
                      icon: Icons.receipt_long,
                      color: AppColors.primaryLight,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PedidosView(),
                          ),
                        );
                      },
                    ),

                  // AUDITORIAS
                  if (esAdmin)
                    MenuCard(
                      title: "Auditorias",
                      subtitle: "Seguimiento del sistema",
                      icon: Icons.fact_check_outlined,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AuditoriasView(),
                          ),
                        );
                      },
                    ),

                  // BASE DE DATOS
                  if (esAdmin)
                    MenuCard(
                      title: "Base de datos",
                      subtitle: "Backup y restore",
                      icon: Icons.storage_rounded,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BaseDatosView(),
                          ),
                        );
                      },
                    ),

                  // CORTE DE CAJA
                    MenuCard(
                      title: "Corte de Caja",
                      subtitle: "Resumen diario",
                      icon: Icons.attach_money,
                      color: AppColors.primaryLight,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CorteCajaView(),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
