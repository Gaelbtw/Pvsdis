# Instalador de Windows (Pv Control)

Esta carpeta contiene todo lo necesario para empaquetar la app como un
instalador profesional de Windows con [Inno Setup 6](https://jrsoftware.org/isdl.php).

- `pos_installer.iss` — script de Inno Setup. Define qué se instala, dónde,
  los accesos directos y el desinstalador.
- `build_installer.ps1` — script de PowerShell que compila la app en modo
  Release y genera el instalador en un solo paso.

## Requisitos

1. **Flutter SDK** en el PATH (el mismo que usas para desarrollar).
2. **Inno Setup 6.3 o superior** instalado. Dos formas de instalarlo:
   - `winget install --id JRSoftware.InnoSetup -e`
   - o descargarlo de https://jrsoftware.org/isdl.php

No hace falta instalar nada más: el script encuentra `ISCC.exe`
automáticamente (PATH, o las rutas típicas de instalación por-máquina o
por-usuario).

## Generar un instalador nuevo (uso normal)

```powershell
powershell -ExecutionPolicy Bypass -File windows\installer\build_installer.ps1
```

Esto hace, en orden: `flutter clean` → `flutter pub get` →
`flutter build windows --release` → compila `pos_installer.iss` con Inno
Setup. El instalador queda en:

```
dist\PvControl-Setup-<version>.exe
```

La versión del instalador **se toma automáticamente de `pubspec.yaml`**
(campo `version:`), no hay que escribirla a mano en ningún lado. `dist\` no
se sube a git (está en `.gitignore`); es la carpeta de salida de cada build.

## Publicar una nueva versión para clientes existentes

1. Sube el número de versión en `pubspec.yaml` (ej. `1.0.0+1` → `1.1.0+2`).
2. Corre `build_installer.ps1` como arriba.
3. Entrega el `.exe` generado en `dist\` al cliente. Al ejecutarlo sobre una
   instalación existente, Inno Setup la detecta automáticamente (mismo
   `AppId`, ver más abajo), la actualiza en el mismo lugar y **conserva la
   base de datos del cliente sin ningún paso manual**.

Si la app está abierta en ese momento, el instalador pide cerrarla antes de
continuar (no la mata a la fuerza) — configurado con `CloseApplications` en
el `.iss`.

## Qué hace el instalador

- Instala en `C:\Program Files\Pv Control\` (requiere permisos de
  administrador).
- Crea acceso directo en el Menú Inicio y, opcionalmente, en el Escritorio
  (casilla marcada por defecto en el asistente).
- Registra un desinstalador estándar de Windows (aparece en
  "Aplicaciones y características").
- Copia **todo** el contenido real de
  `build\windows\x64\runner\Release\` (el `.exe`, las DLLs del motor de
  Flutter, `sqlite3.dll`, `pdfium.dll`, `printing_plugin.dll` y la carpeta
  `data\` con los assets) usando un wildcard, así que no hay una lista de
  archivos que se pueda desincronizar del build real.
- Idioma del asistente: español (con inglés como alternativa).

## Dónde vive la base de datos del cliente (y por qué se conserva sola)

La app **nunca** guarda `pos.db` dentro de la carpeta de instalación.
`DatabaseHelper` usa `path_provider`, que en Windows resuelve la ruta como:

```
%APPDATA%\<CompanyName>\<ProductName>\pos.db
%APPDATA%\<CompanyName>\<ProductName>\backups\
```

tomando `CompanyName` y `ProductName` directamente de la información de
versión del ejecutable (`windows\runner\Runner.rc`). Con los valores
actuales, eso es:

```
C:\Users\<usuario>\AppData\Roaming\2A2G Company\Pv Control\pos.db
```

Como esa carpeta queda **fuera** de `C:\Program Files\Pv Control\`, ni el
instalador ni el desinstalador la tocan nunca — por eso reinstalar,
actualizar o desinstalar conserva los datos del cliente automáticamente,
sin backups manuales ni pasos adicionales. Esto se verificó de punta a
punta: instalación silenciosa → la app crea `pos.db` en esa ruta →
desinstalación → `pos.db` sigue intacto.

### ⚠️ Regla importante: no cambiar `CompanyName` / `ProductName`

Esos dos valores están grabados en dos lugares que deben coincidir siempre:

- `windows\runner\Runner.rc` (`CompanyName`, `ProductName`)
- `windows\installer\pos_installer.iss` (`MyAppPublisher`, `MyAppName`)

**Una vez que un cliente tiene el POS instalado con datos reales, no se
deben volver a tocar.** Si se cambian, `path_provider` calcula una carpeta
de AppData distinta y la app "pierde de vista" la base de datos existente
(los datos no se borran, pero la app abre/crea una base nueva y vacía en la
carpeta nueva). Si algún día hace falta rebrandear el producto, hay que
migrar manualmente el `pos.db` del cliente a la carpeta nueva antes de
entregar esa versión.

### `AppId` fijo (no tocar)

`pos_installer.iss` tiene un `AppId` GUID fijo en `[Setup]`. Es lo que le
permite a Inno Setup reconocer una instalación existente en la máquina del
cliente y actualizarla en el mismo lugar (mismo `DefaultDirName`, mismo
grupo del menú inicio) en vez de instalar una copia en paralelo. No se
regenera entre versiones.

## Verificación realizada

Este instalador se probó de punta a punta antes de entregarlo:

- Compilación limpia con Inno Setup 6.7.3 (sin errores ni warnings).
- Instalación silenciosa (`/VERYSILENT`) → los 6 archivos + carpeta `data\`
  quedan copiados correctamente.
- La app instalada arranca, el título de la ventana muestra "Pv Control", y
  crea su base de datos en `%APPDATA%\2A2G Company\Pv Control\pos.db`.
- Desinstalación silenciosa → la carpeta de instalación se borra por
  completo, y `pos.db` en AppData permanece intacto.
- El `.exe` del instalador queda con el icono, versión (1.0.0) y nombre de
  producto ("Pv Control") correctos en sus propiedades de Windows.

## Icono del producto

El instalador y el ejecutable usan `windows\runner\resources\app_icon.ico`
(el mismo ícono para ambos). Ese archivo es todavía el ícono por defecto de
Flutter. Antes de la entrega final a un cliente, reemplázalo por el logo
real del negocio (mismo nombre de archivo, formato `.ico` multi-resolución)
y vuelve a correr `build_installer.ps1` — no hace falta tocar el `.iss` ni
el `.rc`, ambos ya apuntan a ese archivo.
