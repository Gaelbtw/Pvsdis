# Fase 2 — Fundación de red + esquema local (cliente de sincronización)

Primer paso para convertir esta app en el cliente offline-first de EsqPOS
(ver `docs/sync-desktop-fase2.md` en el repo `EsqueletoPOS`, que describe el
contrato completo del lado del servidor). Cubre dos piezas: la **capa de
red** (login/refresh/logout contra el backend y las llamadas al contrato
`/api/sync`) y la **fundación del esquema local** (columna `guid_sync` +
tabla `Sync_Outbox`, ver más abajo). Ninguna de las dos conecta todavía con
la otra: no hay motor de sync real, solo la infraestructura que ese motor
va a necesitar.

## Esquema local: guid_sync + Sync_Outbox

Migración v17 → v18 en `lib/core/database/database_helper.dart`:

- Columna `guid_sync TEXT` (nullable, índice único) agregada a las tablas
  locales que espejan una entidad sincronizable del backend con
  correspondencia 1:1 clara: `Categorias`, `Producto`, `Clientes`,
  `Proveedores`, `Inventario`, `Ventas`, `Detalle_Venta`, `Venta_Pagos`,
  `Cajas`, `Promociones`, `Venta_Promociones`. Las filas existentes se
  backfillean con un GUID nuevo (`lib/core/utils/guid_generator.dart`, un
  generador v4 propio de ~15 líneas sobre `Random.secure()` — se evitó sumar
  un paquete `uuid` solo para esto, mismo criterio que el resto de la
  Fase 2).
- Tabla `Sync_Outbox` (esqueleto): cola de cambios locales pendientes de
  subir. Nadie escribe en ella todavía.

**Ya conectado** — cada controlador que crea una fila en una tabla
sincronizable le asigna `guid_sync` de inmediato, sin esperar al backfill de
la próxima apertura de la app:
`DatabaseHelper.insertarConGuidSync(db, tabla, values)` es el punto único
de esta lógica (envuelve `db.insert` agregando un GUID nuevo), usado en
`CategoriaController`, `ClienteController`, `ProveedorController`,
`ProductoController` (Producto + Inventario), `CajaController`
(`abrirCaja`), `PromocionesController`, `VentasController`
(Ventas/Detalle_Venta/Venta_Pagos/Venta_Promociones) y
`ApartadosController` (al liquidar, que crea una Venta real). Cubierto por
`test/guid_sync_en_creacion_test.dart`. Llamar a `db.insert(...)` directo
sobre una de estas tablas sigue funcionando (la fila solo queda sin
`guid_sync` hasta el próximo backfill), así que un controlador nuevo que se
olvide de usar el helper no rompe nada, solo pierde el "de una vez".

**Deliberadamente fuera de esta migración** (documentado, no un olvido):

1. **`MovimientoInventario`, `MovimientoCaja`, `CorteCaja`** (sí
   sincronizables del lado del backend) no tienen tabla local equivalente
   hoy: `Inventario.cantidad` se ajusta directo sin bitácora de movimientos,
   y `Cajas` guarda los totales de cierre ya agregados en vez de filas de
   movimiento individuales. Necesitan una decisión de diseño propia (¿tabla
   nueva para bitácora, o reconciliar contra lo agregado?) antes de poder
   sincronizarse.
2. **Tablas puente/detalle de promociones** (`Promocion_Productos`,
   `Promocion_Categorias`, `Promocion_Combo_Items`,
   `Venta_Promociones_Detalle`): aunque el backend también las trata como
   filas con identidad propia, se asumió que se van a repoblar completas
   junto con su fila padre en cada pull en vez de rastrearse una por una.
   Si el motor de sync termina necesitando otra cosa, agregarles
   `guid_sync` es una migración aparte.

Test de migración en `test/guid_sync_migration_test.dart` (mismo patrón que
`test/venta_pagos_migration_test.dart`): reconstruye a mano el esquema v17,
migra a v18, y verifica columna + backfill + índice único + no-reasignación
al reabrir. `test/guid_generator_test.dart` cubre el formato del GUID.

## Qué hay

- `lib/core/config/backend_config.dart` — URL base del backend (configurable
  en caliente), armado de URIs, timeout de red.
- `lib/core/sync/network/`
  - `api_exceptions.dart` — jerarquía de excepciones (`ErrorRed`,
    `ErrorRespuestaApi`, `SesionExpiradaException`).
  - `api_http_client.dart` — envoltorio delgado sobre `package:http`: arma
    la URL, serializa/deserializa JSON, traduce errores de transporte y
    códigos HTTP a las excepciones de arriba. No sabe nada de autenticación.
  - `jwt_utils.dart` — decodifica el payload de un JWT (sin verificar firma)
    para leer el claim `tenant_id`.
  - `token_storage.dart` — persiste la sesión (tokens + datos del usuario)
    en un archivo JSON en el directorio de datos de la app (`path_provider`,
    no `flutter_secure_storage` — ver el comentario en el archivo para el
    porqué).
  - `conectividad_probe.dart` — `GET /health` con timeout corto, para un
    badge en línea/sin conexión sin depender de `connectivity_plus`.
- `lib/core/sync/models/`
  - `sync_auth_models.dart` — espejo de `LoginDto`/`LoginResponseDto`/
    `RefreshTokenRequestDto` del backend, más `SesionSync` (snapshot
    persistido con el `tenant_id` ya decodificado).
  - `sync_dtos.dart` — espejo de `SyncPullResponseDto`/`SyncPushRequestDto`/
    `SyncPushResponseDto`.
- `lib/core/sync/auth_service.dart` — login/logout, caché en memoria de la
  sesión, refresco proactivo del access token (con margen de 60s antes de
  vencer) antes de cada llamada de sync.
- `lib/core/sync/sync_client.dart` — `obtenerEntidades()` / `pull()` /
  `push()`, agregando el header `Authorization` vía `AuthService`. Devuelve
  los elementos del pull como `Map<String, dynamic>` genérico (no hay
  todavía un modelo tipado por entidad — ver "Siguiente paso").

## Decisiones de diseño

- **`http` en vez de `dio`**: el proyecto no necesita interceptores,
  cancelación de requests en cadena, ni transformadores — un envoltorio de
  ~100 líneas sobre `http` cubre login/pull/push sin sumar una dependencia
  más pesada.
- **Sin `flutter_secure_storage`**: un archivo JSON plano en el directorio
  privado de la app (mismo nivel de protección que ya tiene `pos.db`, que
  guarda hashes bcrypt sin cifrado adicional). Si más adelante se necesita
  cifrado en reposo, el cambio queda contenido a `TokenStorage` (misma API
  pública).
- **Sin `connectivity_plus`**: un `GET /health` real contesta la pregunta
  que importa ("¿el backend responde AHORA?"), no solo si hay una interfaz
  de red activa.
- **Dos sesiones independientes**: la sesión de sincronización
  (`AuthService`, JWT contra el backend) es un sistema aparte del login
  local de cajeros (`Authcontroller`, bcrypt contra `pos.db`). Un
  dispositivo puede seguir vendiendo 100% offline con su sesión local
  aunque nunca haya iniciado sesión de sync, o esta esté vencida.
- **`SesionExpiradaException` vs. login fallido**: `ApiHttpClient` traduce
  todo 401 del backend a `SesionExpiradaException` (correcto para un
  request autenticado que dejó de serlo). Pero el backend también devuelve
  401 para credenciales inválidas en `/api/auth/login` (vía
  `UnauthorizedAppException`) — un tipo confuso para ese caso, porque el
  usuario está EN la pantalla de login, no hay sesión que "expiró".
  `AuthService.login()` recaptura ese caso puntual y lo relanza como
  `ErrorRespuestaApi`, conservando el mensaje real del backend
  ("Credenciales inválidas.", "La cuenta está temporalmente bloqueada...").

## Verificado también contra el backend real (no solo mocks)

Además de los tests con `http.Client` falso, se levantó el backend real vía
`docker compose` (imagen reconstruida con el código actual de EsqueletoPOS
-- incluye la Fase 1 de promociones y Cuentas por Pagar) y se corrió un
smoke test puntual (no committeado, se corrió y se borró) contra
`http://localhost:5242`: `ConectividadProbe.hayConexion()`,
`AuthService.login()` con el admin sembrado, `SyncClient.obtenerEntidades()`
y `SyncClient.pull('Producto')`. Los cuatro respondieron correctamente
-- login devolvió un JWT real con `tenant_id` decodificado bien, y la lista
de entidades coincidió exactamente con lo registrado en
`SyncEntidadRegistry` del backend (18 entidades). Esto prueba que el
contrato cliente-servidor funciona de punta a punta, no solo contra lo que
el propio código simula.

## Verificado

El SDK de Flutter se instaló después (clon de `flutter/flutter` rama
`stable`, ver `C:\flutter`) y este código quedó verificado de verdad:

```bash
flutter pub get     # OK -- http agregado como dependencia directa
flutter analyze     # 0 issues en lib/core/sync y lib/core/config
flutter test        # 315/315 (267 preexistentes + 48 nuevos: red + guid_sync + creación), todo verde
```

Antes de tener el SDK se revisó a mano campo por campo contra los DTOs
reales del backend (`EsqPos.Application/DTOs/AuthDtos.cs` y `SyncDtos.cs`)
y contra `AuthController.cs`/`SyncController.cs` para los endpoints
exactos, y se corrigieron en esa revisión un `rethrow` inválido dentro de
un operador ternario (no compila en Dart) y el bug de tipo de excepción en
login descrito arriba. Al correr los tests reales tras instalar el SDK
apareció un tercer bug, más serio, que la revisión manual no podía haber
detectado:

**Bug de encoding (corregido):** `ApiHttpClient` usaba `respuesta.body`
para leer el cuerpo de cada respuesta. Ese getter de `package:http` cae a
**latin1** cuando el `Content-Type` no trae un `charset` explícito, y
corrompe en silencio cualquier tilde o `ñ` ("inválidas" → "invÃ¡lidas").
Como toda esta app habla español, esto habría afectado cualquier mensaje
de error del backend y cualquier campo de texto sincronizado (nombres de
producto, categoría, promoción, etc.). Se corrigió decodificando
`respuesta.bodyBytes` como UTF-8 de forma explícita, sin depender de que
el backend (o algún proxy/gateway en el medio) mande el charset. Cubierto
por tests en `test/api_http_client_test.dart` (mensajes con tildes en
título/detail de un 401/400 simulado).

**Tests nuevos** (`test/jwt_utils_test.dart`, `test/sesion_sync_test.dart`,
`test/api_http_client_test.dart`, `test/auth_service_test.dart`): cubren
`JwtUtils`, el vencimiento/roundtrip de `SesionSync`, la traducción de
código HTTP → excepción en `ApiHttpClient` (con `http.Client` falso vía
`http.BaseClient`, sin red real), y el flujo completo de `AuthService`
(login, logout best-effort, refresco proactivo del access token, y sus
casos de error). **No** hay test unitario de `TokenStorage` ni de
`ConectividadProbe` todavía: `TokenStorage` depende de `path_provider`
(plugin nativo) y este proyecto no tiene un patrón establecido para
mockearlo -- el que sí existe (`DatabaseHelper.abrirEnRuta`,
`@visibleForTesting`) resuelve el mismo problema exponiendo un método que
recibe la ruta directamente en vez de pedirla a `path_provider`; sería
natural aplicarle el mismo patrón a `TokenStorage` en un pase futuro.

## Siguiente paso

Tablas espejo locales en `pos.db` con una columna `guid_sync` (el esquema
actual usa `INTEGER PRIMARY KEY AUTOINCREMENT`, insuficiente para
sincronizar sin colisiones entre dispositivos — ver
`docs/sync-desktop-fase2.md` §6 en el repo `EsqueletoPOS`), más una cola de
outbox para las operaciones locales pendientes de `push`. Ninguna de esas
piezas existe todavía; esta fase es solo la capa de transporte.
