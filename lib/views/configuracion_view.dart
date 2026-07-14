import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../core/database/database_helper.dart';
import '../widgets/nav_bar.dart';
import '../widgets/custom_alert.dart';

class ConfiguracionView extends StatefulWidget {
  const ConfiguracionView({super.key});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  bool cargando = true;

  TimeOfDay matutinoInicio = const TimeOfDay(hour: 7, minute: 0);

  TimeOfDay matutinoFin = const TimeOfDay(hour: 14, minute: 0);

  TimeOfDay vespertinoInicio = const TimeOfDay(hour: 14, minute: 0);

  TimeOfDay vespertinoFin = const TimeOfDay(hour: 21, minute: 0);

  final stockCtrl = TextEditingController();
  final fondoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    cargarConfig();
  }

  Future<void> cargarConfig() async {
    final db = await DatabaseHelper().database;

    final res = await db.query("configuracion");

    if (res.isEmpty) {
      await db.insert("configuracion", {
        "id": 1,
        "hora_inicio_matutino": "07:00",
        "hora_fin_matutino": "14:00",
        "hora_inicio_vespertino": "14:00",
        "hora_fin_vespertino": "21:00",
        "stock_minimo": 5,
        "fondo_caja": 500,
      });

      await cargarConfig();
      return;
    }

    final row = res.first;

    setState(() {
      stockCtrl.text = row["stock_minimo"].toString();

      fondoCtrl.text = row["fondo_caja"].toString();

      matutinoInicio = _parseHora(row["hora_inicio_matutino"] as String);

      matutinoFin = _parseHora(row["hora_fin_matutino"] as String);

      vespertinoInicio = _parseHora(row["hora_inicio_vespertino"] as String);

      vespertinoFin = _parseHora(row["hora_fin_vespertino"] as String);

      cargando = false;
    });
  }

  Future<void> guardar() async {
  if (stockCtrl.text.trim().isEmpty ||
      fondoCtrl.text.trim().isEmpty) {
    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Campos incompletos",
        mensaje:
            "Debes completar todos los campos de configuración.",
        icono: Icons.warning_amber_rounded,
        textoConfirmar: "Aceptar",

        onConfirm: () {
          Navigator.pop(context);
        },
      ),
    );

    return;
  }

  final db = await DatabaseHelper().database;

  await db.insert(
    "configuracion",
    {
      "id": 1,
      "hora_inicio_matutino": format(matutinoInicio),
      "hora_fin_matutino": format(matutinoFin),
      "hora_inicio_vespertino": format(vespertinoInicio),
      "hora_fin_vespertino": format(vespertinoFin),
      "stock_minimo": int.parse(stockCtrl.text),
      "fondo_caja": double.parse(fondoCtrl.text),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: "Configuración guardada",
      mensaje:
          "La configuración del sistema ha sido actualizada exitosamente.",
      icono: Icons.check_circle_outline,
      textoConfirmar: "Aceptar",

      onConfirm: () {},
    ),
  );
}

  String format(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');

    final m = t.minute.toString().padLeft(2, '0');

    return "$h:$m";
  }

  TimeOfDay _parseHora(String hora) {
    final parts = hora.split(":");

    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  Future<void> pickHora(bool inicio, bool matutino) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      if (matutino) {
        inicio ? matutinoInicio = picked : matutinoFin = picked;
      } else {
        inicio ? vespertinoInicio = picked : vespertinoFin = picked;
      }
    });
  }

  Widget sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),

      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: const Color(0xFFFCFBF9),

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: const Color(0xFFF0EBE5)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,

                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4CC),

                  borderRadius: BorderRadius.circular(14),
                ),

                child: Icon(icon, color: const Color(0xFFB88300)),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,

                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2D2B28),
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,

                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6E6A64),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          child,
        ],
      ),
    );
  }

  Widget customInput({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,

      keyboardType: TextInputType.number,

      decoration: InputDecoration(
        hintText: hint,

        filled: true,
        fillColor: Colors.white,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget horaButton({
    required String label,
    required String hora,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),

      onTap: onTap,

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(18),

          border: Border.all(color: const Color(0xFFECE5DB)),
        ),

        child: Row(
          children: [
            const Icon(
              Icons.access_time_rounded,
              color: Color(0xFFCC9600),
              size: 20,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    label,

                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E6A64),
                    ),
                  ),

                  const SizedBox(height: 3),

                  Text(
                    hora,

                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D2B28),
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF9F9A93)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

      appBar: const CustomHeader(titulo: "Configuración", mostrarVolver: true),

      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
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

                  child: ListView(
                    children: [
                      const Text(
                        "Configuración General",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D2B28),
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "Administre horarios, inventario y parámetros generales del sistema",
                        style: TextStyle(
                          color: Color(0xFF6E6A64),
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 28),

                      sectionCard(
                        icon: Icons.wb_sunny_outlined,

                        title: "Turno Matutino",

                        subtitle: "Defina el horario operativo matutino",

                        child: Row(
                          children: [
                            Expanded(
                              child: horaButton(
                                label: "Hora inicio",

                                hora: format(matutinoInicio),

                                onTap: () => pickHora(true, true),
                              ),
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: horaButton(
                                label: "Hora fin",

                                hora: format(matutinoFin),

                                onTap: () => pickHora(false, true),
                              ),
                            ),
                          ],
                        ),
                      ),

                      sectionCard(
                        icon: Icons.nightlight_round,

                        title: "Turno Vespertino",

                        subtitle: "Configure el horario vespertino",

                        child: Row(
                          children: [
                            Expanded(
                              child: horaButton(
                                label: "Hora inicio",

                                hora: format(vespertinoInicio),

                                onTap: () => pickHora(true, false),
                              ),
                            ),

                            const SizedBox(width: 14),

                            Expanded(
                              child: horaButton(
                                label: "Hora fin",

                                hora: format(vespertinoFin),

                                onTap: () => pickHora(false, false),
                              ),
                            ),
                          ],
                        ),
                      ),

                      sectionCard(
                        icon: Icons.inventory_2_outlined,

                        title: "Inventario",

                        subtitle: "Control de stock mínimo permitido",

                        child: customInput(
                          controller: stockCtrl,
                          hint: "Stock mínimo",
                        ),
                      ),

                      sectionCard(
                        icon: Icons.payments_outlined,

                        title: "Caja",

                        subtitle: "Fondo inicial utilizado al abrir caja",

                        child: customInput(
                          controller: fondoCtrl,
                          hint: "Fondo inicial",
                        ),
                      ),

                      const SizedBox(height: 8),

                      SizedBox(
                        height: 58,

                        child: ElevatedButton.icon(
                          onPressed: guardar,

                          icon: const Icon(Icons.save_outlined),

                          label: const Text("Guardar Configuración"),

                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF2C500),

                            foregroundColor: Colors.black87,

                            elevation: 0,

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),

                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
