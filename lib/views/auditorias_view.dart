import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../controllers/auditoria_controller.dart';
import '../core/utils/auditoria_helpers.dart';
import '../models/auditoria_model.dart';
import '../widgets/nav_bar.dart';

class AuditoriasView extends StatefulWidget {
  const AuditoriasView({super.key});

  @override
  State<AuditoriasView> createState() => _AuditoriasViewState();
}

class _AuditoriasViewState extends State<AuditoriasView> {
  final controller = AuditoriaController();

  List<Auditoria> auditorias = [];
  String busqueda = "";
  String accionFiltro = "TODAS";

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    final data = await controller.obtenerTodas();
    if (!mounted) return;
    setState(() => auditorias = data);
  }

  List<Auditoria> get auditoriasFiltradas {
    return auditorias.where((a) {
      final texto = busqueda.toLowerCase();
      final coincideBusqueda =
          a.usuario.toLowerCase().contains(texto) ||
          a.tabla.toLowerCase().contains(texto) ||
          a.descripcion.toLowerCase().contains(texto) ||
          (a.idRegistro?.toString().contains(busqueda) ?? false);

      final coincideAccion =
          accionFiltro == "TODAS" ? true : a.accion == accionFiltro;

      return coincideBusqueda && coincideAccion;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(
        titulo: "Auditorias",
        mostrarVolver: true,
        extraActions: [
          IconButton(
            onPressed: _exportAuditoriasPDF,
            icon: const Icon(Icons.download, color: Colors.black87),
            tooltip: "Exportar auditoria",
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildToolbar(),
              const SizedBox(height: 20),
              _buildResumen(),
              const SizedBox(height: 20),
              _tablaHeader(),
              const SizedBox(height: 10),
              Expanded(
                child: auditoriasFiltradas.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        itemCount: auditoriasFiltradas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          return _filaAuditoria(auditoriasFiltradas[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: TextField(
            onChanged: (value) => setState(() => busqueda = value),
            decoration: InputDecoration(
              hintText: "Buscar por usuario, tabla o descripcion...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: accionFiltro,
              icon: const Icon(Icons.filter_list),
              items: [
                const DropdownMenuItem(value: "TODAS", child: Text("Todas")),
                ...accionesAuditoria.map(
                  (a) => DropdownMenuItem(value: a, child: Text(a)),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => accionFiltro = value);
              },
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _exportAuditoriasPDF,
          icon: const Icon(Icons.picture_as_pdf, size: 18),
          label: const Text("Exportar PDF"),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResumen() {
    return Row(
      children: [
        _summaryCard(
          icon: Icons.fact_check_outlined,
          label: "Registros",
          value: "${auditoriasFiltradas.length}",
          color: AppColors.primaryLight,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: Icons.add_circle_outline,
          label: "Altas",
          value: "${_contarAccion('CREATE')}",
          color: const Color(0xFFE8F0D5),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: Icons.edit_outlined,
          label: "Ediciones",
          value: "${_contarAccion('EDIT')}",
          color: AppColors.primaryLighter,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          icon: Icons.delete_outline,
          label: "Bajas",
          value: "${_contarAccion('DELETE')}",
          color: const Color(0xFFFFE3DF),
        ),
      ],
    );
  }

  int _contarAccion(String accion) {
    return auditoriasFiltradas.where((a) => a.accion == accion).length;
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.black87),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tablaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Expanded(flex: 22, child: Text("FECHA Y HORA", style: auditoriaHeaderStyle)),
          Expanded(flex: 16, child: Text("USUARIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("TABLA", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("ACCION", style: auditoriaHeaderStyle)),
          Expanded(flex: 12, child: Text("REGISTRO", style: auditoriaHeaderStyle)),
          Expanded(flex: 24, child: Text("DESCRIPCION", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaAuditoria(Auditoria auditoria) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        children: [
          Expanded(flex: 22, child: Text(formatearFechaHora(auditoria.fechaHora))),
          Expanded(flex: 16, child: Text(auditoria.usuario)),
          Expanded(flex: 14, child: Text(auditoria.tabla)),
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorPorAccionAuditoria(auditoria.accion).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  auditoria.accion,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorPorAccionAuditoria(auditoria.accion),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Text(auditoria.idRegistro?.toString() ?? "-"),
          ),
          Expanded(
            flex: 24,
            child: Text(
              auditoria.descripcion,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fact_check_outlined, size: 70, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            "No hay movimientos para mostrar",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAuditoriasPDF() async {
    final datos = auditoriasFiltradas;
    if (datos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay auditorias para exportar.')),
      );
      return;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(level: 0, text: 'Auditoria del sistema'),
            pw.Paragraph(text: 'Generado el ${DateTime.now().toLocal()}'),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: [
                'Fecha y Hora',
                'Usuario',
                'Tabla',
                'Accion',
                'Registro',
                'Descripcion',
              ],
              data: datos.map((auditoria) {
                return [
                  formatearFechaHora(auditoria.fechaHora),
                  auditoria.usuario,
                  auditoria.tabla,
                  auditoria.accion,
                  auditoria.idRegistro?.toString() ?? '-',
                  auditoria.descripcion,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.amber100,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

}
