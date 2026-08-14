import 'package:sqflite/sqflite.dart';

/// La base de datos del equipo fue creada por una versión MÁS RECIENTE de la
/// app que la que se está ejecutando.
///
/// Pasa cuando alguien instala una versión anterior encima de una al día: el
/// cliente corre el instalador que guardó en la USB, o se le manda por WhatsApp
/// el archivo equivocado. Como los instaladores se reparten a mano y la copia
/// vieja se queda para siempre en el escritorio del cliente, es cuestión de
/// tiempo.
///
/// `sqflite` no sabe bajar de versión: no existe un `_onDowngrade` que
/// deshaga las migraciones. Sin este chequeo previo, el código viejo abre la
/// base nueva y lee columnas que en su versión del esquema no existen —o peor,
/// escribe filas incompletas—, y el daño ya no se puede deshacer.
///
/// Por eso se aborta ANTES de abrir para escritura y se muestra el mensaje en
/// pantalla ([ErrorArranqueApp]), nunca como excepción cruda.
class BaseDeDatosMasNuevaException implements Exception {
  const BaseDeDatosMasNuevaException({
    required this.versionArchivo,
    required this.versionApp,
    required this.rutaArchivo,
  });

  /// `PRAGMA user_version` que trae el archivo.
  final int versionArchivo;

  /// Versión del esquema que maneja esta compilación.
  final int versionApp;

  final String rutaArchivo;

  /// Mensaje dirigido al dueño del negocio, no al programador: dice qué pasó,
  /// qué hacer y —sobre todo— que no toque nada.
  String get mensajeParaElUsuario =>
      'La información de este equipo fue creada por una versión más reciente '
      'de Pv Control, y esta versión no puede abrirla sin dañarla.\n\n'
      'Esto suele pasar cuando se instala por error un instalador viejo '
      'encima de uno más nuevo.\n\n'
      'Qué hacer: instala la versión más reciente de Pv Control encima de '
      'esta. Tus ventas, tu inventario y tus clientes están intactos y '
      'volverán a aparecer en cuanto abras con la versión correcta.';

  @override
  String toString() =>
      'BaseDeDatosMasNuevaException: el archivo está en el esquema '
      'v$versionArchivo y esta app maneja v$versionApp ($rutaArchivo)';
}

/// Ejecuta una operación de base de datos y, si SQLite la rechaza por una
/// violación de llave foránea (por ejemplo, borrar un registro que todavía
/// tiene ventas, compras o pedidos asociados), la convierte en un mensaje
/// claro para quien llama en vez de dejar pasar la excepción técnica cruda
/// de SQLite.
Future<T> ejecutarConMensajeDeIntegridad<T>(
  Future<T> Function() accion,
  String mensajeSiHayDependientes,
) async {
  try {
    return await accion();
  } on DatabaseException catch (e) {
    if (e.toString().toLowerCase().contains('foreign key constraint failed')) {
      throw Exception(mensajeSiHayDependientes);
    }
    rethrow;
  }
}

/// Red de seguridad a nivel de base de datos para violaciones de unicidad
/// (por ejemplo, dos productos con el mismo código de barras). La UI ya
/// valida esto antes de guardar, pero esto cubre condiciones de carrera u
/// otros puntos de entrada que no pasen por esa validación.
Future<T> ejecutarConMensajeDeDuplicado<T>(
  Future<T> Function() accion,
  String mensajeSiEsDuplicado,
) async {
  try {
    return await accion();
  } on DatabaseException catch (e) {
    if (e.isUniqueConstraintError()) {
      throw Exception(mensajeSiEsDuplicado);
    }
    rethrow;
  }
}
