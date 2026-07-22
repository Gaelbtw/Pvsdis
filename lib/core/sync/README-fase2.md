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

## Sin verificar — necesita el SDK de Flutter

Este código se escribió **sin poder compilarlo**: el SDK de Flutter no
estaba instalado en el entorno donde se hizo este trabajo. Antes de darlo
por bueno hace falta, en orden:

```bash
flutter pub get
flutter analyze
flutter test
```

Se revisó a mano campo por campo contra los DTOs reales del backend
(`EsqPos.Application/DTOs/AuthDtos.cs` y `SyncDtos.cs`) y contra
`AuthController.cs`/`SyncController.cs` para los endpoints exactos, y se
corrigieron en revisión un `rethrow` inválido dentro de un operador
ternario (no compila en Dart) y el bug de mensaje-de-error incorrecto en
login descrito arriba. Aun así, sin el SDK no hay garantía de que compile
limpio en la primera pasada — típicamente quedan detalles de imports o
tipos que solo el analizador atrapa.

## Siguiente paso

Tablas espejo locales en `pos.db` con una columna `guid_sync` (el esquema
actual usa `INTEGER PRIMARY KEY AUTOINCREMENT`, insuficiente para
sincronizar sin colisiones entre dispositivos — ver
`docs/sync-desktop-fase2.md` §6 en el repo `EsqueletoPOS`), más una cola de
outbox para las operaciones locales pendientes de `push`. Ninguna de esas
piezas existe todavía; esta fase es solo la capa de transporte.
