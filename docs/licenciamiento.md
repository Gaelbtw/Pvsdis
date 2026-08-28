# Licenciamiento — cómo funciona y cómo se enciende

El módulo está construido, probado y **apagado**. Este documento dice cómo se
enciende, cómo se emite una licencia y qué NO hacer.

> **Hoy no lo necesitas.** Con menos de cinco clientes, instalados
> presencialmente y con contrato en papel, el licenciamiento técnico no aporta
> nada y sí agrega una forma nueva de que a alguien se le caiga la caja un
> sábado. Enciéndelo cuando alguien te diga *"pásame el instalador para mi otra
> tienda"*, o cuando pases de unos cinco clientes.

---

## Cómo está apagado

`lib/core/licencia/clave_publica.dart` trae la lista de bytes vacía. Con eso:

- `LicenciaService.instancia.activo` es `false`.
- El estado es siempre `sinLicencia`.
- `EstadoLicencia.permite(...)` devuelve `true` para todo.
- La pantalla de Licencia dice *"Esta versión no requiere licencia"*.

Instalar esta versión en un cliente existente no cambia absolutamente nada para
él. Eso es deliberado y hay pruebas que lo sostienen (`test/licencia_test.dart`,
grupo *Degradación*).

---

## Encenderlo

### 1. Generar el par de llaves (una sola vez en la vida)

```powershell
dart run tool/emitir_licencia.dart generar-llaves --salida C:\llaves\pvcontrol
```

Produce `pvcontrol.privada` y `pvcontrol.publica`, e imprime la clave pública ya
formateada.

### 2. Pegar la clave pública

Copia la lista que imprimió el comando en
`lib/core/licencia/clave_publica.dart` y recompila. Desde ese momento la
compilación verifica licencias.

### 3. Guardar la privada

`C:\llaves\pvcontrol.privada` va **fuera del repositorio**, con al menos dos
copias en dos lugares distintos. El `.gitignore` ya ignora `*.privada`,
`*.publica`, `*.lic` y `llaves/`, pero eso solo evita el accidente: la
responsabilidad de dónde vive el archivo es tuya.

> **Si pierdes la llave privada no hay recuperación.** Ninguna licencia nueva
> será aceptada por las versiones ya instaladas. Tendrías que generar otro par,
> publicar una versión con la clave pública nueva, instalarla en cada cliente y
> reemitir todas las licencias vigentes. Trátala como el respaldo del negocio.

---

## Emitir una licencia (dos minutos)

1. El cliente abre **Configuración → Licencia** y oprime **Copiar**. Le manda
   por WhatsApp algo como `A3F2-9C1B-7E44`.

2. Tú emites:

   ```powershell
   dart run tool/emitir_licencia.dart emitir `
       --llave   C:\llaves\pvcontrol.privada `
       --negocio "Abarrotes La Esquina" `
       --huella  A3F2-9C1B-7E44 `
       --edicion pro `
       --meses   12
   ```

   El comando verifica lo que acaba de firmar antes de escribirlo, e imprime un
   mensaje listo para copiar y pegar en WhatsApp.

3. El cliente guarda el `.lic`, entra a **Configuración → Licencia →
   Importar archivo de licencia** y lo elige.

Para comprobar un archivo ya emitido:

```powershell
dart run tool/emitir_licencia.dart verificar --llave C:\llaves\pvcontrol.privada archivo.lic
```

---

## Qué pasa cuando vence

| Situación | Qué ve el cliente | Qué se bloquea |
|---|---|---|
| Faltan más de 15 días | Nada | Nada |
| Faltan 15 días o menos | Aviso al abrir | Nada |
| Venció hace ≤ 30 días | Banner permanente | Nada |
| Venció hace > 30 días | Banner permanente | Reportes, exportación, alta de productos y configuración |
| Licencia de otro equipo | Banner, con el código nuevo a la mano | Igual que la vencida |
| Archivo alterado o ausente | Banner explicativo | Igual que la vencida |

**Vender, cobrar, imprimir el ticket y cerrar caja no se bloquean nunca**, en
ninguna de las filas de arriba. Hay una prueba (`COBRAR NUNCA SE BLOQUEA`) que
truena si alguien mete una función de cobro en `FuncionLicenciada`.

La razón no es generosidad: un punto de venta que deja de cobrar destruye tu
reputación en el pueblo mucho más rápido de lo que te cuesta un cliente moroso.
La degradación tiene que doler lo suficiente para que paguen, no dejar a un
negocio parado.

---

## Poner un candado en una función

`GuardaLicencia` resuelve el permiso y el mensaje. Una línea por punto de uso:

```dart
onTap: () async {
  if (!await GuardaLicencia.permite(context, FuncionLicenciada.reportes)) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReporteView()));
},
```

Está puesto en los cuatro puntos que degrada la licencia vencida:

| Función | Dónde |
|---|---|
| `reportes` | Configuración → Accesos → Reportes, y el KPI "Ventas de hoy" del inicio |
| `exportacion` | `ReporteView._exportarReporte` (Exportar CSV) |
| `altaProductos` | Botón "Nuevo producto" en `ProductosView` |
| `configuracion` | Entrada a `ConfiguracionView` desde el menú de la cuenta |

Dos decisiones a conservar si agregas más:

- **La pantalla de Licencia nunca se bloquea.** Si Configuración estuviera
  cerrada del todo, el cliente no podría activar la licencia que acaba de
  pagar. Por eso el diálogo del guarda ofrece "Ver licencia" en vez de solo
  negar.
- **Editar y vender productos existentes sigue permitido**, solo se bloquea dar
  de alta nuevos. El negocio sigue operando con el catálogo que ya tiene.

---

## La huella del equipo

Tres señales, **basta con que coincidan dos**:

| Señal | Sobrevive a | Cambia con |
|---|---|---|
| `MachineGuid` del registro | cambio de disco, renombrar la PC | reinstalar Windows |
| UUID del equipo (SMBIOS) | formatear, cambiar disco | cambiar tarjeta madre |
| Nombre del equipo | casi todo | que alguien lo renombre |

En la práctica:

- **Cambian el disco duro:** siguen las tres. No pasa nada.
- **Renombran la computadora:** siguen dos. No pasa nada.
- **Reinstalan Windows:** sobrevive una. Hay que reemitir. Es razonable, y el
  cliente ya te iba a hablar de todos modos.
- **Cambian la tarjeta madre:** es otra computadora. Hay que reemitir.

El código son tres grupos de cuatro caracteres, uno por señal, con un alfabeto
sin `I`, `L`, `O`, `U`, `0` ni `1` — porque alguien lo va a dictar por teléfono.

---

## Lo que esto NO es

**No es una barrera de seguridad.** Flutter compila a nativo AOT, lo que ayuda,
pero cualquier validación local es rompible por alguien decidido, y la clave
pública está dentro del `.exe` de cada cliente. El objetivo es:

1. evitar la copia casual —*"pásame el instalador para mi otra tienda"*—, y
2. tener control administrativo de vencimientos.

No intentes convertirlo en protección anticopia seria: el esfuerzo no se paga a
esta escala, y cada capa de ofuscación es una forma nueva de que la app falle en
una computadora que no puedes reproducir.

---

## Cuándo pasar a activación en línea

Cuando vendas suscripción de verdad, o pases de ~30 clientes. La
infraestructura ya existe (`EsqPos.API` con JWT, tenants y sucursales): sería un
`POST /api/licencias/activar` que devuelve una licencia firmada con caducidad
corta (30-60 días) que la app renueva en cada ciclo de sync.

**La verificación no cambia** — el mismo Ed25519, el mismo `Licencia`, el mismo
`LicenciaService`. Lo único distinto es de dónde llega el archivo. Por eso el
formato se diseñó así desde el principio: ese trabajo no se tira.
