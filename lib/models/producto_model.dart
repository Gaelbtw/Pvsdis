class Producto {
  final int? idProducto;
  final String nombre;
  final String descripcion;
  final double precio;
  final int stockMinimo;
  final String estado;
  final double? precioCompra;
  final int? categoriaId;
  final String? categoriaNombre;
  final String? codigoBarras;

  /// Clave interna del catálogo (etiqueta impresa, lista de precios, conteo
  /// físico). Es distinta del código de barras: el de barras lo trae el
  /// fabricante en el empaque, el SKU lo define el negocio y existe también
  /// para lo que se vende a granel o sin empaque. Opcional y único.
  final String? sku;

  /// IVA de ESTE producto, en porcentaje. `null` significa "usa la tasa
  /// general de Configuración" (ver [ivaEfectivo]), que es como se comportaba
  /// todo el catálogo antes de que el IVA fuera por producto.
  final double? ivaTasa;

  const Producto({
    this.idProducto,
    required this.nombre,
    required this.descripcion,
    required this.precio,
    this.stockMinimo = 5,
    this.estado = "Activo",
    this.precioCompra,
    this.categoriaId,
    this.categoriaNombre,
    this.codigoBarras,
    this.sku,
    this.ivaTasa,
  });

  /// Normaliza un código de barras ingresado por el usuario: recorta
  /// espacios y convierte cadenas vacías a `null`, para no guardar `""`
  /// como si fuera un valor real (evita falsos duplicados/columna sucia).
  static String? normalizarCodigoBarras(String? valor) {
    final limpio = valor?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  /// Mismo criterio que [normalizarCodigoBarras] para el SKU: vacío = sin
  /// clave, no una clave vacía. Sin cambiar mayúsculas/minúsculas: hay
  /// negocios que distinguen `A-100` de `a-100` en sus etiquetas, y
  /// "corregir" lo que el usuario tecleó rompería la coincidencia con lo que
  /// tiene impreso.
  static String? normalizarSku(String? valor) {
    final limpio = valor?.trim();
    return (limpio == null || limpio.isEmpty) ? null : limpio;
  }

  /// Deja la tasa en un rango con sentido (0-100%) o la descarta. Un campo
  /// vacío, un texto que no es número o un valor fuera de rango se traducen a
  /// `null` = "usa la tasa general", que es el default seguro.
  static double? normalizarIvaTasa(String? valor) {
    final limpio = valor?.trim().replaceAll('%', '');
    if (limpio == null || limpio.isEmpty) return null;

    final tasa = double.tryParse(limpio);
    if (tasa == null || tasa < 0 || tasa > 100) return null;
    return tasa;
  }

  /// Tasa de IVA que realmente aplica a este producto: la suya si la tiene,
  /// si no la general del negocio. Es el único lugar donde se decide eso, para
  /// que el ticket, los reportes y la sincronización no puedan discrepar.
  double ivaEfectivo(double tasaGeneral) => ivaTasa ?? tasaGeneral;

  /// Margen sobre el precio de venta, en porcentaje. `null` si no hay precio
  /// de compra registrado o el precio es cero: sin costo no hay margen que
  /// calcular, y devolver 0 haría pasar "no sé" por "no ganas nada".
  double? get margenPorcentaje {
    final costo = precioCompra;
    if (costo == null || precio <= 0) return null;
    return ((precio - costo) / precio) * 100;
  }

  /// Precio de venta necesario para obtener [margen] % sobre el precio (no
  /// sobre el costo) partiendo de [costo]. Es la operación inversa de
  /// [margenPorcentaje], para poder capturar "quiero ganar 30%" en vez de
  /// calcular el precio a mano. `null` si el margen no es alcanzable (100% o
  /// más exigiría un precio infinito).
  static double? precioParaMargen({required double costo, required double margen}) {
    if (margen < 0 || margen >= 100) return null;
    return costo / (1 - margen / 100);
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'precio_compra': precioCompra,
      'id_categoria': categoriaId,
      'estado': estado,
      'stock_minimo': stockMinimo,
      'codigo_barras': normalizarCodigoBarras(codigoBarras),
      'sku': normalizarSku(sku),
      'iva_tasa': ivaTasa,
    };

    if (idProducto != null) {
      map['id_producto'] = idProducto;
    }

    return map;
  }

  /// Copia el producto cambiando solo lo que se indique.
  ///
  /// Existe por un defecto concreto: el dialogo de edicion rapida construia un
  /// `Producto` nuevo a mano con los tres campos que edita, y como [toMap]
  /// escribe todas SUS claves, los demas se sobreescribian con lo que trajera
  /// el objeto nuevo. Asi se perdian en silencio `precio_compra` (quedaba
  /// NULL), `descripcion` (quedaba vacia) y `stock_minimo` (se pisaba con el
  /// global de Configuracion) cada vez que alguien corregia un precio.
  ///
  /// El dialogo ya intentaba defenderse pasando a mano `codigo_barras`, `sku`
  /// e `iva_tasa`, con un comentario que explicaba el peligro. Esa defensa no
  /// escala: cada columna nueva es una oportunidad de olvidarla. Con esto, lo
  /// que no se nombra viene de la fila original y no hay nada que recordar.
  Producto copyWith({
    int? idProducto,
    String? nombre,
    String? descripcion,
    double? precio,
    int? stockMinimo,
    String? estado,
    double? precioCompra,
    int? categoriaId,
    String? categoriaNombre,
    String? codigoBarras,
    String? sku,
    double? ivaTasa,
  }) {
    return Producto(
      idProducto: idProducto ?? this.idProducto,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      precio: precio ?? this.precio,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      estado: estado ?? this.estado,
      precioCompra: precioCompra ?? this.precioCompra,
      categoriaId: categoriaId ?? this.categoriaId,
      categoriaNombre: categoriaNombre ?? this.categoriaNombre,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      sku: sku ?? this.sku,
      ivaTasa: ivaTasa ?? this.ivaTasa,
    );
  }

  factory Producto.fromMap(Map<String, dynamic> map) {
    return Producto(
      idProducto: map["id_producto"],
      nombre: map["nombre"],
      descripcion: map["descripcion"] ?? "",
      precio: map["precio"],
      //categoria: map["categoria"] ?? "",
      stockMinimo: map["stock_minimo"] ?? 5,
      estado: map["estado"] ?? "Activo",
      precioCompra: map["precio_compra"],
      categoriaId: map["id_categoria"],
      categoriaNombre: map["categoria_nombre"],
      codigoBarras: map["codigo_barras"],
      sku: map["sku"],
      ivaTasa: (map["iva_tasa"] as num?)?.toDouble(),
    );
  }
}
