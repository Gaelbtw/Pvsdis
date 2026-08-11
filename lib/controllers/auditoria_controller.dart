import 'package:sqflite/sqflite.dart';

import '../core/database/database_helper.dart';
import '../core/session/session_manager.dart';
import '../models/auditoria_model.dart';

/// Una página de resultados de la bitácora, con el total que hay detrás del
/// filtro para poder mostrar "mostrando X de Y" y saber si quedan más.
class PaginaAuditorias {
  const PaginaAuditorias({
    required this.registros,
    required this.total,
    required this.desplazamiento,
  });

  final List<Auditoria> registros;

  /// Cuántos registros cumplen el filtro en total, no cuántos trae esta
  /// página.
  final int total;

  final int desplazamiento;

  bool get hayMas => desplazamiento + registros.length < total;
}

class AuditoriaController {
  final dbHelper = DatabaseHelper();

  /// Escribe un evento en la bitácora.
  ///
  /// [executor] permite que el registro participe de la transacción de quien
  /// llama, en vez de abrir su propia escritura suelta: si la operación
  /// auditada se revierte, su rastro se revierte con ella (y al revés, no
  /// queda una operación aplicada sin rastro). Si se omite, se usa la
  /// conexión normal, como antes.
  Future<int> registrar({
    required String tabla,
    required String accion,
    required String descripcion,
    int? idRegistro,
    String? usuario,
    int? idUsuario,
    int? idCaja,
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await dbHelper.database;
    final rol = SessionManager.currentUserRoleCanonico;
    final usuarioActual = '$rol: ${SessionManager.currentUserName}';

    return await db.insert('Auditorias', {
      "fecha_hora": DateTime.now().toIso8601String(),
      "usuario": usuario ?? usuarioActual,
      "tabla": tabla,
      "accion": accion,
      "id_registro": idRegistro,
      "descripcion": descripcion,
      "id_usuario": idUsuario ?? SessionManager.currentUserId,
      "id_caja": idCaja,
    });
  }

  /// Carga TODA la bitácora en memoria. **No usar desde una vista.**
  ///
  /// `Auditorias` crece con cada venta, movimiento de stock y login, y no se
  /// purga nunca: en una instalación de dos años son cientos de miles de
  /// filas. Se conserva solo para procesos que de verdad necesiten recorrerla
  /// entera (exportaciones, migraciones). Para mostrarla, usar
  /// [obtenerPagina].
  @Deprecated('Usa obtenerPagina: esta carga la tabla completa en memoria.')
  Future<List<Auditoria>> obtenerTodas() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'Auditorias',
      orderBy: 'fecha_hora DESC',
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

  /// Una página de la bitácora, ya filtrada **en SQL**.
  ///
  /// Sustituye al patrón anterior de "traer todo y filtrar en Dart", que en la
  /// vista de Auditorías significaba cargar la tabla completa y recorrerla
  /// entera una vez por cada celda dibujada.
  ///
  /// Sobre la búsqueda de texto: se usa `LIKE`, que en SQLite ignora
  /// mayúsculas **solo para ASCII**. Buscar "CAMION" encuentra "camion", pero
  /// "CAMIÓN" no encuentra "camión" (la Ó acentuada no se pliega). Es una
  /// pérdida real frente al `toLowerCase()` de Dart, y se acepta a cambio de
  /// no traer la tabla entera: los textos de la bitácora los genera la app con
  /// un formato consistente, así que el caso se da poco. Si algún día molesta,
  /// la solución es una columna normalizada, no volver a filtrar en memoria.
  Future<PaginaAuditorias> obtenerPagina({
    String busqueda = '',
    String? accion,
    String? tabla,
    int? idUsuario,
    DateTime? desde,
    DateTime? hasta,
    int limite = 100,
    int desplazamiento = 0,
  }) async {
    final db = await dbHelper.database;

    final condiciones = <String>[];
    final argumentos = <Object?>[];

    final texto = busqueda.trim();
    if (texto.isNotEmpty) {
      // `%` y `_` son comodines de LIKE. Sin escaparlos, buscar "50%"
      // devolvería cualquier cosa que empiece por "50".
      final patron = '%${_escaparLike(texto)}%';
      // Cadena cruda (r'...') para que el `\` de ESCAPE llegue tal cual a
      // SQLite en vez de interpretarse como escape de Dart.
      condiciones.add(
        r"(usuario LIKE ? ESCAPE '\'"
        r" OR tabla LIKE ? ESCAPE '\'"
        r" OR descripcion LIKE ? ESCAPE '\'"
        r" OR CAST(id_registro AS TEXT) LIKE ? ESCAPE '\')",
      );
      argumentos.addAll([patron, patron, patron, patron]);
    }

    if (accion != null && accion.isNotEmpty && accion != 'TODAS') {
      condiciones.add('accion = ?');
      argumentos.add(accion);
    }
    if (tabla != null && tabla.isNotEmpty && tabla != 'TODOS') {
      condiciones.add('tabla = ?');
      argumentos.add(tabla);
    }
    if (idUsuario != null) {
      condiciones.add('id_usuario = ?');
      argumentos.add(idUsuario);
    }
    if (desde != null) {
      condiciones.add('fecha_hora >= ?');
      argumentos.add(desde.toIso8601String());
    }
    if (hasta != null) {
      condiciones.add('fecha_hora <= ?');
      argumentos.add(hasta.toIso8601String());
    }

    final filtro = condiciones.isEmpty ? '' : 'WHERE ${condiciones.join(' AND ')}';

    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM Auditorias $filtro', argumentos),
        ) ??
        0;

    final filas = await db.rawQuery(
      'SELECT * FROM Auditorias $filtro ORDER BY fecha_hora DESC LIMIT ? OFFSET ?',
      [...argumentos, limite, desplazamiento],
    );

    return PaginaAuditorias(
      registros: filas.map((e) => Auditoria.fromMap(e)).toList(),
      total: total,
      desplazamiento: desplazamiento,
    );
  }

  static String _escaparLike(String valor) => valor
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// Cuántos registros hay de cada acción bajo el filtro dado.
  ///
  /// Se resuelve con un `GROUP BY` en vez de contando en Dart sobre la lista
  /// cargada: las tarjetas de resumen deben reflejar TODO lo que cumple el
  /// filtro, no solo la página visible. Contarlas en memoria mostraría "100
  /// altas" simplemente porque el tamaño de página es 100.
  Future<Map<String, int>> conteoPorAccion({
    String busqueda = '',
    String? accion,
    String? tabla,
  }) async {
    final db = await dbHelper.database;

    final condiciones = <String>[];
    final argumentos = <Object?>[];

    final texto = busqueda.trim();
    if (texto.isNotEmpty) {
      final patron = '%${_escaparLike(texto)}%';
      condiciones.add(
        r"(usuario LIKE ? ESCAPE '\'"
        r" OR tabla LIKE ? ESCAPE '\'"
        r" OR descripcion LIKE ? ESCAPE '\'"
        r" OR CAST(id_registro AS TEXT) LIKE ? ESCAPE '\')",
      );
      argumentos.addAll([patron, patron, patron, patron]);
    }
    if (accion != null && accion.isNotEmpty && accion != 'TODAS') {
      condiciones.add('accion = ?');
      argumentos.add(accion);
    }
    if (tabla != null && tabla.isNotEmpty && tabla != 'TODOS') {
      condiciones.add('tabla = ?');
      argumentos.add(tabla);
    }

    final filtro = condiciones.isEmpty ? '' : 'WHERE ${condiciones.join(' AND ')}';

    final filas = await db.rawQuery(
      'SELECT accion, COUNT(*) AS total FROM Auditorias $filtro GROUP BY accion',
      argumentos,
    );

    return {
      for (final f in filas)
        (f['accion']?.toString() ?? ''): (f['total'] as int? ?? 0),
    };
  }

  /// Valores distintos de `tabla` presentes en la bitácora, para poblar el
  /// filtro de módulo sin tener que cargar todos los registros.
  Future<List<String>> modulosDisponibles() async {
    final db = await dbHelper.database;
    final filas = await db.rawQuery(
      'SELECT DISTINCT tabla FROM Auditorias ORDER BY tabla',
    );
    return filas.map((f) => f['tabla']?.toString() ?? '').where((t) => t.isNotEmpty).toList();
  }

  Future<List<Auditoria>> obtenerPorTablas(List<String> tablas) async {
    if (tablas.isEmpty) return [];

    final db = await dbHelper.database;
    final placeholders = List.filled(tablas.length, '?').join(',');
    final result = await db.query(
      'Auditorias',
      where: 'tabla IN ($placeholders)',
      whereArgs: tablas,
      orderBy: 'fecha_hora DESC',
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

  /// Consulta usada por el reporte de movimientos por usuario: reutiliza la
  /// misma tabla `Auditorias` que ya alimentan ventas, caja, inventario,
  /// clientes, proveedores, usuarios, promociones, apartados y devoluciones,
  /// solo que con filtros combinables (todos opcionales).
  /// [limite] acota el resultado, igual que [obtenerPagina].
  ///
  /// Antes esta consulta no tenía tope: con todos los filtros en blanco
  /// devolvía la bitácora entera, y la vista de "Movimientos por usuario" la
  /// pintaba de golpe en un `ListView` sin virtualizar. Con años de historial
  /// eso son cientos de miles de widgets construidos a la vez.
  Future<List<Auditoria>> obtenerFiltradas({
    int? idUsuario,
    String? accion,
    String? tabla,
    int? idCaja,
    DateTime? desde,
    DateTime? hasta,
    int limite = 500,
  }) async {
    final db = await dbHelper.database;

    final condiciones = <String>[];
    final argumentos = <Object?>[];

    if (idUsuario != null) {
      condiciones.add('id_usuario = ?');
      argumentos.add(idUsuario);
    }
    if (accion != null && accion.isNotEmpty) {
      condiciones.add('accion = ?');
      argumentos.add(accion);
    }
    if (tabla != null && tabla.isNotEmpty) {
      condiciones.add('tabla = ?');
      argumentos.add(tabla);
    }
    if (idCaja != null) {
      condiciones.add('id_caja = ?');
      argumentos.add(idCaja);
    }
    if (desde != null) {
      condiciones.add('fecha_hora >= ?');
      argumentos.add(desde.toIso8601String());
    }
    if (hasta != null) {
      condiciones.add('fecha_hora <= ?');
      argumentos.add(hasta.toIso8601String());
    }

    final result = await db.query(
      'Auditorias',
      where: condiciones.isEmpty ? null : condiciones.join(' AND '),
      whereArgs: condiciones.isEmpty ? null : argumentos,
      orderBy: 'fecha_hora DESC',
      limit: limite,
    );

    return result.map((e) => Auditoria.fromMap(e)).toList();
  }

}
