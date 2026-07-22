# Fase 3 — Motor de sincronización

Conecta las dos orillas que dejó la Fase 2 (`README-fase2.md`): el backend
acepta pull/push en `/api/sync`, el Flutter sabe llamarlos y tiene
`guid_sync`/`Sync_Outbox` en el esquema local, pero nada traducía una fila
local al formato del backend (o viceversa), nadie escribía en el outbox, y
no había bucle de sincronización. Esta fase construye ese puente completo.

## Qué hay

- `entities/` — mapeo bidireccional. `entity_mapper.dart` define el
  contrato `EntityMapper` (`aBackend`/`upsertLocal`) y `FkResolver`
  (traduce `guid_sync <-> id local`, con caché por ciclo). `entity_mapper_
  registry.dart` indexa un `EntityMapper` por cada una de las 14 entidades
  sincronizables con push habilitado, más `ordenPull` (orden padre-antes-
  que-hijo). `simple_catalog_mapper.dart` cubre catálogos "id + escalares"
  de forma declarativa (`Categoria`/`Cliente`/`Proveedor`); el resto
  (`Producto`, `Stock`, `Promocion`, `Venta`+`Detalle`+`Pago`+`Promocion`,
  `CajaSesion`, `Movimiento*`, `CorteCaja`) tiene su propia clase por
  lógica de negocio propia. `enums_backend.dart` centraliza las tablas de
  conversión de enums compartidas entre mappers.
- `sucursal/` — `SucursalesClient` (`GET /api/sucursales`) y
  `SucursalResolver`: el login puede devolver `sucursalId: null`, así que
  se resuelve una (la `esPrincipal`) la primera vez y se cachea en
  `Sync_Config`.
- `bitacoras/` — `MovimientoInventarioLogger`/`MovimientoCajaLogger`/
  `CorteCajaLogger`: llenan las 3 tablas de bitácora nuevas
  (`Movimiento_Inventario`, `Movimiento_Caja`, `Corte_Caja`) en cada punto
  de escritura real de los controladores (Producto/Ventas/Compras/
  Devoluciones/Caja), vía `SyncOutboxWriter`.
- `outbox/` — `SyncOutboxWriter` (reemplaza `DatabaseHelper.
  insertarConGuidSync` en todo punto de escritura sincronizable: inserta/
  actualiza Y encola en la misma transacción) y `SyncOutboxDrainer` (drena
  `Sync_Outbox` hacia `POST /api/sync/push` en lotes de 25).
- `pull/` — `SyncPullRunner` (pull incremental paginado por entidad,
  cursor en `Sync_Pull_Estado`) y `SyncPullCursorStore`.
- `sync_engine.dart` — `SyncEngine.sincronizarUnaVez()`: orquesta todo en
  un ciclo (resolver sucursal -> pull -> drenar outbox -> pull extra de lo
  `OmitidoServidorGana`).

## Decisiones de diseño

- **Casing verificado, no asumido**: el backend sirve JSON en camelCase
  (default de ASP.NET Core MVC, `Program.cs` sin `PropertyNamingPolicy`
  explícito) y deserializa el push con `PropertyNameCaseInsensitive =
  true`. Todo mapper produce/consume camelCase.
- **`UsuarioId` de sync ≠ `id_usuario` local**: todo campo `UsuarioId` que
  pide el backend es el usuario de la sesión de sincronización (Guid,
  `AuthService.sesionActual.usuarioId`), nunca el cajero local (login
  bcrypt contra `pos.db`, sistema de identidad completamente aparte). Esto
  deja un gap real y documentado: `CajaSesionMapper.upsertLocal` no puede
  insertar una `CajaSesion` abierta en OTRO dispositivo (su `Usuarios.
  id_usuario` local NOT NULL con FK no tiene contraparte), así que solo
  actualiza sesiones que el propio dispositivo ya conoce.
- **`AuthService.instancia`**: única instancia compartida por toda la app
  (`_sesionActual` es un campo de instancia, no estático). Todo
  controlador que usa `SyncOutboxWriter` construye el suyo apuntando a
  `AuthService.instancia`, para que todos vean la misma sesión.
- **Participantes de Promocion/VentaPromocion NO se sincronizan**
  (`Promocion_Productos`/`Promocion_Categorias`/`Promocion_Combo_Items`/
  `Venta_Promociones_Detalle`): el backend limpia toda propiedad de
  navegación de un push (`LimpiarNavegaciones`, evita cascadas no
  deseadas) y el pull tampoco las trae pobladas hoy (sin `.Include(...)`).
  Sincronizarlas de verdad necesita tocar ambos lados y quedó fuera de
  esta fase a propósito (ver los comentarios en `promocion_mapper.dart`/
  `venta_promocion_mapper.dart`).
- **`Inventario`/`Stock` es pull-only**: el Flutter nunca sube su
  inventario directo (los ajustes viajan como `MovimientoInventario`), así
  que sigue usando `DatabaseHelper.insertarConGuidSync` sin pasar por
  `SyncOutboxWriter` (que rompería con `UnsupportedError` si se intentara).
- **Sentinela `intentos = -1`**: si `EntityMapper.aBackend` no puede armar
  el payload todavía (sucursal sin resolver, FK sin `guid_sync` aún),
  `SyncOutboxWriter` encola igual con `datos_json` vacío e `intentos = -1`
  en vez de perder la operación. `SyncEngine` las reintenta después de
  resolver la sucursal; `SyncOutboxDrainer` las ignora (nunca las
  selecciona para push).
- **Lotes de 25 en el drenado**: `AplicarCambioAsync` del backend hace
  `SaveChangesAsync` por ítem individual, sin transacción de lote ni
  try/catch en el `foreach` de `PushAsync` — si un ítem falla a mitad de
  un lote, los anteriores ya quedaron persistidos pero el cliente no
  recibe `resultados`. Lotes chicos acotan cuánto se pierde de vista por
  fallo; el reintento es seguro porque el push es idempotente por `Id`.

## Fuera de alcance (documentado, no un olvido)

- Sincronizar los participantes de Promocion/VentaPromocion (ver arriba).
- Propagar borrados (`isDeleted: true`) de catálogos hacia el local.
- `Compras`, `Devoluciones`, `CuentaCobrar`, `CuentaPagar`,
  `VentaDevolucion`: ninguna tiene entidad equivalente en
  `SyncEntidadRegistry` del backend hoy.
- Desde dónde/cuándo se dispara `SyncEngine.sincronizarUnaVez()` en la UI
  (temporizador, botón manual, badge en línea/sin conexión) — siguiente
  fase del roadmap general del proyecto.

## Verificado

```bash
flutter analyze   # 0 issues nuevos en lib/core/sync, lib/controllers
flutter test      # 404/404 (315 preexistentes de Fase 2 + ~89 nuevos de esta fase)
```

Cobertura con DB real en memoria (`abrirEnRuta`/`setTestDatabase`) para
migraciones y mappers; con `http.BaseClient` falso (sin red real) para
`SyncPullRunner`/`SyncOutboxDrainer`/`SyncEngine`/`SucursalResolver`. No se
volvió a levantar el backend real en Docker para esta fase (sí se hizo en
Fase 2, ver `README-fase2.md`) — sería el siguiente paso natural antes de
dar la Fase 3 por cerrada del todo: un smoke test end-to-end (crear
producto/venta offline, sincronizar, confirmar en el backend real; editar
en el backend, hacer pull, confirmar en el Flutter).
