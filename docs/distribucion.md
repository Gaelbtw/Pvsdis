# Distribución de Pv Control

Plan para poner el POS en manos de clientes reales. Tres capas: **entrega
técnica**, **licenciamiento** y **modelo comercial**. Escala objetivo inicial:
5-30 negocios, instalados por ti (presencial o remoto).

Este documento es una propuesta, no describe código existente. Lo que sí existe
hoy está marcado como **[ya está]**.

---

## Qué ya tienes resuelto

- **[ya está]** Instalador Inno Setup con `AppId` fijo → actualizar reinstala en
  el mismo lugar en vez de crear una copia paralela.
- **[ya está]** Datos en `%APPDATA%\2A2G Company\Pv Control\` → el instalador y
  el desinstalador no los tocan. Reinstalar no borra al cliente.
- **[ya está]** Versión del instalador tomada de `pubspec.yaml`, imposible de
  desincronizar.
- **[ya está]** `CloseApplications=yes` → no deja el POS a medio actualizar.
- **[ya está]** Respaldo automático del `.db` antes de cada migración, con
  `wal_checkpoint` previo.

Eso es más de lo que tiene la mayoría de los POS locales del mercado. Lo que
falta es todo lo que pasa **después** de que el .exe sale de tu máquina.

---

## Capa 1 — Entrega técnica

### 1.1 Firma de código

Hoy el instalador va sin firmar. Consecuencia concreta: Windows muestra
*"Windows protegió tu PC"* y el botón para continuar está escondido tras "Más
información". Con 5 clientes que instalas tú, das clic y ya. Con 20 instalando
solos por WhatsApp, la mitad se detiene ahí y te llama.

Opciones y costos aproximados (2026, verifica antes de comprar):

| Opción | Costo | Notas |
|---|---|---|
| **Azure Trusted Signing** (Basic) | ~$9.99 USD/mes, 5,000 firmas | Sin token físico. Certificados de ~3 días que se renuevan solos. **La opción sensata a tu escala.** |
| OV tradicional | ~$370-440 USD/año | Requiere token hardware o HSM desde 2023. |
| EV tradicional | ~$250-625 USD/año | **Ojo:** desde marzo 2024 Microsoft ya no le da reputación SmartScreen inmediata al EV. Pagar EV por eso ya no aplica. |

La reputación en SmartScreen se acumula por volumen de descargas limpias, y se
reinicia parcialmente con cada build nuevo. Con 30 clientes nunca vas a acumular
volumen — por eso importa firmar (identifica al publicador) pero no esperes que
la advertencia desaparezca de inmediato.

Al `.iss` le falta también:

```pascal
[Setup]
LicenseFile=..\..\docs\EULA.txt
SignTool=firmar $f
```

### 1.2 Canal de actualizaciones

Regla número uno de un POS: **una actualización nunca se aplica sola a media
venta.** Si le tumbas la caja a una tienda un sábado, perdiste al cliente.

**Fase A (0-10 clientes) — manual, es suficiente.**
Publicas `PvControl-Setup-X.Y.Z.exe` en un enlace fijo (Drive, R2, GitHub
Releases) junto a:

- `SHA256` del archivo, para que el cliente verifique que bajó lo tuyo.
- `CHANGELOG.md` en español de negocio, no de programador: *"Ahora el corte X
  muestra las devoluciones del turno"*, no *"fix: cast en corte_x_service"*.

Lo mandas por WhatsApp, el cliente lo corre. El instalador ya conserva sus datos.

**Fase B (10+ clientes) — aviso en la app.**
Un JSON estático en una URL fija:

```json
{
  "version": "1.3.0",
  "url": "https://.../PvControl-Setup-1.3.0.exe",
  "sha256": "…",
  "obligatoria": false,
  "notas": "Corte X ahora incluye devoluciones del turno."
}
```

La app lo consulta al abrir (con `package_info_plus` para conocer su versión),
compara, y si hay una nueva **muestra un aviso discreto, no un modal**. El botón
"Actualizar ahora" solo se habilita si:

- No hay venta en curso, y
- la caja está cerrada.

Al confirmar: descarga, verifica el SHA256, cierra la app y lanza
`Setup.exe /SILENT /CLOSEAPPLICATIONS`.

No construyas auto-update silencioso. En un POS el costo de una actualización
mal aplicada es mucho mayor que el ahorro de un clic.

### 1.3 Bloqueo de downgrade (esto te va a morder)

Escenario real: el cliente reinstala una versión vieja que tenía guardada, o le
mandas el instalador equivocado. La app abre una base con esquema v22 usando
código que espera v19. `sqflite` no baja versiones: lanza excepción, o peor, el
código lee columnas que no existen.

Antes de abrir, compara `PRAGMA user_version` con `_databaseVersion`:

```dart
if (versionArchivo > _databaseVersion) {
  throw BaseDeDatosMasNuevaException(
    'Esta base fue creada por una versión más reciente de Pv Control '
    '(esquema v$versionArchivo, esta app maneja v$_databaseVersion). '
    'Instala la versión más reciente; no abras esta base con esta versión.',
  );
}
```

Y muestra ese mensaje en pantalla, no un stack trace. Un cliente asustado que ve
un error rojo borra la carpeta.

### 1.4 Paquete de soporte

Un botón en Configuración → **"Generar paquete de soporte"** que produce un ZIP
con:

- Versión de la app y del esquema
- Últimas N líneas del log
- Estado del outbox de sync (pendientes, dead-letter)
- Fecha y tamaño del último respaldo
- **Sin datos de clientes ni de ventas**

El cliente te lo manda por WhatsApp. Esto sustituye media hora de
"¿y qué te dice exactamente?" por llamada. A 20 clientes, es la mejora de
soporte con mejor retorno que puedes construir.

### 1.5 Versionado

SemVer, con una regla adicional propia:

- **Cambio de esquema (`_databaseVersion` sube) → mínimo bump de MINOR.**
  Nunca metas una migración en un PATCH: el número de versión debe delatar que
  la base va a cambiar.
- El `+build` de `pubspec.yaml` es para ti; el cliente solo ve `X.Y.Z`.

---

## Capa 2 — Licenciamiento y activación

### 2.1 Qué es realista

Flutter compila a nativo AOT, así que no es tan fácil de destripar como .NET o
Java. Aun así, **cualquier validación local es rompible por alguien decidido.**
El objetivo no es detener a un cracker: es

1. evitar la copia casual ("pásame el instalador para mi otra tienda"), y
2. tener control administrativo de suscripciones y vencimientos.

### 2.2 Modelo recomendado: licencia firmada, verificada offline

Coherente con el producto (funciona 100% sin internet) y no requiere backend.

Tú tienes una llave privada **Ed25519**. La app trae embebida solo la **pública**.
Emites un archivo `.lic` por cliente:

```json
{
  "negocio": "Abarrotes La Esquina",
  "edicion": "pro",
  "cajas": 2,
  "emitida": "2026-08-12",
  "expira": "2027-08-12",
  "huella": "A3F2-9C1B-7E44"
}
```

Firmado, se guarda como `payloadBase64Url.firmaBase64Url`.

**Verificación en la app** (`package:cryptography`):

```dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Clave pública Ed25519 (32 bytes). La privada NUNCA sale de tu máquina.
const _clavePublica = <int>[/* 32 bytes */];

class LicenciaInvalidaException implements Exception {
  LicenciaInvalidaException(this.motivo);
  final String motivo;
  @override
  String toString() => motivo;
}

Future<Licencia> verificarLicencia(String contenido) async {
  final partes = contenido.trim().split('.');
  if (partes.length != 2) {
    throw LicenciaInvalidaException('Archivo de licencia con formato inválido.');
  }

  final payloadBytes = base64Url.decode(base64Url.normalize(partes[0]));
  final firmaBytes = base64Url.decode(base64Url.normalize(partes[1]));

  final valida = await Ed25519().verify(
    payloadBytes,
    signature: Signature(
      firmaBytes,
      publicKey: SimplePublicKey(_clavePublica, type: KeyPairType.ed25519),
    ),
  );
  if (!valida) {
    throw LicenciaInvalidaException(
      'La licencia no es auténtica o fue modificada.',
    );
  }

  return Licencia.fromJson(
    jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>,
  );
}
```

### 2.3 Huella de equipo tolerante

El error clásico es atar la licencia al serial del disco: el cliente cambia a
SSD y te habla furioso un domingo. Usa **tres señales y exige que coincidan dos**:

```dart
import 'dart:io';

/// MachineGuid: estable, cambia solo al reinstalar Windows.
Future<String> _machineGuid() async {
  final r = await Process.run('reg', [
    'query', r'HKLM\SOFTWARE\Microsoft\Cryptography',
    '/v', 'MachineGuid', '/reg:64',
  ]);
  final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
      .firstMatch(r.stdout.toString());
  return m?.group(1) ?? '';
}

/// UUID del equipo (BIOS): sobrevive a formateos y cambios de disco.
Future<String> _uuidEquipo() async {
  final r = await Process.run('powershell', [
    '-NoProfile', '-Command',
    '(Get-CimInstance Win32_ComputerSystemProduct).UUID',
  ]);
  return r.stdout.toString().trim();
}

/// Devuelve las 3 señales; el validador exige 2 de 3 iguales.
Future<List<String>> senalesEquipo() async => [
      await _machineGuid(),
      await _uuidEquipo(),
      Platform.localHostname,
    ];
```

**Flujo de activación, 2 minutos por cliente:**

1. Instala → la app muestra un **código de instalación** corto (hash de las
   señales, en base32, tipo `A3F2-9C1B-7E44`).
2. Te lo manda por WhatsApp.
3. Corres tu CLI: `dart run tool/emitir_licencia.dart --negocio "…" --huella A3F2-9C1B-7E44 --edicion pro --meses 12`
4. Le mandas el `.lic`, él lo importa desde la pantalla de activación.

### 2.4 Dónde se guarda

- Archivo `licencia.lic` en `%APPDATA%\2A2G Company\Pv Control\` — junto a
  `pos.db`, así **reinstalar no la borra**.
- Copia del hash en la tabla de configuración de SQLite.
- Si el archivo desaparece pero la copia en BD existe → licencia manipulada,
  no un reset de prueba gratis.

**Reloj hacia atrás:** guarda en BD el timestamp más alto visto. Si el reloj del
sistema retrocede respecto a ese valor, marca sospecha. No bloquees por eso
solo: los cambios de zona horaria y las pilas de BIOS muertas existen.

### 2.5 La regla que no se negocia

> **Una licencia vencida jamás debe impedir cobrar.**

Degradación correcta, en orden:

| Estado | Qué pasa |
|---|---|
| Vence en ≤15 días | Aviso al abrir, con fecha exacta. Todo funciona. |
| Vencida ≤30 días | Banner permanente. Todo funciona. |
| Vencida >30 días | Se bloquean **reportes, exportación, alta de productos y configuración**. Vender, cobrar, imprimir ticket y cerrar caja **siguen funcionando**. |

Un POS que deja de cobrar destruye tu reputación en el pueblo mucho más rápido
de lo que un cliente moroso te cuesta.

### 2.6 Cuándo migrar a activación online

Cuando pases de ~30 clientes o vendas suscripción de verdad. Ya tienes la
infraestructura: `EsqPos.API` con JWT, tenants y sucursales. Sería
`POST /api/licencias/activar` devolviendo una licencia firmada con caducidad
corta (30-60 días) que la app renueva en cada ciclo de sync. Misma verificación
Ed25519 en el cliente, solo cambia de dónde llega el archivo. Por eso conviene
diseñar hoy el formato de licencia pensando en eso: el trabajo no se tira.

---

## Capa 3 — Modelo comercial

### 3.1 Anclas del mercado mexicano (2026)

- Suscripciones en la nube: desde ~$800 MXN/mes; sistemas completos hasta
  ~$5,000 MXN/mes. PoloTab ronda $990 MXN/mes + IVA con hardware y soporte.
- Licencia vitalicia: SIFO desde ~$5,150 MXN.
- Hardware que el cliente compra aparte: impresora térmica ~$1,200 MXN,
  lector de códigos ~$600 MXN.

Tu ventaja competitiva real es **que funciona sin internet**. En un mercado
donde casi todo es SaaS en la nube, eso vale para tiendas con internet malo,
mercados y locales sin conexión fija. Véndelo así, explícitamente.

Tu desventaja es que **no timbras CFDI**. Dilo por escrito antes de vender o te
lo van a exigir gratis después.

### 3.2 Los tres modelos

| Modelo | A favor | En contra |
|---|---|---|
| **Pago único** | Fácil de vender a un changarro; es lo que esperan. | Ingreso no recurrente; das soporte gratis para siempre. |
| **Suscripción mensual** | Ingreso predecible, financia el desarrollo. | Resistencia inicial fuerte; exige activación con caducidad. |
| **Híbrido** ← recomendado | El pago inicial cubre tu tiempo de implementación y filtra curiosos; la mensualidad da caja. | Explicar dos conceptos en vez de uno. |

**Híbrido concreto para arrancar:**

- **Implementación (pago único):** instalación, carga del catálogo inicial,
  configuración de impresora y cajón, capacitación al personal.
- **Mensualidad:** actualizaciones, soporte por WhatsApp y respaldo en nube.

El respaldo en nube es el mejor argumento para que alguien pague mes a mes en un
producto local. Se le puede olvidar por qué paga por "actualizaciones"; nunca se
le olvida por qué paga porque no perderá el inventario si se quema la
computadora.

### 3.3 Ediciones (mapeadas a los módulos que ya existen)

| Edición | Incluye |
|---|---|
| **Básica** | Ventas, inventario, categorías, clientes, corte de caja, tickets. 1 caja. |
| **Pro** | + apartados, promociones, devoluciones, compras y cuentas por pagar, múltiples usuarios con permisos, reporte de utilidad, auditoría. |
| **Multisucursal** | + sincronización con backend, consolidado entre sucursales. |

Que la edición sea un campo de la licencia (`"edicion": "pro"`) y que los
permisos ya existentes en `core/security` la consulten. No hagas builds
distintos por edición: un solo binario, una licencia que habilita.

### 3.4 Lo que se cobra aparte (aquí está el dinero real)

- **Carga inicial del catálogo.** Es lo que más le duele al cliente y lo que más
  tiempo te consume. Cóbralo por rango de productos. Ya tienes utilidades CSV,
  úsalas para que te salga barato a ti y caro a él.
- Configuración de impresora térmica y cajón de dinero.
- Capacitación adicional o cambio de personal.
- Visita en sitio fuera de la zona.
- Recuperación de datos por falla del cliente.

### 3.5 Lo legal que no puedes saltarte

1. **EULA en el instalador** (`LicenseFile=` en el `.iss`, hoy no está). Debe
   decir: los datos son del cliente, límite de responsabilidad, y que el
   software no es un sistema de facturación fiscal.
2. **Aviso de privacidad.** La app guarda datos de clientes finales. El
   responsable del tratamiento es el negocio, no tú — déjalo escrito.
3. **Responsabilidad del respaldo.** Define en contrato de quién es. Si vendes
   respaldo en nube, ahí sí es tuya, y entonces tiene que funcionar.
4. **Alcance del soporte por escrito.** Horario y tiempo de respuesta. Sin esto,
   "soporte" significa WhatsApp a las 11 de la noche del domingo.

---

## Ruta por fases

**Fase 1 — primeros 5 clientes**
Sin licenciamiento técnico. Instalas tú, contrato en papel, updates por WhatsApp.
Todo el esfuerzo va a que el producto no falle y a aprender qué te piden.
Construir un servidor de licencias antes de tener 5 clientes es procrastinación
disfrazada de ingeniería.

**Fase 2 — 5 a 15 clientes**
1. Firmar el instalador (Azure Trusted Signing).
2. Licencia Ed25519 offline + CLI emisor.
3. Bloqueo de downgrade de esquema.
4. Botón de paquete de soporte.
5. EULA en el instalador.

**Fase 3 — 15 a 30 clientes**
6. Aviso de actualización dentro de la app (con caja cerrada).
7. Respaldo automático a nube como gancho de la mensualidad.
8. Activación online contra `EsqPos.API`.

**Todavía no:** panel de administración de clientes, telemetría, auto-update
silencioso, portal de autoservicio, revendedores. Todo eso se justifica pasando
los 30 clientes, no antes.

---

## Fuentes

- [Trusted Signing para desarrolladores individuales — Microsoft](https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-is-now-open-for-individual-developers-to-sign-up-in-public-previ/4273554)
- [Costo de Azure Trusted Signing — G.D.G. Software](https://www.gdgsoft.com/faq/azure-trusted-signing-cost-effective-exe-code-signing)
- [EV vs OV code signing — SSL.com](https://www.ssl.com/faqs/which-code-signing-certificate-do-i-need-ev-ov/)
- [¿Cuánto cuesta un punto de venta en México? — Pulpos](https://pulpos.com/blog/cuanto-cuesta-un-punto-de-venta-en-promedio/)
- [Cuánto cuesta un POS en México, guía 2026 — PoloTab](https://www.polotab.com/blog/cuanto-cuesta-un-sistema-de-punto-de-venta-en-mexico)
- [Precios de software punto de venta México](https://puntodeventa.com.mx/blog/precios-de-software-punto-de-venta.php)
