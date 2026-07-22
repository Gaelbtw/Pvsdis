import 'simple_catalog_mapper.dart';

/// `Clientes` (local) <-> `Cliente` (backend, `ServidorGana`).
///
/// `telefono` es `INTEGER` en el esquema local (`Clientes.telefono
/// INTEGER`) pero `string` en el backend (`Cliente.Telefono`) -- se
/// convierte en ambas direcciones. `Documento` y `LimiteCredito` del
/// backend no tienen columna local equivalente -- se omiten del push, ver
/// la nota de alcance en `SimpleCatalogMapper`.
final clienteMapper = SimpleCatalogMapper(
  entidadBackend: 'Cliente',
  tablaLocal: 'Clientes',
  columnaIdLocal: 'id_cliente',
  campos: [
    const CampoMapeo('nombre', 'nombre'),
    const CampoMapeo('direccion', 'direccion'),
    CampoMapeo(
      'telefono',
      'telefono',
      aBackend: (v) => v?.toString(),
      aLocal: (v) => v == null ? null : int.tryParse(v.toString()),
    ),
    const CampoMapeo('correo', 'email'),
  ],
);
