# ============================================================================
# Registra el respaldo diario de Pv Control como tarea programada de Windows.
#
# Uso (en la PC del negocio, DESPUES de instalar Pv Control):
#   Clic derecho > "Ejecutar con PowerShell"
#   o bien:
#   powershell -ExecutionPolicy Bypass -File instalar-respaldo-automatico.ps1
#
# Pregunta a donde respaldar y a que hora. No requiere ser administrador:
# la tarea se registra en la sesion del usuario actual.
# ============================================================================

param(
    # Carpeta destino (USB, disco externo, carpeta de Drive/OneDrive).
    # Si se omite, se pregunta.
    [string]$Destino,

    # Hora diaria del respaldo, formato 24h. Conviene despues del cierre.
    [string]$Hora = "23:00",

    # Copias a conservar en el destino.
    [int]$Conservar = 30
)

$ErrorActionPreference = "Stop"
$nombreTarea = "Pv Control - Respaldo diario"

Write-Host ""
Write-Host "=== Respaldo automatico de Pv Control ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Verificar que la app ya haya corrido ---------------------------------
$carpetaDatos = Join-Path $env:APPDATA "2A2G Company\Pv Control"
$baseDatos    = Join-Path $carpetaDatos "pos.db"

if (-not (Test-Path $baseDatos)) {
    Write-Host "No se encontro la base de datos en:" -ForegroundColor Red
    Write-Host "  $baseDatos"
    Write-Host ""
    Write-Host "Instala Pv Control y abrelo al menos una vez (para crear la" -ForegroundColor Yellow
    Write-Host "cuenta de administrador). Luego vuelve a correr este script." -ForegroundColor Yellow
    Read-Host "`nPresiona Enter para salir"
    exit 1
}
Write-Host "Base de datos encontrada:" -ForegroundColor Green
Write-Host "  $baseDatos"

# --- 2. Destino --------------------------------------------------------------
if (-not $Destino) {
    Write-Host ""
    Write-Host "Unidades disponibles ahora mismo:" -ForegroundColor Cyan
    # SilentlyContinue: una unidad de red desconectada haria fallar el listado
    # entero, y esto es solo una ayuda visual.
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.Free } |
        ForEach-Object {
            $libreGB = [math]::Round($_.Free / 1GB, 1)
            Write-Host ("  {0}:\   {1} GB libres" -f $_.Name, $libreGB)
        }
    Write-Host ""
    Write-Host "IMPORTANTE: elige una unidad DISTINTA a la del sistema (C:)." -ForegroundColor Yellow
    Write-Host "Un respaldo en el mismo disco no protege del caso que mas" -ForegroundColor Yellow
    Write-Host "negocios se lleva por delante: que ese disco se muera." -ForegroundColor Yellow
    Write-Host ""
    $Destino = Read-Host "Carpeta destino del respaldo (ej. E:\ o D:\Respaldos)"
}

$Destino = $Destino.Trim().Trim('"')
if (-not $Destino) { Write-Host "No se indico destino. Cancelado." -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Destino)) {
    Write-Host "La ruta '$Destino' no existe o no esta conectada." -ForegroundColor Red
    Read-Host "`nPresiona Enter para salir"
    exit 1
}

if ([System.IO.Path]::GetPathRoot($Destino).TrimEnd('\') -ieq $env:SystemDrive) {
    Write-Host ""
    Write-Host "AVISO: elegiste una carpeta en $env:SystemDrive (el mismo disco del sistema)." -ForegroundColor Yellow
    $r = Read-Host "Si ese disco falla, pierdes base y respaldo. Continuar de todos modos? (s/N)"
    if ($r -notmatch '^[sS]') { Write-Host "Cancelado." ; exit 1 }
}

# --- 3. Copiar el script a una ruta local estable ----------------------------
# Se instala en LOCALAPPDATA a proposito: si la tarea apuntara al script
# dentro de la USB, dejaria de funcionar en cuanto se desconecte la USB.
$carpetaLocal = Join-Path $env:LOCALAPPDATA "PvControl"
if (-not (Test-Path $carpetaLocal)) {
    New-Item -ItemType Directory -Path $carpetaLocal -Force | Out-Null
}

$origenScript = Join-Path $PSScriptRoot "respaldo.ps1"
if (-not (Test-Path $origenScript)) {
    Write-Host "No se encontro respaldo.ps1 junto a este archivo." -ForegroundColor Red
    Write-Host "Copia la carpeta completa de la USB, no solo este script." -ForegroundColor Yellow
    Read-Host "`nPresiona Enter para salir"
    exit 1
}

$scriptLocal = Join-Path $carpetaLocal "respaldo.ps1"
Copy-Item -Path $origenScript -Destination $scriptLocal -Force
Write-Host ""
Write-Host "Script instalado en: $scriptLocal" -ForegroundColor Green

# --- 4. Registrar la tarea ---------------------------------------------------
$argumentos = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ' +
              "-File `"$scriptLocal`" -Destino `"$Destino`" -Conservar $Conservar"

$accion = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentos

$disparador = New-ScheduledTaskTrigger -Daily -At $Hora

# StartWhenAvailable: si la PC estaba apagada a esa hora (cierre del negocio),
# el respaldo corre en cuanto se prenda, en vez de saltarse el dia.
$opciones = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask `
    -TaskName $nombreTarea `
    -Action $accion `
    -Trigger $disparador `
    -Settings $opciones `
    -Description "Copia diaria de la base de datos de Pv Control a $Destino" `
    -Force | Out-Null

Write-Host "Tarea programada creada: `"$nombreTarea`"" -ForegroundColor Green
Write-Host "  Hora diaria : $Hora"
Write-Host "  Destino     : $Destino\PvControl-Respaldos\"
Write-Host "  Conservar   : $Conservar copias"

# --- 5. Prueba inmediata -----------------------------------------------------
Write-Host ""
Write-Host "Ejecutando un respaldo de prueba ahora..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptLocal -Destino $Destino -Conservar $Conservar
$codigo = $LASTEXITCODE

Write-Host ""
if ($codigo -eq 0) {
    Write-Host "LISTO. El respaldo de prueba se hizo correctamente." -ForegroundColor Green
    Write-Host "Revisa la carpeta: $Destino\PvControl-Respaldos\" -ForegroundColor Green
} else {
    Write-Host "La tarea quedo registrada, pero el respaldo de prueba fallo (codigo $codigo)." -ForegroundColor Yellow
    Write-Host "Revisa el mensaje de arriba." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Para quitar el respaldo automatico algun dia:" -ForegroundColor DarkGray
Write-Host "  Unregister-ScheduledTask -TaskName `"$nombreTarea`" -Confirm:`$false" -ForegroundColor DarkGray
Write-Host ""
Read-Host "Presiona Enter para salir"
