# pvapp — Punto de venta

POS de escritorio para Windows, configurable para cualquier tipo de comercio.
Funciona **100% sin internet**; la sincronización con el backend es opcional y
se activa por dispositivo.

- **Stack:** Flutter (Dart ^3.11) · SQLite vía `sqflite` + `sqflite_common_ffi`
- **Plataforma real:** Windows escritorio. El proyecto conserva las carpetas de
  Android/iOS/web del andamiaje de Flutter, pero no se compilan ni se prueban.
- **Backend opcional:** EsqPos.API (repositorio aparte)

---

## Arranque rápido

```bash
flutter pub get
flutter run -d windows          # desarrollo
flutter test                    # 80 archivos de prueba
flutter analyze                 # sin advertencias antes de subir
```

Instalador de Windows (Inno Setup):

```powershell
powershell -ExecutionPolicy Bypass -File windows\installer\build_installer.ps1
```

En el primer arranque la app **no trae usuario por defecto**: pide crear la
cuenta de administrador (`SetupAdminView`).

---

## Cómo está organizado

```
lib/
├── main.dart              Arranque: abre la BD, carga config, inicia sync
├── models/                Objetos de dominio (Producto, Venta, Caja…)
├── controllers/           Reglas de negocio + acceso a datos
├── views/                 Pantallas
├── widgets/               Componentes reutilizables
├── services/              Tickets PDF, impresión, cajón de dinero, export CSV
└── core/
    ├── database/          Esquema, migraciones e índices
    ├── security/          Hash de contraseñas, permisos, límite de intentos
    ├── session/           Usuario en sesión
    ├── sync/              Motor de sincronización con el backend
    ├── theme/             Colores, tipografía, radios
    ├── config/            Configuración del negocio en caché
    └── utils/             Cálculo de dinero, promociones, descuentos, CSV
```

Sin inyección de dependencias ni rutas nombradas: las vistas instancian sus
controladores y navegan con `MaterialPageRoute`. Es deuda conocida, no un
patrón a imitar en código nuevo.

---

## Decisiones que conviene entender antes de tocar nada

Están comentadas en el código, pero estas son las que más duele descubrir tarde.

### El dinero se recalcula en el controlador, nunca se confía a la UI

`VentasController.insertarVentaCompleta` **vuelve a evaluar** promociones y
total con `calcularVenta()` antes de guardar, ignorando lo que traiga la
pantalla. La fuente de verdad del monto cobrado es el controlador. Lo mismo con
el autorizador de un descuento: se verifica contra la base, no se confía en que
el diálogo ya pidió credenciales.

### Los importes se redondean en cada paso, no al final

`redondearMoneda()` (en `core/utils/money.dart`) se aplica en cada operación
intermedia para que el error de coma flotante no se acumule. Las columnas son
`REAL`; esta función es lo que da la garantía práctica que daría un `Decimal`.

### El costo de venta se congela en la línea

`Detalle_Venta.costo_unitario` guarda el `precio_compra` vigente **al cobrar**
(migración v22). `Producto.precio_compra` se sobrescribe con cada compra, así
que sin esa copia la utilidad histórica se recalcularía con el costo de hoy.
Las líneas anteriores a la v22 lo tienen en `NULL` y quedan fuera del reporte
de utilidad a propósito: no se puede inventar un costo pasado.

### El arqueo de caja es ciego para el cajero

`CajaView` oculta al cajero el efectivo esperado y la diferencia hasta que
confirma su conteo; el resultado se revela después, cuando ya no se puede
ajustar. El Corte X también lo omite, y el dashboard muestra `•••` en vez del
monto. Si se añade otro sitio que exponga `efectivoEsperado`, hay que decidir
conscientemente si el cajero puede verlo.

### La seguridad falla cerrada

`SessionManager` arranca **sin rol**: sin sesión no hay privilegios.
`requiredUserId` lanza excepción en vez de caer a un usuario por defecto — un
`?? 1` silencioso falsearía la auditoría y los reportes por usuario.

### La sincronización es offline-first y tolera un backend imperfecto

`Sync_Outbox` encola los cambios en la **misma transacción** que la escritura
local. El drenado usa un cursor `id > idMinimo` (sin él, un lote fallido se
reintentaría en bucle infinito) y distingue dos tipos de fallo: transporte
(reintenta indefinidamente) y rechazo del backend (tras N intentos va a
dead-letter). Los detalles y el porqué están en `lib/core/sync/README-fase3.md`.

### Nada carga tablas completas para pintarlas

`Auditorias` crece con cada operación y nunca se purga, así que se pagina en
SQL (`AuditoriaController.obtenerPagina`). Los filtros de búsqueda se resuelven
en el `WHERE`, no en Dart: filtrar en memoria obligaba a traer la tabla entera.
Si añades una vista de listado, pagina desde el principio.

---

## Base de datos

Un solo archivo SQLite en el directorio de datos de la app, junto a
`backups/` y `exportaciones/`.

- **Versión actual del esquema:** 24 (ver `_databaseVersion` en
  `core/database/database_helper.dart`, expuesta como
  `DatabaseHelper.versionEsquema`)
- **Antes de cada migración se respalda el archivo completo**, con
  `wal_checkpoint` previo para no dejar fuera transacciones que aún vivan en
  el `-wal`.
- Las migraciones son idempotentes (`PRAGMA table_info` o `IF NOT EXISTS`).

### No se puede abrir una base más nueva que la app

`abrirEnRuta` compara `PRAGMA user_version` con `_databaseVersion` **antes**
de abrir para escritura y lanza `BaseDeDatosMasNuevaException` si el archivo
viene de una versión más reciente.

Hace falta porque `sqflite` solo sabe subir de versión: si el archivo está
adelantado, `openDatabase` no se queja —no existe un `onDowngrade` que
dispare— y la app opera contra columnas que su esquema no conoce. El daño es
silencioso. Y el escenario es cuestión de tiempo: los instaladores se reparten
a mano por USB y WhatsApp, así que la copia vieja se queda para siempre en el
escritorio del cliente.

`main()` la atrapa y muestra `ErrorArranqueApp`, nunca un stack trace: un
cliente asustado que ve un error rojo borra la carpeta de datos "para que se
arregle".

### Al añadir una migración

1. Sube `_databaseVersion`.
2. Añade el bloque `if (oldVersion < N) { ... }` al final de `_onUpgrade`.
3. Actualiza también `_onCreate`, para que una instalación nueva nazca con el
   esquema correcto sin pasar por la migración.
4. Si reconstruyes una tabla con `_reconstruirTabla`, **incluye todas sus
   columnas actuales** —incluida `guid_sync`—: el helper solo copia las
   columnas presentes en ambas definiciones, y omitir una borra sus datos.
5. Prueba sobre una **copia** de una base real, no solo sobre una vacía.

---

## Pruebas

80 archivos en `test/`, ejecutables con `flutter test`. Cubren cálculo de
descuentos y promociones, pagos mixtos, apartados, devoluciones, cortes de
caja, permisos, el motor de sincronización y cada migración de esquema.

Los tests de base de datos usan `sqflite_common_ffi` contra un archivo
temporal y `DatabaseHelper.abrirEnRuta`, que ejerce exactamente la misma
secuencia de creación/migración que producción.

---

## Integración continua

`.github/workflows/ci.yml` corre en cada push:

| Job | Dónde | Qué |
|---|---|---|
| `analyze` | ubuntu | `flutter analyze` |
| `test` | **windows** | `flutter test` |
| `build` | **windows** | `flutter build windows --release` + artefacto |

Las pruebas corren en Windows a propósito: `sqflite_common_ffi` trae ahí su
propio `sqlite3.dll`, y los plugins del proyecto (`win32`, `window_manager`,
`printing`) solo existen en esa plataforma.

---

## Distribución

- **Instalador:** `windows/installer/build_installer.ps1` compila y empaqueta
  en un paso. La versión sale de `pubspec.yaml`; el EULA que muestra el
  asistente está en `docs/EULA.txt` (ASCII puro: Inno lee los `.txt` de
  `LicenseFile` como ANSI salvo que traigan BOM UTF-8).
- **Paquete USB:** `windows/installer/usb/` — VC_redist, instalador, script de
  respaldo automático y `LEEME.txt` para el cliente. No requiere internet en la
  PC del negocio.
- **Respaldo externo:** `respaldo.ps1` deja un marcador
  (`ultimo_respaldo_externo.txt`) junto a `pos.db` en cada corrida exitosa.
  Configuración → Sistema y soporte lo lee y avisa en rojo a partir de
  `DatabaseBackupController.diasParaAvisoRespaldo` días sin respaldar. Sin ese
  aviso, una USB desconectada hace semanas se descubre el día que muere el
  disco.
- **Reporte de soporte:** Configuración → Sistema y soporte genera un `.txt`
  con versiones, conteos y estado del outbox, **sin datos de clientes ni de
  ventas**, para mandarlo por WhatsApp.
- **Licencia:** construida y **apagada**. `lib/core/licencia/` verifica
  archivos `.lic` firmados con Ed25519, sin internet, y `tool/emitir_licencia.dart`
  los emite. Mientras `clavePublicaLicencias` esté vacía,
  `LicenciaService.activo` es `false`, el estado es siempre `sinLicencia` y todo
  funciona sin restricción. Encenderlo es pegar 32 bytes y recompilar — ver
  [`docs/licenciamiento.md`](docs/licenciamiento.md).
- **Firma del instalador:** opcional, vía `build_installer.ps1 -Firmar`. Sin
  ella el build no falla y el `LEEME.txt` de la USB explica al cliente la
  pantalla de SmartScreen.
- **Papeleo del cliente:** contrato de servicio, aviso de privacidad, checklist
  de instalación y registro de instalaciones están en `docs/` — ver
  [`docs/README.md`](docs/README.md) para el orden de un cliente nuevo.
- **Qué falta antes de escalar:** firmar el instalador (Azure Trusted Signing),
  licencia Ed25519 offline con su CLI emisor, y aviso de actualización dentro
  de la app. Solo aplica pasando los ~5 clientes.
