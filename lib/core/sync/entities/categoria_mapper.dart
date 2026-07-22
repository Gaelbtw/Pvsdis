import 'simple_catalog_mapper.dart';

/// `Categorias` (local) <-> `CategoriaProducto` (backend, `ServidorGana`).
///
/// `Descripcion` del backend no tiene columna local equivalente (`Categorias`
/// solo guarda `nombre`) -- se omite del push, ver la nota de alcance en
/// `SimpleCatalogMapper`.
final categoriaMapper = SimpleCatalogMapper(
  entidadBackend: 'CategoriaProducto',
  tablaLocal: 'Categorias',
  columnaIdLocal: 'id_categoria',
  campos: const [
    CampoMapeo('nombre', 'nombre'),
  ],
);
