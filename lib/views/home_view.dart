import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/session/session_manager.dart';
import '../controllers/auditoria_controller.dart';
import '../widgets/menu_card.dart';
import 'apartados_view.dart';
import 'clientes_view.dart';
import 'caja_view.dart';
import 'inventario_view.dart';
import 'login_view.dart';
import 'pedidos_view.dart';
import 'productos_view.dart';
import 'proveedores_view.dart';
import 'reporte_view.dart';
import 'ventas_view.dart';
import 'compras_view.dart';
import 'configuracion_view.dart';
import '../widgets/nav_bar.dart';

/// Inicio del Administrador: muestra únicamente Productos, Ventas,
/// Inventario, Clientes, Proveedores, Compras y Caja. Usuarios, Reportes,
/// Auditorías, Base de datos, Apartados, Promociones y Pedidos se
/// administran desde Configuración. El inicio de Cajero no cambia: conserva
/// su acceso directo a Apartados, Pedidos y Reportes (con las mismas
/// restricciones que ya tenía).
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  bool get esAdmin => SessionManager.isAdmin;

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
                color: AppColors.textPrimary,
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
              color: AppColors.textPrimary,
            ),

            onPressed: () async {
              await AuditoriaController().registrar(
                tabla: 'Sesion',
                accion: 'LOGOUT',
                descripcion: 'Cierre de sesión',
              );

              SessionManager.clear();

              if (!context.mounted) return;

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

            boxShadow: AppColors.cardShadow,
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

                  // APARTADOS (solo Cajero: Admin los administra desde Configuración)
                  if (!esAdmin)
                    MenuCard(
                      title: "Apartados",
                      subtitle: "Reservas con anticipo",
                      icon: Icons.event_available,
                      color: AppColors.primaryLighter,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ApartadosView(),
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

                  // REPORTES (solo Cajero: Admin los administra desde Configuración)
                  if (!esAdmin)
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

                  // PEDIDOS (solo Cajero: Admin los administra desde Configuración)
                  if (!esAdmin)
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

                  // CAJA
                    MenuCard(
                      title: "Caja",
                      subtitle: "Apertura, cierre e historial",
                      icon: Icons.attach_money,
                      color: AppColors.primaryLight,

                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CajaView(),
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
