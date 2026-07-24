import 'dart:io';

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import 'sync_estado_badge.dart';

class CustomHeader extends StatelessWidget implements PreferredSizeWidget {
  final String titulo;
  final bool? mostrarVolver;
  final List<Widget>? extraActions;

  const CustomHeader({
    super.key,
    required this.titulo,
    this.mostrarVolver,
    this.extraActions,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final puedeVolver = mostrarVolver ?? Navigator.canPop(context);
    final logoPath = AppConfig.actual.logoPath;

    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      toolbarHeight: 72,
      leadingWidth: puedeVolver ? 110 : 0,
      leading: puedeVolver
          ? TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back,
                  color: AppColors.textPrimary, size: 18),
              label: const Text(
                "Volver",
                style: TextStyle(color: AppColors.textPrimary),
              ),
            )
          : null,
      title: Row(
        children: [
          if (logoPath != null && File(logoPath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(File(logoPath), width: 22, height: 22, fit: BoxFit.cover),
            )
          else
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 10),
          Text(
            AppConfig.actual.nombreNegocio,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            " | $titulo",
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      actions: [
  _topInfo(Icons.calendar_today_outlined, _fechaLarga(now)),
  const SizedBox(width: 16),
  _topInfo(Icons.access_time, _hora(now)),
  const SizedBox(width: 16),
  const SyncEstadoBadge(),
  const SizedBox(width: 12),
  _usuarioBox(),
  ...?extraActions,
  const SizedBox(width: 12),
],
    );
  }

  Widget _usuarioBox() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SessionManager.currentUserName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppText.caption,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            SessionManager.currentUserRole.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppText.overline,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _topInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryDark),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppText.small,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _hora(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? "p.m." : "a.m.";
    return "$hour:$minute $period";
  }

  String _fechaLarga(DateTime value) {
    const dias = [
      "lunes","martes","miercoles","jueves","viernes","sabado","domingo",
    ];
    const meses = [
      "enero","febrero","marzo","abril","mayo","junio",
      "julio","agosto","septiembre","octubre","noviembre","diciembre",
    ];

    return "${dias[value.weekday - 1]}, ${value.day} de ${meses[value.month - 1]}";
  }

  @override
  Size get preferredSize => const Size.fromHeight(72);
}
