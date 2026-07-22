import 'simple_catalog_mapper.dart';

/// `Proveedores` (local) <-> `Proveedor` (backend, `ServidorGana`).
///
/// `nombre` local se mapea a `razonSocial` backend (nombres de campo
/// distintos, mismo concepto). `direccion_fiscal` local no tiene
/// contraparte separada en el backend (que solo tiene una `Direccion`) --
/// se usa `direccion` para el push, `direccion_fiscal` queda fuera. Ni
/// `telefono` (TEXT en ambos lados, sin conversión) tiene ese problema.
/// `NombreContacto` y `Email` del backend no tienen columna local
/// equivalente -- se omiten del push, ver la nota de alcance en
/// `SimpleCatalogMapper`.
final proveedorMapper = SimpleCatalogMapper(
  entidadBackend: 'Proveedor',
  tablaLocal: 'Proveedores',
  columnaIdLocal: 'id_proveedor',
  campos: const [
    CampoMapeo('nombre', 'razonSocial'),
    CampoMapeo('direccion', 'direccion'),
    CampoMapeo('telefono', 'telefono'),
    CampoMapeo('rfc', 'rfc'),
  ],
);
