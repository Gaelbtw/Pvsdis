import 'package:flutter/material.dart';
import '../core/session/session_manager.dart';

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

    return AppBar(
      backgroundColor: const Color(0xFFFAF8F4),
      elevation: 0,
      leadingWidth: puedeVolver ? 110 : 0,
      leading: puedeVolver
          ? TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back,
                  color: Colors.black87, size: 18),
              label: const Text(
                "Volver",
                style: TextStyle(color: Colors.black87),
              ),
            )
          : null,
      title: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFF2C500),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            "La Lomita",
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            " | $titulo",
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
      actions: [
  _topInfo(Icons.calendar_today_outlined, _fechaLarga(now)),
  const SizedBox(width: 16),
  _topInfo(Icons.access_time, _hora(now)),
  const SizedBox(width: 20),
  _usuarioBox(),
  if (extraActions != null) ...extraActions!,
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6E0D8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            SessionManager.currentUserName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          Text(
            SessionManager.currentUserRole.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              color: Color(0xFFCC9A00),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFDA9B00)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87,
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}