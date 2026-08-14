# ============================================================================
# Arma la carpeta lista para copiar a la memoria USB.
#
# Uso normal (compila todo desde cero):
#   powershell -ExecutionPolicy Bypass -File windows\installer\preparar_usb.ps1
#
# Si ya compilaste y solo quieres rearmar la carpeta:
#   ... \preparar_usb.ps1 -SinCompilar
#
# Resultado:
#   dist\USB\   <- copiar ESTA carpeta completa a la memoria USB
#
# Requiere internet UNA vez (para bajar VC_redist.x64.exe de Microsoft).
# Despues queda cacheado en dist\ y ya no se vuelve a descargar.
# La PC del negocio no necesita internet en ningun momento.
# ============================================================================

param(
    # Reutiliza el instalador que ya exista en dist\ en vez de recompilar.
    [switch]$SinCompilar,

    # No incluir VC_redist.x64.exe (si sabes que la PC destino ya lo tiene).
    [switch]$SinRedist
)

$ErrorActionPreference = "Stop"

$installerDir = $PSScriptRoot
$repoRoot     = Split-Path -Parent (Split-Path -Parent $installerDir)
$distDir      = Join-Path $repoRoot "dist"
$usbDir       = Join-Path $distDir "USB"
$plantillas   = Join-Path $installerDir "usb"

Set-Location $repoRoot

Write-Host ""
Write-Host "=== Preparando carpeta para USB ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Compilar el instalador ----------------------------------------------
if (-not $SinCompilar) {
    Write-Host "[1/5] Compilando app + instalador..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installerDir "build_installer.ps1")
    if ($LASTEXITCODE -ne 0) { throw "build_installer.ps1 fallo (codigo $LASTEXITCODE)" }
} else {
    Write-Host "[1/5] -SinCompilar: se reutiliza lo que haya en dist\" -ForegroundColor Yellow
}

# --- 2. Localizar el instalador generado ------------------------------------
Write-Host ""
Write-Host "[2/5] Buscando el instalador..." -ForegroundColor Cyan

if (-not (Test-Path $distDir)) {
    throw "No existe dist\. Corre el script sin -SinCompilar para generar el instalador."
}

$setup = Get-ChildItem $distDir -Filter "PvControl-Setup-*.exe" -File |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1

if (-not $setup) {
    throw "No se encontro ningun PvControl-Setup-*.exe en $distDir"
}

if ($setup.Name -notmatch 'PvControl-Setup-(.+)\.exe$') {
    throw "No se pudo extraer la version de '$($setup.Name)'"
}
$version = $Matches[1]

Write-Host "  Instalador : $($setup.Name)" -ForegroundColor Green
Write-Host "  Version    : $version" -ForegroundColor Green
Write-Host "  Compilado  : $($setup.LastWriteTime)" -ForegroundColor Green

# --- 3. Carpeta USB limpia ---------------------------------------------------
Write-Host ""
Write-Host "[3/5] Armando dist\USB\ ..." -ForegroundColor Cyan

if (Test-Path $usbDir) { Remove-Item $usbDir -Recurse -Force }
New-Item -ItemType Directory -Path $usbDir -Force | Out-Null

# El prefijo numerico define el orden de instalacion a simple vista.
Copy-Item $setup.FullName -Destination (Join-Path $usbDir "2-$($setup.Name)")
Copy-Item (Join-Path $plantillas "respaldo.ps1") -Destination $usbDir
Copy-Item (Join-Path $plantillas "instalar-respaldo-automatico.ps1") `
          -Destination (Join-Path $usbDir "3-instalar-respaldo-automatico.ps1")

# --- 4. Visual C++ Redistributable ------------------------------------------
if (-not $SinRedist) {
    Write-Host ""
    Write-Host "[4/5] Visual C++ Redistributable..." -ForegroundColor Cyan

    $redistCache = Join-Path $distDir "VC_redist.x64.exe"

    if (Test-Path $redistCache) {
        Write-Host "  Usando copia cacheada en dist\" -ForegroundColor Green
    } else {
        Write-Host "  Descargando de Microsoft (una sola vez)..." -ForegroundColor Cyan
        try {
            $progresoPrevio = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'   # acelera Invoke-WebRequest
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
                              -OutFile $redistCache -UseBasicParsing
            $ProgressPreference = $progresoPrevio
            Write-Host "  Descargado." -ForegroundColor Green
        } catch {
            Write-Host "  AVISO: no se pudo descargar ($($_.Exception.Message))." -ForegroundColor Yellow
            Write-Host "  Bajalo a mano de https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
            Write-Host "  y guardalo como: $redistCache" -ForegroundColor Yellow
            $redistCache = $null
        }
    }

    if ($redistCache -and (Test-Path $redistCache)) {
        Copy-Item $redistCache -Destination (Join-Path $usbDir "1-VC_redist.x64.exe")
    }
} else {
    Write-Host ""
    Write-Host "[4/5] -SinRedist: se omite VC_redist.x64.exe" -ForegroundColor Yellow
}

# --- 5. LEEME con version y checksum reales ---------------------------------
Write-Host ""
Write-Host "[5/5] Generando LEEME.txt..." -ForegroundColor Cyan

$hash = (Get-FileHash $setup.FullName -Algorithm SHA256).Hash

$leeme = Get-Content (Join-Path $plantillas "LEEME.txt") -Raw -Encoding UTF8
$leeme = $leeme.Replace("{VERSION}", $version).Replace("{SHA256}", $hash)
Set-Content -Path (Join-Path $usbDir "LEEME.txt") -Value $leeme -Encoding UTF8

# Checksum suelto, por si se quiere verificar con otra herramienta.
Set-Content -Path (Join-Path $usbDir "SHA256.txt") `
            -Value "$hash  2-$($setup.Name)" -Encoding ASCII

# --- Resumen -----------------------------------------------------------------
$total = (Get-ChildItem $usbDir -File | Measure-Object -Property Length -Sum).Sum
$totalMB = [math]::Round($total / 1MB, 1)

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Green
Write-Host " LISTO. Copia esta carpeta completa a la USB:" -ForegroundColor Green
Write-Host ""
Write-Host "   $usbDir" -ForegroundColor White
Write-Host ""
Write-Host " Contenido ($totalMB MB):" -ForegroundColor Green
Get-ChildItem $usbDir -File | Sort-Object Name | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 2)
    Write-Host ("   {0,-42} {1,8} MB" -f $_.Name, $mb)
}
Write-Host ""
Write-Host " SHA256: $hash" -ForegroundColor DarkGray
Write-Host ""
Write-Host " En la PC del negocio: abrir LEEME.txt y seguir los 4 pasos." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host ""
