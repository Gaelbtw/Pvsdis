# Compila Pv Control (Flutter, Release) y genera el instalador de Windows
# (pos_installer.iss, Inno Setup) en un solo paso.
#
# Requisitos:
#   - Flutter SDK en PATH.
#   - Inno Setup 6.3+ instalado (https://jrsoftware.org/isdl.php).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File windows\installer\build_installer.ps1
#
# La version del instalador se toma automaticamente de pubspec.yaml: no hace
# falta (ni conviene) escribirla a mano en el .iss.

param(
    # Firma el instalador y el desinstalador. Requiere -ComandoFirma o la
    # variable de entorno PVCONTROL_SIGN_CMD.
    [switch]$Firmar,

    # Comando de firma, con $f donde va el archivo. Ejemplo:
    #   'signtool.exe sign /fd SHA256 /tr http://timestamp.acs.microsoft.com /td SHA256 $f'
    [string]$ComandoFirma = $env:PVCONTROL_SIGN_CMD
)

$ErrorActionPreference = "Stop"

$installerDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $installerDir)

Set-Location $repoRoot

# 1. Leer la version desde pubspec.yaml (formato "version: X.Y.Z+build").
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw
if ($pubspec -notmatch "(?m)^version:\s*(\d+\.\d+\.\d+)(\+\d+)?\s*$") {
    throw "No se pudo leer una version valida (X.Y.Z) desde pubspec.yaml"
}
$version = $Matches[1]
Write-Host "Version detectada en pubspec.yaml: $version" -ForegroundColor Cyan

# 2. Compilar la app Flutter en modo Release.
Write-Host "`n== flutter clean ==" -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean fallo (codigo $LASTEXITCODE)" }

Write-Host "`n== flutter pub get ==" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get fallo (codigo $LASTEXITCODE)" }

Write-Host "`n== flutter build windows --release ==" -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows fallo (codigo $LASTEXITCODE)" }

$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$releaseExe = Join-Path $releaseDir "pvapp.exe"
if (-not (Test-Path $releaseExe)) {
    throw "No se genero pvapp.exe en $releaseDir. Revisa la salida de 'flutter build windows' arriba."
}

# 3. Ubicar ISCC.exe (compilador de linea de comandos de Inno Setup).
$isccCmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
if ($isccCmd) {
    $iscc = $isccCmd.Source
} else {
    $candidatos = @(
        "${Env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$Env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$Env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    $iscc = $candidatos | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $iscc) {
    throw "No se encontro ISCC.exe. Instala Inno Setup 6.3+ (https://jrsoftware.org/isdl.php) o agregalo al PATH."
}
Write-Host "`nUsando Inno Setup: $iscc" -ForegroundColor Cyan

# 4. Compilar el instalador, propagando la version leida del pubspec.
$issPath = Join-Path $installerDir "pos_installer.iss"
$argsIscc = @("/DMyAppVersion=$version")

if ($Firmar) {
    if (-not $ComandoFirma) {
        throw "Se pidio -Firmar pero no hay comando de firma. Pasa -ComandoFirma '<cmd> `$f' o define PVCONTROL_SIGN_CMD."
    }
    if ($ComandoFirma -notmatch '\$f') {
        throw "El comando de firma debe incluir `$f (donde Inno pone la ruta del archivo). Recibido: $ComandoFirma"
    }
    $argsIscc += "/DFirmarSetup"
    $argsIscc += "/Sfirmante=$ComandoFirma"
    Write-Host "`nFirma activada." -ForegroundColor Cyan
} else {
    Write-Host "`nSin firmar. Windows mostrara 'Windows protegio tu PC' al instalar;" -ForegroundColor DarkYellow
    Write-Host "el LEEME.txt de la USB explica al cliente como continuar." -ForegroundColor DarkYellow
}

Write-Host "`n== Generando instalador con Inno Setup ==" -ForegroundColor Cyan
& $iscc @argsIscc $issPath
if ($LASTEXITCODE -ne 0) { throw "ISCC fallo al compilar el instalador (codigo $LASTEXITCODE)" }

$distDir = Join-Path $repoRoot "dist"
Write-Host "`nListo. Instalador generado en: $distDir" -ForegroundColor Green
Get-ChildItem $distDir -Filter "PvControl-Setup-*.exe" | Select-Object -Last 1 | ForEach-Object {
    Write-Host " -> $($_.FullName)" -ForegroundColor Green

    # SHA256 del instalador. Se entrega junto al .exe para que el cliente
    # pueda comprobar que lo que bajo (o lo que le quedo en la USB) es
    # exactamente lo que salio de aqui, y no una copia corrupta.
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    Write-Host "`nSHA256 (entregalo junto al instalador):" -ForegroundColor Cyan
    Write-Host "  $hash" -ForegroundColor Cyan
}
