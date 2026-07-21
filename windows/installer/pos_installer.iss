; ============================================================================
; Instalador de Pv Control (POS) para Windows -- script de Inno Setup 6.
;
; Este script NO compila la app: solo empaqueta lo que ya exista en
; build\windows\x64\runner\Release. Antes de compilar el instalador hay que
; generar ese build con:
;
;     flutter build windows --release
;
; Uso recomendado (hace ambos pasos en uno): ejecutar
; windows\installer\build_installer.ps1 desde PowerShell. Ver el README.md
; de esta misma carpeta para el procedimiento completo de release.
;
; Requiere Inno Setup 6.3 o superior (https://jrsoftware.org/isdl.php).
; ============================================================================

; La version se recibe desde build_installer.ps1 via "ISCC /DMyAppVersion=X",
; tomada directamente de pubspec.yaml para que no se pueda desincronizar del
; numero de version real de la app. Si se compila este .iss a mano sin pasar
; la version, cae en el valor por defecto de abajo.
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "Pv Control"
#define MyAppPublisher "2A2G Company"
#define MyAppExeName "pvapp.exe"
#define MyReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
; AppId fijo: NO CAMBIAR NUNCA entre versiones. Es lo que permite a Inno
; Setup reconocer una instalacion existente en la maquina del cliente y
; actualizarla en el mismo lugar, en vez de instalar una copia paralela.
AppId={{9F3B2E7A-2C1D-4E6F-8A9B-5D7C1F4E6A2B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; Instalaciones/actualizaciones posteriores reutilizan la carpeta y el grupo
; elegidos la primera vez, sin volver a preguntar.
UsePreviousAppDir=yes
UsePreviousGroup=yes
OutputDir=..\..\dist
OutputBaseFilename=PvControl-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Program Files requiere permisos de administrador.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Si la app esta abierta al instalar/actualizar, pide cerrarla en vez de
; fallar a mitad de copia (evita dejar el POS a medio actualizar).
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName},*.dll
RestartApplications=no

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Copia TODO el contenido generado por "flutter build windows --release"
; (pvapp.exe, flutter_windows.dll, sqlite3.dll, pdfium.dll,
; printing_plugin.dll y la carpeta data\ con los assets de Flutter),
; preservando la estructura de subcarpetas tal cual la genera Flutter.
Source: "{#MyReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; ----------------------------------------------------------------------------
; NOTA IMPORTANTE SOBRE LOS DATOS DEL CLIENTE
;
; La base de datos (pos.db) y sus respaldos NO viven dentro de {app}. La app
; los guarda en:
;
;     %APPDATA%\{#MyAppPublisher}\{#MyAppName}\pos.db
;     %APPDATA%\{#MyAppPublisher}\{#MyAppName}\backups\
;
; (ruta que arma automaticamente el paquete path_provider a partir de
; CompanyName/ProductName definidos en windows\runner\Runner.rc). Como esa
; carpeta esta fuera de {app}, ni este instalador ni el desinstalador que
; Inno genera automaticamente la tocan: por eso reinstalar o actualizar
; conserva los datos del cliente sin ningun paso extra.
;
; Esto significa tambien que CompanyName y ProductName en Runner.rc (y
; MyAppPublisher/MyAppName aqui arriba) son, en la practica, parte del
; contrato de datos del cliente: si algun dia se cambian, la app deja de
; encontrar la base de datos existente en esa maquina. No los cambies salvo
; que sepas exactamente lo que haces (ver README.md de esta carpeta).
; ----------------------------------------------------------------------------
