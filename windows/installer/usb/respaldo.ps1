# ============================================================================
# Respaldo de la base de datos de Pv Control a una carpeta externa
# (memoria USB, disco externo o carpeta sincronizada tipo Drive/OneDrive).
#
# Uso manual:
#   powershell -ExecutionPolicy Bypass -File respaldo.ps1 -Destino "E:\"
#
# Uso automatico: lo registra "instalar-respaldo-automatico.ps1" como tarea
# programada diaria. No hace falta llamarlo a mano.
#
# Por que copia TRES archivos y no solo pos.db:
#   SQLite trabaja en modo WAL. Mientras la app esta abierta, las ultimas
#   transacciones viven en pos.db-wal y todavia no en pos.db. Copiar solo
#   pos.db dejaria fuera las ventas mas recientes. Los tres juntos son un
#   conjunto restaurable.
#   Si la app estaba cerrada al momento del respaldo, -wal y -shm no existen
#   (ya se consolidaron en pos.db) y eso es normal, no es un error.
# ============================================================================

param(
    # Carpeta donde se guardan los respaldos. Obligatorio.
    [Parameter(Mandatory = $true)]
    [string]$Destino,

    # Cuantas copias se conservan. Las mas viejas se borran solas para que la
    # USB no se llene sin que nadie se de cuenta.
    [int]$Conservar = 30
)

$ErrorActionPreference = "Stop"

# --- Rutas de origen ---------------------------------------------------------
# Debe coincidir con CompanyName/ProductName de windows\runner\Runner.rc.
# Si algun dia se rebrandea el producto, esta ruta cambia y este script
# deja de encontrar la base.
$carpetaDatos = Join-Path $env:APPDATA "2A2G Company\Pv Control"
$baseDatos    = Join-Path $carpetaDatos "pos.db"

$carpetaRespaldos = Join-Path $Destino "PvControl-Respaldos"
$log              = Join-Path $carpetaRespaldos "respaldo.log"

function Escribir-Log {
    param([string]$Mensaje, [string]$Nivel = "INFO")
    $linea = "{0}  [{1}]  {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensaje
    Write-Host $linea
    try {
        if (Test-Path $carpetaRespaldos) {
            Add-Content -Path $log -Value $linea -Encoding UTF8
        }
    } catch {
        # Si no se puede escribir el log (USB desconectada a media escritura),
        # no se convierte eso en el error principal.
    }
}

# --- Validaciones ------------------------------------------------------------
if (-not (Test-Path $baseDatos)) {
    Write-Host "ERROR: no se encontro la base de datos en:" -ForegroundColor Red
    Write-Host "  $baseDatos" -ForegroundColor Red
    Write-Host "Abre Pv Control al menos una vez antes de programar el respaldo." -ForegroundColor Yellow
    exit 1
}

# La USB puede no estar conectada a la hora de la tarea programada. Eso no es
# una falla del sistema: se registra y se sale sin ruido.
$raizDestino = [System.IO.Path]::GetPathRoot($Destino)
if (-not (Test-Path $Destino)) {
    Write-Host "AVISO: el destino '$Destino' no esta disponible (unidad $raizDestino desconectada?)." -ForegroundColor Yellow
    Write-Host "No se hizo respaldo. Conecta la unidad y vuelve a intentar." -ForegroundColor Yellow
    exit 2
}

if (-not (Test-Path $carpetaRespaldos)) {
    New-Item -ItemType Directory -Path $carpetaRespaldos -Force | Out-Null
}

# --- Copia -------------------------------------------------------------------
$marca      = Get-Date -Format "yyyy-MM-dd_HHmm"
$destinoHoy = Join-Path $carpetaRespaldos $marca

if (Test-Path $destinoHoy) {
    # Dos corridas en el mismo minuto: no se pisa la anterior.
    $destinoHoy = "$destinoHoy-$(Get-Random -Maximum 999)"
}
New-Item -ItemType Directory -Path $destinoHoy -Force | Out-Null

$copiados = 0
$bytes    = 0
foreach ($sufijo in @("", "-wal", "-shm")) {
    $origen = "$baseDatos$sufijo"
    if (Test-Path $origen) {
        try {
            Copy-Item -Path $origen -Destination $destinoHoy -Force
            $copiados++
            $bytes += (Get-Item $origen).Length
        } catch {
            Escribir-Log "No se pudo copiar $origen : $($_.Exception.Message)" "ERROR"
        }
    }
}

if ($copiados -eq 0) {
    Escribir-Log "Respaldo FALLIDO: no se copio ningun archivo." "ERROR"
    Remove-Item $destinoHoy -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$mb = [math]::Round($bytes / 1MB, 2)
Escribir-Log "Respaldo OK -> $marca  ($copiados archivo(s), $mb MB)"

# --- Marcador para la app -----------------------------------------------------
# Pv Control no puede saber por si solo si este respaldo corrio: la tarea vive
# en el Programador de tareas de Windows y escribe en una unidad que puede
# estar desconectada. Se deja un archivito junto a pos.db para que la app avise
# en pantalla cuando el respaldo externo lleva dias sin ejecutarse.
#
# Lo que falla en la practica no es este script: es que alguien desconecto la
# USB para pasar fotos y no la volvio a conectar. Un respaldo que falla en
# silencio es peor que no tener respaldo, porque quita la preocupacion sin
# quitar el riesgo.
try {
    $marcador = Join-Path $carpetaDatos "ultimo_respaldo_externo.txt"
    @(
        "fecha=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')",
        "destino=$destinoHoy"
    ) | Set-Content -Path $marcador -Encoding UTF8
} catch {
    Escribir-Log "No se pudo escribir el marcador para la app: $($_.Exception.Message)" "WARN"
}

# --- Retencion ---------------------------------------------------------------
# Se conservan las $Conservar copias mas recientes; el resto se borra.
$todas = Get-ChildItem -Path $carpetaRespaldos -Directory |
         Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{4}' } |
         Sort-Object Name -Descending

if ($todas.Count -gt $Conservar) {
    $sobran = $todas | Select-Object -Skip $Conservar
    foreach ($vieja in $sobran) {
        try {
            Remove-Item $vieja.FullName -Recurse -Force
            Escribir-Log "Purgada copia antigua: $($vieja.Name)"
        } catch {
            Escribir-Log "No se pudo purgar $($vieja.Name): $($_.Exception.Message)" "WARN"
        }
    }
}

Escribir-Log "Total de copias conservadas: $([math]::Min($todas.Count, $Conservar))"
exit 0
