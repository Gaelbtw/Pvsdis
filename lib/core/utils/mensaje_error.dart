/// Convierte una excepción en un texto que se le pueda enseñar a un cajero.
///
/// Los controladores ya traducen los fallos de SQLite a mensajes claros (ver
/// `core/database/db_exceptions.dart`: "no se puede eliminar, tiene ventas
/// asociadas", "ya existe un producto con ese código"). El problema era que
/// las vistas no capturaban nada, así que ese mensaje nunca llegaba a la
/// pantalla: la excepción subía sin manejar y el usuario veía una pantalla
/// rota o, peor, nada — y en una terminal de cobro "no pasó nada" es
/// indistinguible de "sí se guardó".
///
/// Punto único para que las ~15 vistas no repitan el mismo
/// `replaceFirst('Exception: ', '')` cada una a su manera.
String mensajeDeError(Object error) {
  var texto = error.toString();

  // `Exception: algo` -> `algo`. Es el formato que produce `throw
  // Exception(...)`, que es como los controladores devuelven sus mensajes.
  texto = texto.replaceFirst('Exception: ', '');

  // Si aun así llega algo crudo de SQLite, no tiene sentido enseñárselo a
  // quien está cobrando: no puede hacer nada con "DatabaseException(UNIQUE
  // constraint failed: Producto.codigo_barras (code 2067))".
  if (texto.contains('DatabaseException') || texto.contains('SqliteException')) {
    return 'No se pudo completar la operación. Vuelve a intentarlo y, si '
        'sigue fallando, avisa al administrador.';
  }

  return texto;
}
