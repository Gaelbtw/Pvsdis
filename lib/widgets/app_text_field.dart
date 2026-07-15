import 'package:flutter/material.dart';

/// Campo de texto estándar usado en formularios de alta/edición. Antes cada
/// vista definía su propia versión casi idéntica de este widget
/// (`_input`, `_inputFormulario`, `customInput`, ...); esta es la única.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType keyboardType;
  final IconData? icon;
  final Color iconColor;
  final Color fillColor;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.icon,
    this.iconColor = Colors.black87,
    this.fillColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, color: iconColor),
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
