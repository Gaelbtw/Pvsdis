import 'package:flutter/material.dart';
import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../widgets/nav_bar.dart';
import '../services/ticket_corte_caja_service.dart';
import '../services/configuracion_service.dart';
import '../models/configuracion_model.dart';
import '../widgets/custom_alert.dart';

import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

class CorteCajaView extends StatefulWidget {
  const CorteCajaView({super.key});

  @override
  State<CorteCajaView> createState() => _CorteCajaViewState();
}

class _CorteCajaViewState extends State<CorteCajaView> {
  // Datos
  double total = 0;
  double efectivo = 0;
  double tarjeta = 0;
  double salidasDB = 0;

  // Input
  final contadoCtrl = TextEditingController();

  //  Config
  late Configuracion config;
  bool cargando = true;

  //  Datos
  late DateTime ahora;
  late String turno;
  late String fecha;
  late String horaApertura;
  late String horaCierre;

  String cajero = SessionManager.currentUserName;

  @override
  void initState() {
    super.initState();
    inicializar();
  }

  @override
  void dispose() {
    contadoCtrl.dispose();
    super.dispose();
  }

  // INICIALIZAR
  Future<void> inicializar() async {
    ahora = DateTime.now();

    config = await ConfiguracionService().obtener();

    fecha = "${ahora.year}-${_2(ahora.month)}-${_2(ahora.day)}";

    turno = _getTurno(ahora);
    horaApertura = _getHoraApertura(turno);
    horaCierre = _formatHora(ahora);

    await calcular();

    if (!mounted) return;

    setState(() {
      cargando = false;
    });
  }

  //  HELPERS
  String _2(int n) => n.toString().padLeft(2, '0');

  String _formatHora(DateTime dt) {
    int h = dt.hour;
    int m = dt.minute;

    String periodo = h >= 12 ? "p.m." : "a.m.";

    h = h % 12 == 0 ? 12 : h % 12;

    return "${_2(h)}:${_2(m)} $periodo";
  }

  TimeOfDay _parseHora(String hora) {
    try {
      final limpio = hora.trim().replaceAll("am", "").replaceAll("pm", "");

      final parts = limpio.split(":");

      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  //  TURNOS
  String _getTurno(DateTime ahora) {
    final actual = TimeOfDay.fromDateTime(ahora);

    final matInicio = _parseHora(config.horaInicioMatutino);
    final matFin = _parseHora(config.horaFinMatutino);

    final vesInicio = _parseHora(config.horaInicioVespertino);
    final vesFin = _parseHora(config.horaFinVespertino);

    final actualMin = actual.hour * 60 + actual.minute;
    final matIniMin = matInicio.hour * 60 + matInicio.minute;
    final matFinMin = matFin.hour * 60 + matFin.minute;
    final vesIniMin = vesInicio.hour * 60 + vesInicio.minute;
    final vesFinMin = vesFin.hour * 60 + vesFin.minute;

    if (actualMin >= matIniMin && actualMin <= matFinMin) {
      return "Matutino";
    }

    if (actualMin >= vesIniMin && actualMin <= vesFinMin) {
      return "Vespertino";
    }

    return "Fuera de turno";
  }

  String _formatearHora(String hora) {
    final parts = hora.split(":");

    int h = int.parse(parts[0]);
    final m = parts[1];

    final periodo = h >= 12 ? "p.m." : "a.m.";

    h = h % 12 == 0 ? 12 : h % 12;

    return "${h.toString().padLeft(2, '0')}:$m $periodo";
  }

  String _getHoraApertura(String turno) {
    if (turno == "Matutino") {
      return _formatearHora(config.horaInicioMatutino);
    }

    if (turno == "Vespertino") {
      return _formatearHora(config.horaInicioVespertino);
    }

    return "--";
  }

  //  BD
  Future<void> calcular() async {
    final db = await DatabaseHelper().database;
    final hoy = "${ahora.year}-${_2(ahora.month)}-${_2(ahora.day)}";

    final totalRes = await db.rawQuery(
      "SELECT SUM(total) as total FROM Ventas WHERE fecha LIKE ?",
      ['$hoy%'],
    );

    final efectivoRes = await db.rawQuery(
      "SELECT SUM(total) as total FROM Ventas WHERE metodo_pago = 'efectivo' AND fecha LIKE ?",
      ['$hoy%'],
    );

    final tarjetaRes = await db.rawQuery(
      "SELECT SUM(total) as total FROM Ventas WHERE metodo_pago = 'tarjeta' AND fecha LIKE ?",
      ['$hoy%'],
    );

    final salidasRes = await db.rawQuery(
      "SELECT SUM(total) as total FROM Compras WHERE fecha LIKE ?",
      ['$hoy%'],
    );

    total = (totalRes.first["total"] as num?)?.toDouble() ?? 0;

    efectivo = (efectivoRes.first["total"] as num?)?.toDouble() ?? 0;

    tarjeta = (tarjetaRes.first["total"] as num?)?.toDouble() ?? 0;

    salidasDB = (salidasRes.first["total"] as num?)?.toDouble() ?? 0;
  }

  //  CÁLCULOS
  double get contado => double.tryParse(contadoCtrl.text) ?? 0;

  double get fondoInicial => config.fondoCaja;

  double get esperadoEnCaja => efectivo + fondoInicial - salidasDB;

  double get diferencia => contado - esperadoEnCaja;

  //  GENERAR CORTE
  void generarCorte() async {
  if (contadoCtrl.text.isEmpty) {
    showDialog(
      context: context,
      builder: (_) => const CustomAlert(
        titulo: "Campo requerido",
        mensaje: "Ingresa el efectivo contado.",
        icono: Icons.warning_amber_rounded,
        textoConfirmar: "Aceptar",
      ),
    );

    return;
  }

  horaCierre = _formatHora(DateTime.now());

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) => CustomAlert(
      titulo: "Generar corte",
      mensaje:
          "Se generará el corte de caja del turno $turno.\n\n"
          "Total ventas: \$${total.toStringAsFixed(2)}\n"
          "Efectivo: \$${efectivo.toStringAsFixed(2)}\n"
          "Tarjeta: \$${tarjeta.toStringAsFixed(2)}\n\n"
          "¿Deseas continuar?",
      icono: Icons.point_of_sale,
      textoCancelar: "Cancelar",
      textoConfirmar: "Generar",

      onConfirm: () async {
        try {
          final pdf = await TicketCorteCajaService.generarCorte(
            fecha: fecha,
            turno: turno,
            cajero: cajero,
            horaApertura: horaApertura,
            horaCierre: horaCierre,
            total: total,
            efectivo: efectivo,
            tarjeta: tarjeta,
            fondo: fondoInicial,
            salidas: salidasDB,
            contado: contado,
            esperado: esperadoEnCaja,
            diferencia: diferencia,
          );

          await Printing.layoutPdf(
            onLayout: (PdfPageFormat format) async => pdf.save(),
          );

          if (!mounted) return;

          showDialog(
            context: context,
            builder: (_) => const CustomAlert(
              titulo: "Corte generado",
              mensaje: "El corte de caja se generó correctamente.",
              icono: Icons.check_circle_outline,
              textoConfirmar: "Aceptar",
            ),
          );
        } catch (e) {
          if (!mounted) return;

          showDialog(
            context: context,
            builder: (_) => CustomAlert(
              titulo: "Error",
              mensaje: "Ocurrió un error al generar el corte.\n\n$e",
              icono: Icons.error_outline,
              textoConfirmar: "Aceptar",
            ),
          );
        }
      },
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F4),

      appBar: const CustomHeader(titulo: "Corte de Caja", mostrarVolver: true),

      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
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

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    //HEADER
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2C500),
                            shape: BoxShape.circle,
                          ),
                        ),

                        const SizedBox(width: 10),

                        const Text(
                          "Resumen de Corte",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2B2B2B),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Consulta el efectivo esperado y genera el cierre de caja del turno actual.",
                      style: TextStyle(color: Color(0xFF6E6A64), fontSize: 13),
                    ),

                    const SizedBox(height: 24),

                  
                    Row(
                      children: [
                        Expanded(
                          child: _statCard(
                            "Ventas Totales",
                            "\$${total.toStringAsFixed(2)}",
                            Icons.payments_outlined,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: _statCard(
                            "Efectivo",
                            "\$${efectivo.toStringAsFixed(2)}",
                            Icons.attach_money,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: _statCard(
                            "Tarjeta",
                            "\$${tarjeta.toStringAsFixed(2)}",
                            Icons.credit_card,
                          ),
                        ),

                        const SizedBox(width: 14),

                        Expanded(
                          child: _statCard(
                            "Salidas",
                            "\$${salidasDB.toStringAsFixed(2)}",
                            Icons.shopping_bag_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Expanded(
                      child: Row(
                        children: [
                          // 📋 INFORMACIÓN
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.all(22),

                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F6F2),
                                borderRadius: BorderRadius.circular(22),
                              ),

                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    "Información del turno",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: Color(0xFF3C3935),
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  _infoRow("Fecha", fecha),

                                  _infoRow("Turno", turno),

                                  _infoRow("Cajero", cajero),

                                  _infoRow("Hora apertura", horaApertura),

                                  _infoRow("Hora cierre", horaCierre),

                                  const SizedBox(height: 24),

                                  const Divider(),

                                  const SizedBox(height: 18),

                                  _infoRow(
                                    "Fondo inicial",
                                    "\$${fondoInicial.toStringAsFixed(2)}",
                                  ),

                                  _infoRow(
                                    "Efectivo esperado",
                                    "\$${esperadoEnCaja.toStringAsFixed(2)}",
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 20),

                          // CORTE
                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.all(22),

                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: const Color(0xFFE8E2D9),
                                ),
                              ),

                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const Text(
                                    "Ejecutar corte",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: Color(0xFF3C3935),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  const Text(
                                    "Ingresa el efectivo contado para calcular la diferencia.",
                                    style: TextStyle(
                                      color: Color(0xFF6E6A64),
                                      fontSize: 13,
                                    ),
                                  ),

                                  const SizedBox(height: 24),

                                  _input(
                                    "Efectivo contado",
                                    contadoCtrl,
                                    Icons.payments,
                                  ),

                                  const SizedBox(height: 22),

                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(18),

                                    decoration: BoxDecoration(
                                      color: diferencia == 0
                                          ? const Color(0xFFF7F6F2)
                                          : diferencia > 0
                                          ? Colors.green.shade50
                                          : Colors.red.shade50,

                                      borderRadius: BorderRadius.circular(18),
                                    ),

                                    child: Column(
                                      children: [
                                        const Text(
                                          "Conteo",
                                          style: TextStyle(
                                            color: Color(0xFF6E6A64),
                                            fontSize: 13,
                                          ),
                                        ),

                                        const SizedBox(height: 8),

                                        Text(
                                          "\$${diferencia.abs().toStringAsFixed(2)}",
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: diferencia == 0
                                                ? Colors.black87
                                                : diferencia > 0
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const Spacer(),

                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,

                                    child: ElevatedButton.icon(
                                      onPressed: generarCorte,

                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFF2C500,
                                        ),
                                        foregroundColor: Colors.black87,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),

                                      icon: const Icon(Icons.print),

                                      label: const Text(
                                        "Generar Corte",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F2),
        borderRadius: BorderRadius.circular(20),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, color: const Color(0xFFDA9B00), size: 24),

          const SizedBox(height: 16),

          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6E6A64),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2B2B),
            ),
          ),
        ],
      ),
    );
  }

  // FILA INFO
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),

      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6E6A64),
              fontWeight: FontWeight.w600,
            ),
          ),

          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2B2B),
            ),
          ),
        ],
      ),
    );
  }

  // INPUT
  Widget _input(String hint, TextEditingController ctrl, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,

      onChanged: (_) => setState(() {}),

      decoration: InputDecoration(
        hintText: hint,

        prefixIcon: Icon(icon, color: const Color(0xFFDA9B00)),

        filled: true,
        fillColor: const Color(0xFFF8F6F2),

        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 18,
        ),

        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
