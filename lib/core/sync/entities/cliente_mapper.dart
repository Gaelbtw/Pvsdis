import 'simple_catalog_mapper.dart';

/// `Clientes` (local) <-> `Cliente` (backend, `ServidorGana`).
///
/// `telefono` es `TEXT` en ambos lados desde la v22 del esquema local, así
/// que ya no necesita conversión.
///
/// Antes la columna local era `INTEGER` y este mapeo hacía
/// `int.tryParse(v)` al bajar del backend: cualquier teléfono con formato
/// real ('+52 55 1234 5678', '55-1234-5678', con extensión) devolvía `null`
/// y el dato se perdía en silencio al sincronizar. `Documento` y
/// `LimiteCredito` del backend no tienen columna local equivalente -- se
/// omiten del push, ver la nota de alcance en `SimpleCatalogMapper`.
final clienteMapper = SimpleCatalogMapper(
  entidadBackend: 'Cliente',
  tablaLocal: 'Clientes',
  columnaIdLocal: 'id_cliente',
  campos: [
    const CampoMapeo('nombre', 'nombre'),
    const CampoMapeo('direccion', 'direccion'),
    const CampoMapeo('telefono', 'telefono'),
    const CampoMapeo('correo', 'email'),
  ],
);
