import 'package:flutter/material.dart';

import '../controllers/database_backup_controller.dart';
import '../core/config/app_config.dart';
import '../core/session/session_manager.dart';
import '../core/theme/app_colors.dart';
import '../models/database_backup_model.dart';
import '../widgets/custom_alert.dart';
import 'login_view.dart';


const _databaseHeaderStyle = TextStyle(
  fontSize: AppText.overline,
  fontWeight: FontWeight.w800,
  color: AppColors.textStrong,
);

enum DatabaseTab { backup, restore }

class BaseDatosView extends StatefulWidget {
  const BaseDatosView({super.key});

  @override
  State<BaseDatosView> createState() => _BaseDatosViewState();
}

class _BaseDatosViewState extends State<BaseDatosView> {
  final controller = DatabaseBackupController();

  DatabaseTab selectedTab = DatabaseTab.backup;
  List<DatabaseBackup> backups = [];
  String? selectedBackupPath;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    cargarBackups();
  }

  Future<void> cargarBackups() async {
    final data = await controller.obtenerBackups();
    if (!mounted) return;
    setState(() => backups = data);
  }

Future<void> hacerBackup() async {
  setState(() => loading = true);

  try {
    await controller.crearBackup();
    await cargarBackups();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => const CustomAlert(
        titulo: 'Backup creado',
        mensaje: 'El respaldo se creó correctamente.',
        icono: Icons.check_circle_outline,
        textoConfirmar: 'Aceptar',
      ),
    );
  } catch (e) {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => CustomAlert(
        titulo: 'Error',
        mensaje: 'Error al crear backup:\n$e',
        icono: Icons.error_outline,
        textoConfirmar: 'Aceptar',
      ),
    );
  } finally {
    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  Future<void> restaurarSeleccionado() async {
    DatabaseBackup? selected;
    for (final backup in backups) {
      if (backup.path == selectedBackupPath) {
        selected = backup;
        break;
      }
    }

    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un backup para restaurar')),
      );
      return;
    }

final confirmar = await showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CustomAlert(
    titulo: 'Restaurar backup',
    mensaje:
        'Se restaurará la base de datos desde '
        '${selected!.backupFileName}. '
        'Los cambios actuales serán reemplazados.',
    icono: Icons.restore_page_outlined,
    textoConfirmar: 'Restaurar',
    textoCancelar: 'Cancelar',
  ),
);

    if (confirmar != true) return;

    setState(() => loading = true);

    try {
      await controller.restaurarBackup(selected);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const CustomAlert(
          titulo: 'Restauración exitosa',
          mensaje:
              'La base de datos fue restaurada correctamente. '
              'La sesión se cerrará para aplicar los cambios.',
          icono: Icons.check_circle_outline,
          textoConfirmar: 'Aceptar',
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginView()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => CustomAlert(
          titulo: 'Error',
          mensaje: 'Error al restaurar backup:\n$e',
          icono: Icons.error_outline,
          textoConfirmar: 'Aceptar',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leadingWidth: 110,
        leading: TextButton.icon(
          onPressed: loading ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 18),
          label: const Text(
            'Volver',
            style: TextStyle(color: Colors.black87),
          ),
        ),
        title: Row(
          children: [
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
                color: Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              ' | Base de datos',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          _topInfo(Icons.calendar_today_outlined, _fechaLarga(now)),
          const SizedBox(width: 16),
          _topInfo(Icons.access_time, _hora(now)),
          const SizedBox(width: 20),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
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
                    fontSize: AppText.caption,
                    color: Colors.black87,
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
          ),
          const SizedBox(width: 12),
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
            children: [
              Row(
                children: [
                  _tabButton('Back Up', DatabaseTab.backup),
                  const SizedBox(width: 18),
                  _tabButton('Restore', DatabaseTab.restore),
                  const Spacer(),
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _tableHeader(),
              const Divider(height: 1),
              Expanded(
                child: selectedTab == DatabaseTab.backup
                    ? _backupContent()
                    : _restoreContent(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: selectedTab == DatabaseTab.backup
                    ? [
                        _secondaryButton(
                          label: 'Backup',
                          onPressed: loading ? null : hacerBackup,
                        ),
                        const SizedBox(width: 12),
                        _secondaryButton(
                          label: 'Cancelar',
                          onPressed: loading
                              ? null
                              : () {
                                  setState(() {
                                    selectedBackupPath = null;
                                  });
                                },
                        ),
                      ]
                    : [
                        _secondaryButton(
                          label: 'Restore',
                          onPressed: loading ? null : restaurarSeleccionado,
                        ),
                        const SizedBox(width: 12),
                        _secondaryButton(
                          label: 'Cancelar',
                          onPressed: loading
                              ? null
                              : () {
                                  setState(() {
                                    selectedBackupPath = null;
                                  });
                                },
                        ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backupContent() {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Row(
            children: [
              Radio<String>(
                value: 'backup-action',
                groupValue: 'backup-action',
                onChanged: loading ? null : (_) {},
              ),
              const Expanded(
                flex: 7,
                child: Text(
                  'Realizar Back Up',
                  style: TextStyle(
                    fontSize: AppText.title,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  backups.isEmpty
                      ? 'Sin respaldos generados'
                      : 'Ultimo: ${_fechaHora(backups.first.modifiedAt)}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _restoreContent() {
    if (backups.isEmpty) {
      return const Center(
        child: Text('No hay backups disponibles para restaurar'),
      );
    }

    return ListView.separated(
      itemCount: backups.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final backup = backups[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            children: [
              Radio<String>(
                value: backup.path,
                groupValue: selectedBackupPath,
                onChanged: loading
                    ? null
                    : (value) => setState(() => selectedBackupPath = value),
              ),
              Expanded(
                flex: 7,
                child: Text(
                  backup.backupFileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(_fechaHora(backup.modifiedAt)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabButton(String label, DatabaseTab tab) {
    final isActive = selectedTab == tab;

    return GestureDetector(
      onTap: loading
          ? null
          : () {
              setState(() {
                selectedTab = tab;
              });
            },
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppText.small,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? Colors.black87 : const Color(0xFF9A948A),
        ),
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: const Row(
        children: [
          SizedBox(width: 48),
          Expanded(flex: 7, child: Text('File Name', style: _databaseHeaderStyle)),
          Expanded(flex: 5, child: Text('Backup Time', style: _databaseHeaderStyle)),
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        side: const BorderSide(color: Color(0xFFE0D8CF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Text(label, style: const TextStyle(color: Colors.black87)),
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
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: AppText.small,
          ),
        ),
      ],
    );
  }

  String _fechaHora(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  String _hora(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'p.m.' : 'a.m.';
    return '$hour:$minute $period';
  }

  String _fechaLarga(DateTime value) {
    const dias = [
      'lunes',
      'martes',
      'miercoles',
      'jueves',
      'viernes',
      'sabado',
      'domingo',
    ];
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];

    final dia = dias[value.weekday - 1];
    final mes = meses[value.month - 1];
    return '$dia, ${value.day} de $mes';
  }
}
