import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_colors.dart';
import '../models/configuracion_model.dart';
import '../services/configuracion_service.dart';
import '../widgets/custom_alert.dart';
import '../widgets/nav_bar.dart';

class ConfiguracionView extends StatefulWidget {
  const ConfiguracionView({super.key});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  final _configuracionService = ConfiguracionService();

  bool cargando = true;

  TimeOfDay matutinoInicio = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay matutinoFin = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay vespertinoInicio = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay vespertinoFin = const TimeOfDay(hour: 21, minute: 0);

  final stockCtrl = TextEditingController();
  final fondoCtrl = TextEditingController();

  final nombreCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final correoCtrl = TextEditingController();
  final rfcCtrl = TextEditingController();
  final monedaCtrl = TextEditingController();
  final ivaCtrl = TextEditingController();
  final mensajeTicketCtrl = TextEditingController();
  final descuentoMaximoCtrl = TextEditingController();

  bool descuentoCajeroPuedeAplicar = true;
  bool descuentoCajeroRequiereAutorizacion = true;

  String? logoPath;
  late Color colorSeleccionado;

  static const _paletaColores = [
    Color(0xFFF2C500), // dorado (default)
    Color(0xFF2563EB), // azul
    Color(0xFF16A34A), // verde
    Color(0xFFDC2626), // rojo
    Color(0xFF9333EA), // morado
    Color(0xFFEA580C), // naranja
    Color(0xFF0D9488), // verde azulado
    Color(0xFF334155), // gris azulado oscuro
  ];

  @override
  void initState() {
    super.initState();
    colorSeleccionado = AppColors.primary;
    cargarConfig();
  }

  Future<void> cargarConfig() async {
    final config = await _configuracionService.obtener();

    setState(() {
      stockCtrl.text = config.stockMinimo.toString();
      fondoCtrl.text = config.fondoCaja.toString();

      matutinoInicio = _parseHora(config.horaInicioMatutino);
      matutinoFin = _parseHora(config.horaFinMatutino);
      vespertinoInicio = _parseHora(config.horaInicioVespertino);
      vespertinoFin = _parseHora(config.horaFinVespertino);

      nombreCtrl.text = config.nombreNegocio;
      direccionCtrl.text = config.direccion ?? '';
      telefonoCtrl.text = config.telefono ?? '';
      correoCtrl.text = config.correo ?? '';
      rfcCtrl.text = config.rfc ?? '';
      monedaCtrl.text = config.simboloMoneda;
      ivaCtrl.text = config.tasaImpuestoPorcentaje == 0
          ? ''
          : config.tasaImpuestoPorcentaje.toString();
      mensajeTicketCtrl.text = config.mensajeTicket;
      logoPath = config.logoPath;
      colorSeleccionado = Color(config.colorPrimario);

      descuentoMaximoCtrl.text = config.descuentoMaximoPorcentaje.toString();
      descuentoCajeroPuedeAplicar = config.descuentoCajeroPuedeAplicar;
      descuentoCajeroRequiereAutorizacion = config.descuentoCajeroRequiereAutorizacion;

      cargando = false;
    });
  }

  Future<void> seleccionarLogo() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.image,
    );

    final rutaOrigen = resultado?.files.single.path;
    if (rutaOrigen == null) return;

    final baseDir = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : Directory(await getDatabasesPathFallback());

    final extension = p.extension(rutaOrigen);
    final destino = p.join(baseDir.path, 'logo$extension');

    await File(rutaOrigen).copy(destino);

    setState(() {
      logoPath = destino;
    });
  }

  /// En Android/iOS no existe getApplicationSupportDirectory con el mismo
  /// significado que en desktop; se usa el directorio de documentos.
  Future<String> getDatabasesPathFallback() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> guardar() async {
    if (stockCtrl.text.trim().isEmpty ||
        fondoCtrl.text.trim().isEmpty ||
        nombreCtrl.text.trim().isEmpty) {
      showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: "Campos incompletos",
          mensaje:
              "El nombre del negocio, el stock mínimo y el fondo de caja son obligatorios.",
          icono: Icons.warning_amber_rounded,
          textoConfirmar: "Aceptar",
          onConfirm: () {},
        ),
      );
      return;
    }

    final nuevaConfig = Configuracion(
      horaInicioMatutino: format(matutinoInicio),
      horaFinMatutino: format(matutinoFin),
      horaInicioVespertino: format(vespertinoInicio),
      horaFinVespertino: format(vespertinoFin),
      stockMinimo: int.parse(stockCtrl.text),
      fondoCaja: double.parse(fondoCtrl.text),
      nombreNegocio: nombreCtrl.text.trim(),
      logoPath: logoPath,
      direccion: direccionCtrl.text.trim().isEmpty ? null : direccionCtrl.text.trim(),
      telefono: telefonoCtrl.text.trim().isEmpty ? null : telefonoCtrl.text.trim(),
      correo: correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
      rfc: rfcCtrl.text.trim().isEmpty ? null : rfcCtrl.text.trim(),
      simboloMoneda: monedaCtrl.text.trim().isEmpty ? r'$' : monedaCtrl.text.trim(),
      tasaImpuestoPorcentaje: double.tryParse(ivaCtrl.text.trim()) ?? 0,
      mensajeTicket: mensajeTicketCtrl.text.trim().isEmpty
          ? Configuracion.porDefecto().mensajeTicket
          : mensajeTicketCtrl.text.trim(),
      colorPrimario: colorSeleccionado.toARGB32(),
      descuentoMaximoPorcentaje:
          (double.tryParse(descuentoMaximoCtrl.text.trim()) ?? 20).clamp(0, 100).toDouble(),
      descuentoCajeroPuedeAplicar: descuentoCajeroPuedeAplicar,
      descuentoCajeroRequiereAutorizacion: descuentoCajeroRequiereAutorizacion,
    );

    await _configuracionService.guardar(nuevaConfig);
    AppConfig.actualizar(nuevaConfig);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: "Configuración guardada",
        mensaje: colorSeleccionado.toARGB32() != AppColors.primary.toARGB32()
            ? "Los datos del negocio se actualizaron. El color de marca se aplicará por completo la próxima vez que abras la app."
            : "La configuración del sistema ha sido actualizada exitosamente.",
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
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.primaryLighter,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryDark),
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
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
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
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
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
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, color: AppColors.primaryDark, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hora,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
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

  Widget _logoSelector() {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          clipBehavior: Clip.antiAlias,
          child: logoPath != null && File(logoPath!).existsSync()
              ? Image.file(File(logoPath!), fit: BoxFit.cover)
              : Icon(Icons.storefront_outlined, color: AppColors.primaryDark),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: seleccionarLogo,
            icon: const Icon(Icons.upload_outlined),
            label: Text(logoPath == null ? "Subir logo" : "Cambiar logo"),
          ),
        ),
      ],
    );
  }

  Widget _selectorColor() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _paletaColores.map((color) {
        final seleccionado = color.toARGB32() == colorSeleccionado.toARGB32();
        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => colorSeleccionado = color),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: seleccionado ? AppColors.textPrimary : Colors.transparent,
                width: 3,
              ),
            ),
            child: seleccionado
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Estos datos se usan en toda la app: encabezado, tickets, reportes y respaldos.",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 28),
                      sectionCard(
                        icon: Icons.storefront_outlined,
                        title: "Datos del negocio",
                        subtitle: "Nombre, logo y contacto que aparecen en tickets y reportes",
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _logoSelector(),
                            const SizedBox(height: 16),
                            customInput(controller: nombreCtrl, hint: "Nombre del negocio"),
                            const SizedBox(height: 12),
                            customInput(controller: direccionCtrl, hint: "Dirección"),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: customInput(
                                    controller: telefonoCtrl,
                                    hint: "Teléfono",
                                    keyboard: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: customInput(
                                    controller: correoCtrl,
                                    hint: "Correo",
                                    keyboard: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            customInput(controller: rfcCtrl, hint: "RFC / dato fiscal (opcional)"),
                          ],
                        ),
                      ),
                      sectionCard(
                        icon: Icons.receipt_long_outlined,
                        title: "Ticket y ventas",
                        subtitle: "Moneda, IVA y mensaje que se imprime en cada ticket",
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: customInput(controller: monedaCtrl, hint: "Símbolo de moneda (ej. \$)"),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: customInput(
                                    controller: ivaCtrl,
                                    hint: "IVA % (ej. 16)",
                                    keyboard: const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            customInput(controller: mensajeTicketCtrl, hint: "Mensaje al final del ticket"),
                          ],
                        ),
                      ),
                      sectionCard(
                        icon: Icons.palette_outlined,
                        title: "Color de marca",
                        subtitle: "Se aplica a botones y encabezados de todo el sistema",
                        child: _selectorColor(),
                      ),
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
                          keyboard: TextInputType.number,
                        ),
                      ),
                      sectionCard(
                        icon: Icons.payments_outlined,
                        title: "Caja",
                        subtitle: "Fondo inicial utilizado al abrir caja",
                        child: customInput(
                          controller: fondoCtrl,
                          hint: "Fondo inicial",
                          keyboard: TextInputType.number,
                        ),
                      ),
                      sectionCard(
                        icon: Icons.sell_outlined,
                        title: "Descuentos",
                        subtitle: "Umbral que exige motivo/autorización y permisos del cajero",
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            customInput(
                              controller: descuentoMaximoCtrl,
                              hint: "Umbral (% a partir del cual se exige motivo)",
                              keyboard: const TextInputType.numberWithOptions(decimal: true),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text("El cajero puede aplicar descuentos"),
                              value: descuentoCajeroPuedeAplicar,
                              activeThumbColor: AppColors.primary,
                              onChanged: (v) => setState(() => descuentoCajeroPuedeAplicar = v),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text("Requiere autorización de administrador al superar el umbral"),
                              value: descuentoCajeroRequiereAutorizacion,
                              activeThumbColor: AppColors.primary,
                              onChanged: (v) => setState(() => descuentoCajeroRequiereAutorizacion = v),
                            ),
                          ],
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
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
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
