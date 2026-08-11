import 'dart:async';

import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../controllers/auditoria_controller.dart';
import '../core/utils/auditoria_helpers.dart';
import '../models/auditoria_model.dart';
import '../widgets/nav_bar.dart';
import '../widgets/toast.dart';

class AuditoriasView extends StatefulWidget {
  const AuditoriasView({super.key});

  @override
  State<AuditoriasView> createState() => _AuditoriasViewState();
}

class _AuditoriasViewState extends State<AuditoriasView> {
  final controller = AuditoriaController();

  /// Registros de la página actual, NO la bitácora completa.
  ///
  /// Antes esta vista hacía `obtenerTodas()` y filtraba en Dart con un getter
  /// que se consumía una vez por celda dibujada. `Auditorias` crece con cada
  /// venta y nunca se purga, así que el coste no tenía techo: en una
  /// instalación de dos años eran ~145.000 filas en memoria y millones de
  /// comparaciones de texto por frame. Ahora el filtro va en SQL y solo viajan
  /// [_porPagina] registros.
  List<Auditoria> auditorias = [];

  String busqueda = "";
  String accionFiltro = "TODAS";

  int _total = 0;
  bool _hayMas = false;
  bool _cargando = true;
  bool _cargandoMas = false;

  /// Conteo por acción sobre el filtro completo (ver [_contarAccion]).
  Map<String, int> _conteoPorAccion = const {};

  static const int _porPagina = 100;

  /// Amortigua el tecleo: sin esto cada carácter dispararía una consulta.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Recarga desde la primera página. Se llama al entrar y cada vez que
  /// cambia un filtro.
  Future<void> cargar() async {
    setState(() => _cargando = true);

    // Las dos consultas van en paralelo: son independientes y así el reporte
    // no tarda el doble.
    final resultados = await Future.wait([
      controller.obtenerPagina(
        busqueda: busqueda,
        accion: accionFiltro,
        limite: _porPagina,
      ),
      // El conteo por acción se pide SIN el filtro de acción: si no, al
      // seleccionar "Altas" las demás tarjetas se irían a cero y no se
      // podría comparar.
      controller.conteoPorAccion(busqueda: busqueda),
    ]);

    if (!mounted) return;
    final pagina = resultados[0] as PaginaAuditorias;

    setState(() {
      auditorias = pagina.registros;
      _total = pagina.total;
      _hayMas = pagina.hayMas;
      _conteoPorAccion = resultados[1] as Map<String, int>;
      _cargando = false;
    });
  }

  /// Añade la siguiente página al final de la lista ya cargada.
  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;
    setState(() => _cargandoMas = true);

    final pagina = await controller.obtenerPagina(
      busqueda: busqueda,
      accion: accionFiltro,
      limite: _porPagina,
      desplazamiento: auditorias.length,
    );

    if (!mounted) return;
    setState(() {
      // Se filtran los que ya están en pantalla.
      //
      // La paginación por OFFSET asume una tabla quieta, y `Auditorias` NO lo
      // está: cada venta, cada movimiento de caja y cada login insertan filas
      // mientras el usuario mira el listado. Como el orden es `fecha_hora
      // DESC`, si entran 5 registros nuevos entre una página y la siguiente,
      // el OFFSET queda desplazado y esas 5 filas vuelven a aparecer
      // duplicadas.
      //
      // Deduplicar por id es una curita, no la cura: lo correcto sería
      // paginación por cursor (`WHERE (fecha_hora, id_auditoria) < (?, ?)`).
      // Se deja así porque no cambia el SQL ni introduce un modo de fallo
      // nuevo; si algún día el listado se usa de forma intensiva, ese es el
      // cambio que toca.
      final yaVisibles = {for (final a in auditorias) a.idAuditoria};
      auditorias.addAll(
        pagina.registros.where((r) => !yaVisibles.contains(r.idAuditoria)),
      );

      _total = pagina.total;
      _hayMas = pagina.hayMas;
      _cargandoMas = false;
    });
  }

  void _onBusquedaChanged(String valor) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      busqueda = valor;
      cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomHeader(
        titulo: "Auditorías",
        mostrarVolver: true,
        extraActions: [
          IconButton(
            onPressed: _exportAuditoriasPDF,
            icon: const Icon(Icons.download, color: Colors.black87),
            tooltip: "Exportar auditoría",
          ),
        ],
      ),
      body: Padding(
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
              _buildToolbar(),
              const SizedBox(height: 20),
              _buildResumen(),
              const SizedBox(height: 20),
              _tablaHeader(),
              const SizedBox(height: 10),
              Expanded(
                child: _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : auditorias.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            // Una fila extra al final: o el botón de "cargar
                            // más", o el aviso de que ya no hay nada más.
                            itemCount: auditorias.length + 1,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              if (index == auditorias.length) {
                                return _pieDeLista();
                              }
                              return _filaAuditoria(auditorias[index]);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cierre de la lista: botón para traer la siguiente página, o el conteo
  /// final. Hace explícito que lo que se ve es una parte, no todo.
  Widget _pieDeLista() {
    if (!_hayMas) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            _total == 0
                ? ''
                : 'Se muestran los $_total registros que cumplen el filtro.',
            style: const TextStyle(
                fontSize: AppText.small, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _cargandoMas
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton.icon(
                onPressed: _cargarMas,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Cargar más  (${auditorias.length} de $_total)'),
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
            onChanged: _onBusquedaChanged,
            decoration: InputDecoration(
              hintText: "Buscar por usuario, módulo o descripción…",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
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
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: accionFiltro,
              icon: const Icon(Icons.filter_list),
              items: [
                const DropdownMenuItem(value: "TODAS", child: Text("Todas las acciones")),
                ...accionesAuditoria.map(
                  (a) => DropdownMenuItem(value: a, child: Text(etiquetaAccionAuditoria(a))),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                // Ahora el filtro se aplica en SQL, así que cambiarlo obliga a
                // volver a consultar desde la primera página.
                accionFiltro = value;
                cargar();
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
              borderRadius: BorderRadius.circular(AppRadius.md),
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
          // `_total` y no `auditorias.length`: la tarjeta debe reflejar todo
          // lo que cumple el filtro, no cuántos caben en la página cargada.
          value: "$_total",
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

  /// Conteo por acción de TODO lo que cumple el filtro, calculado con un
  /// `GROUP BY` al cargar. Contarlo sobre la lista en memoria daría el conteo
  /// de la página, no del total.
  int _contarAccion(String accion) => _conteoPorAccion[accion] ?? 0;

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
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppRadius.md),
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
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: AppText.heading,
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
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        children: [
          Expanded(flex: 22, child: Text("FECHA Y HORA", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("USUARIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 14, child: Text("MÓDULO", style: auditoriaHeaderStyle)),
          Expanded(flex: 16, child: Text("ACCIÓN", style: auditoriaHeaderStyle)),
          Expanded(flex: 10, child: Text("FOLIO", style: auditoriaHeaderStyle)),
          Expanded(flex: 24, child: Text("DESCRIPCIÓN", style: auditoriaHeaderStyle)),
        ],
      ),
    );
  }

  Widget _filaAuditoria(Auditoria auditoria) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        children: [
          Expanded(flex: 22, child: Text(formatearFechaHora(auditoria.fechaHora))),
          Expanded(flex: 14, child: Text(auditoria.usuario)),
          Expanded(flex: 14, child: Text(etiquetaModuloAuditoria(auditoria.tabla))),
          Expanded(
            flex: 16,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorPorAccionAuditoria(auditoria.accion).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  etiquetaAccionAuditoria(auditoria.accion),
                  style: TextStyle(
                    fontSize: AppText.caption,
                    fontWeight: FontWeight.w800,
                    color: colorPorAccionAuditoria(auditoria.accion),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 10,
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
          Icon(Icons.fact_check_outlined, size: 70, color: AppColors.disabled),
          const SizedBox(height: 14),
          Text(
            "No hay movimientos para mostrar",
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppText.bodyLg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Tope de filas del PDF de auditoría.
  ///
  /// La exportación necesita TODO lo que cumple el filtro, no solo la página
  /// visible, así que aquí sí se hace una consulta grande. Pero sin tope, en
  /// una instalación con años de historial se intentaría construir un PDF de
  /// cientos de miles de filas: la app se quedaría sin memoria y el archivo
  /// resultante sería inservible. Si se alcanza el tope se avisa, en vez de
  /// entregar en silencio un documento incompleto.
  static const int _maxFilasPdf = 5000;

  Future<void> _exportAuditoriasPDF() async {
    final pagina = await controller.obtenerPagina(
      busqueda: busqueda,
      accion: accionFiltro,
      limite: _maxFilasPdf,
    );
    final datos = pagina.registros;

    if (datos.isEmpty) {
      if (!mounted) return;
      Toast.info(context, 'No hay auditorías para exportar.');
      return;
    }

    if (pagina.total > _maxFilasPdf) {
      if (!mounted) return;
      Toast.info(
        context,
        'Se exportan los $_maxFilasPdf más recientes de ${pagina.total}. '
        'Acota el filtro para incluir el resto.',
      );
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(level: 0, text: 'Auditoría del sistema'),
            pw.Paragraph(text: 'Generado el ${formatearFechaHora(DateTime.now().toIso8601String())}'),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: [
                'Fecha y hora',
                'Usuario',
                'Módulo',
                'Acción',
                'Folio',
                'Descripción',
              ],
              data: datos.map((auditoria) {
                return [
                  formatearFechaHora(auditoria.fechaHora),
                  auditoria.usuario,
                  etiquetaModuloAuditoria(auditoria.tabla),
                  etiquetaAccionAuditoria(auditoria.accion),
                  auditoria.idRegistro?.toString() ?? '-',
                  auditoria.descripcion,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.amber100,
              ),
              cellStyle: const pw.TextStyle(fontSize: AppText.overline),
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
