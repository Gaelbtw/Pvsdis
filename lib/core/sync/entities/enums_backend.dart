// Tablas de conversión entre los strings que usa el esquema local (algunas
// en SCREAMING_SNAKE, otras en minúsculas -- ver cada tabla de origen) y
// los nombres de enum del backend (serializados como string por
// `JsonStringEnumConverter`, ver `EsqPos.Domain.Enums`). Compartidas entre
// los mappers que necesitan la misma conversión (`Promocion`/
// `VentaPromocion` para tipo de promoción; `Venta`/`VentaPago` para método
// de pago) para no duplicar la tabla en cada archivo.

/// Local (`Promociones.tipo`, ver `promocion_model.dart` `TipoPromocion.
/// nombreDb`) <-> `EsqPos.Domain.Enums.TipoPromocion`.
const Map<String, String> tipoPromocionLocalABackend = {
  'PORCENTAJE_PRODUCTO': 'PorcentajeProducto',
  'MONTO_FIJO_PRODUCTO': 'MontoFijoProducto',
  'NXY': 'NxY',
  'DESCUENTO_CANTIDAD': 'DescuentoCantidad',
  'COMBO': 'Combo',
};
final Map<String, String> tipoPromocionBackendALocal = {
  for (final entry in tipoPromocionLocalABackend.entries) entry.value: entry.key,
};

/// Local (`'porcentaje'`/`'fijo'`, ver `TipoDescuento` en
/// `descuento_utils.dart`) <-> `EsqPos.Domain.Enums.TipoDescuentoPromocion`.
const Map<String, String> tipoValorLocalABackend = {'porcentaje': 'Porcentaje', 'fijo': 'Monto'};
const Map<String, String> tipoValorBackendALocal = {'Porcentaje': 'porcentaje', 'Monto': 'fijo'};

/// Local (`Ventas.metodo_pago`/`Venta_Pagos.metodo_pago`, texto libre
/// histórico -- ver comentario en `lib/core/utils/pagos_mixtos.dart`) <->
/// `EsqPos.Domain.Enums.MetodoPago`. Sin match exacto (case-insensitive) se
/// asume `'Efectivo'` -- el método más común y el que menos sorprende si el
/// dato local viniera en un formato inesperado.
String metodoPagoABackend(String metodoLocal) {
  switch (metodoLocal.trim().toLowerCase()) {
    case 'efectivo':
      return 'Efectivo';
    case 'tarjeta':
      return 'Tarjeta';
    case 'transferencia':
      return 'Transferencia';
    case 'mixto':
      return 'Mixto';
    default:
      return 'Efectivo';
  }
}
