# Fase 2 — Fundación de red (cliente de sincronización)

Primer paso para convertir esta app en el cliente offline-first de EsqPOS
(ver `docs/sync-desktop-fase2.md` en el repo `EsqueletoPOS`, que describe el
contrato completo del lado del servidor). Esta fase construye **solo la capa
de red**: login/refresh/logout contra el backend y las llamadas al contrato
`/api/sync`. **No toca el esquema SQLite** (`lib/core/database/database_helper.dart`)
ni persiste nada localmente todavía — eso es el siguiente paso.

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

## Verificado

El SDK de Flutter se instaló después (clon de `flutter/flutter` rama
`stable`, ver `C:\flutter`) y este código quedó verificado de verdad:

```bash
flutter pub get     # OK -- http agregado como dependencia directa
flutter analyze     # 0 issues en lib/core/sync y lib/core/config
flutter test        # 302/302 (267 preexistentes + 35 nuevos), todo verde
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
