import 'package:flutter/material.dart';

import '../core/security/permisos.dart';
import '../core/security/permisos_service.dart';
import '../core/theme/app_colors.dart';
import '../widgets/nav_bar.dart';

/// Editor de la matriz de permisos por rol (solo Admin). Muestra una fila por
/// permiso y una columna por rol: el Cajero y el Supervisor son editables; el
/// Admin va bloqueado en "sí" porque siempre tiene todo. Cada cambio se guarda
/// al instante vía [PermisosService].
class PermisosView extends StatefulWidget {
  const PermisosView({super.key});

  @override
  State<PermisosView> createState() => _PermisosViewState();
}

class _PermisosViewState extends State<PermisosView> {
  final _servicio = PermisosService.instancia;
  bool _cargando = true;

  static const double _anchoColumnaRol = 118;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await _servicio.cargar();
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  Future<void> _cambiar(String rol, Permiso permiso, bool valor) async {
    await _servicio.establecer(rol, permiso, valor);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(titulo: "Permisos por rol", mostrarVolver: true),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Permisos por rol",
                      style: TextStyle(
                        fontSize: AppText.display,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Define qué puede hacer cada rol. El administrador siempre tiene todos los permisos.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
                    ),
                    const SizedBox(height: 24),
                    _encabezado(),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final permiso in Permiso.values) _filaPermiso(permiso),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "PERMISO",
              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong, fontSize: AppText.caption),
            ),
          ),
          for (final rol in Roles.todos)
            SizedBox(
              width: _anchoColumnaRol,
              child: Text(
                rol.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textStrong, fontSize: AppText.caption),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaPermiso(Permiso permiso) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permiso.etiqueta,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppText.body, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  permiso.descripcion,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: AppText.small),
                ),
              ],
            ),
          ),
          for (final rol in Roles.todos)
            SizedBox(width: _anchoColumnaRol, child: Center(child: _celda(rol, permiso))),
        ],
      ),
    );
  }

  Widget _celda(String rol, Permiso permiso) {
    final permitido = _servicio.tienePermisoDeRol(rol, permiso);

    // El Admin no es configurable: se muestra bloqueado siempre en "sí".
    if (rol == Roles.admin) {
      return Tooltip(
        message: "El administrador siempre tiene todos los permisos",
        child: Icon(Icons.lock, size: 20, color: AppColors.textSecondary.withValues(alpha: 0.6)),
      );
    }

    return Checkbox(
      value: permitido,
      activeColor: AppColors.primary,
      onChanged: (v) => _cambiar(rol, permiso, v ?? false),
    );
  }
}
