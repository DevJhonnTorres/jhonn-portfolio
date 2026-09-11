# Diagnostica y arregla a Jarvis en un solo comando.
#
# Hace, sin preguntar, todo lo que si no habria que hacer a mano:
#   1. Dice en que proveedor esta Jarvis ahora.
#   2. Actualiza Hermes si es anterior a v0.20.5 (ahi opencode-free todavia
#      pide credencial y da "Provider authentication failed").
#   3. Prueba los proveedores gratis en orden y se queda con el primero que
#      responda de verdad, comprobado con una llamada real.
#   4. Deja los que sobraron como cadena de respaldo.
#   5. Si ninguno anda, restaura la configuracion original y dice que fallo.
#
# Uso (PowerShell):
#   .\arreglar_jarvis.ps1
#
# Variables opcionales:
#   JARVIS_NO_UPDATE=1   no actualizar Hermes aunque este viejo
#   OPENROUTER_API_KEY   habilita openrouter como candidato
#   NVIDIA_API_KEY       habilita nvidia como candidato
#
# Si Windows bloquea la ejecucion:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"
$MinVersion = [version]"0.20.5"

# --- Home y ejecutable de Hermes -----------------------------------------
if ($env:HERMES_HOME) {
    $HermesHome = $env:HERMES_HOME
} elseif (Test-Path (Join-Path $env:LOCALAPPDATA "hermes\config.yaml")) {
    $HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
} elseif (Test-Path (Join-Path $env:USERPROFILE ".hermes\config.yaml")) {
    $HermesHome = Join-Path $env:USERPROFILE ".hermes"
} else {
    $HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
}

$HermesExe = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $HermesExe) {
    $guess = Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.exe"
    if (Test-Path $guess) { $HermesExe = $guess; $env:Path = (Split-Path $guess) + ";" + $env:Path }
}
if (-not $HermesExe) {
    Write-Host "[X] Hermes no esta instalado o no esta en PATH" -ForegroundColor Red
    exit 1
}

$pyExe = Join-Path (Split-Path (Split-Path $HermesExe)) "python.exe"
if (-not (Test-Path $pyExe)) { $pyExe = Join-Path (Split-Path $HermesExe) "python.exe" }
if (-not (Test-Path $pyExe)) {
    Write-Host "[X] No encontre el python de Hermes junto a $HermesExe" -ForegroundColor Red
    exit 1
}

$CfgFile = Join-Path $HermesHome "config.yaml"
$EnvFile = Join-Path $HermesHome ".env"

# --- Helpers ---------------------------------------------------------------
# Toda llamada a un exe nativo con 2>&1 se hace con ErrorActionPreference en
# Continue: con "Stop", PS 5.1 convierte cualquier linea de stderr en excepcion
# terminante (NativeCommandError) y aca justamente queremos leer el error.
function Invoke-Native {
    param([string]$Exe, [string[]]$Args)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & $Exe @Args 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return [pscustomobject]@{ Output = $out.Trim(); ExitCode = $code }
}

function Get-CfgValue {
    param([string]$Key)
    $code = @"
import io, yaml
try:
    with io.open(r'$CfgFile', encoding='utf-8') as f:
        c = yaml.safe_load(f) or {}
except FileNotFoundError:
    c = {}
for part in '$Key'.split('.'):
    c = c.get(part) if isinstance(c, dict) else None
print('' if c is None else c)
"@
    return (Invoke-Native $pyExe @("-c", $code)).Output
}

function Set-CfgModel {
    param([string]$Provider, [string]$Model, [string]$BaseUrl)
    $code = @"
import io, yaml
p = r'$CfgFile'
try:
    with io.open(p, encoding='utf-8') as f:
        c = yaml.safe_load(f) or {}
except FileNotFoundError:
    c = {}
m = c.setdefault('model', {})
m['provider'], m['default'], m['base_url'] = r'$Provider', r'$Model', r'$BaseUrl'
with io.open(p, 'w', encoding='utf-8') as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
"@
    Invoke-Native $pyExe @("-c", $code) | Out-Null
}

function Test-EnvKey {
    param([string]$Key)
    if (-not (Test-Path $EnvFile)) { return $false }
    return [bool](Select-String -Path $EnvFile -Pattern "^$Key=" -Quiet)
}

function Get-HermesVersion {
    $raw = (Invoke-Native $HermesExe @("version")).Output
    $m = [regex]::Match($raw, 'v?(\d+)\.(\d+)\.(\d+)')
    if ($m.Success) {
        return [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    }
    return $null
}

# --- 1. Estado actual ------------------------------------------------------
Write-Host "== Estado actual =="
$OrigProvider = Get-CfgValue "model.provider"
$OrigModel    = Get-CfgValue "model.default"
$OrigBaseUrl  = Get-CfgValue "model.base_url"
Write-Host "   Proveedor: $(if ($OrigProvider) { $OrigProvider } else { '(sin definir)' })"
Write-Host "   Modelo:    $(if ($OrigModel) { $OrigModel } else { '(sin definir)' })"
Write-Host "   base_url:  $(if ($OrigBaseUrl) { $OrigBaseUrl } else { '(vacio)' })"

$Ver = Get-HermesVersion
Write-Host "   Hermes:    $(if ($Ver) { $Ver } else { '(ilegible)' })"
Write-Host ""

# --- 2. Actualizar si hace falta -------------------------------------------
if ($Ver -and $Ver -lt $MinVersion) {
    if ($env:JARVIS_NO_UPDATE -eq "1") {
        Write-Host "[!] Hermes $Ver es anterior a $MinVersion y opencode-free no va a"
        Write-Host "    funcionar, pero JARVIS_NO_UPDATE=1: no lo actualizo."
    } else {
        Write-Host "== Actualizando Hermes ($Ver -> >=$MinVersion) =="
        Write-Host "   opencode-free solo es keyless desde $MinVersion; antes de eso"
        Write-Host "   pide credencial y da 'Provider authentication failed'."
        $upd = Invoke-Native $HermesExe @("update")
        ($upd.Output -split "`n" | Select-Object -Last 5) | ForEach-Object { Write-Host "   $_" }
        $Ver = Get-HermesVersion
        Write-Host "   Ahora: $(if ($Ver) { $Ver } else { '(ilegible)' })"
    }
    Write-Host ""
}

# --- 3. Candidatos ---------------------------------------------------------
$Candidates = @()
if ((-not $Ver) -or ($Ver -ge $MinVersion)) {
    $Candidates += @{ Provider = "opencode-free"; Model = "deepseek-v4-flash-free"; BaseUrl = "" }
}
if (Test-EnvKey "OPENROUTER_API_KEY") {
    $Candidates += @{ Provider = "openrouter"; Model = "nvidia/nemotron-3-super-120b-a12b:free"; BaseUrl = "" }
}
if (Test-EnvKey "NVIDIA_API_KEY") {
    $Candidates += @{ Provider = "nvidia"; Model = "nvidia/nemotron-3-super-120b-a12b"; BaseUrl = "" }
}

if ($Candidates.Count -eq 0) {
    Write-Host "[X] No queda ningun candidato gratis que probar." -ForegroundColor Red
    Write-Host "    Hermes $Ver es anterior a $MinVersion (sin opencode-free) y no hay"
    Write-Host "    OPENROUTER_API_KEY ni NVIDIA_API_KEY en $EnvFile."
    Write-Host "    Actualiza Hermes ('hermes update') o carga una key gratuita."
    exit 1
}

Write-Host "== Probando proveedores gratis =="
$Winner = $null
$LastErr = ""
$Remaining = @()
foreach ($c in $Candidates) {
    if ($Winner) { $Remaining += $c; continue }
    Write-Host ("   {0,-16} " -f $c.Provider) -NoNewline
    Set-CfgModel $c.Provider $c.Model $c.BaseUrl
    $probe = Invoke-Native $HermesExe @("-z", "Responde unicamente con la palabra OK.")
    if ($probe.ExitCode -eq 0 -and $probe.Output) {
        Write-Host "[OK] responde" -ForegroundColor Green
        $Winner = $c
    } else {
        Write-Host "[X] fallo" -ForegroundColor Red
        $LastErr = ($probe.Output -split "`n" | Select-Object -Last 3) -join "`n"
        if ($LastErr) { ($LastErr -split "`n") | ForEach-Object { Write-Host "        $_" } }
    }
}
Write-Host ""

# --- 4. Cierre -------------------------------------------------------------
if (-not $Winner) {
    Write-Host "[X] Ningun proveedor gratis respondio. Restauro la configuracion original." -ForegroundColor Red
    Set-CfgModel $OrigProvider $OrigModel $OrigBaseUrl
    Write-Host "    Proveedor: $OrigProvider / $OrigModel"
    Write-Host ""
    Write-Host "    Ultimo error:"
    if ($LastErr) { ($LastErr -split "`n") | ForEach-Object { Write-Host "      $_" } }
    Write-Host ""
    Write-Host "    El log del gateway dice que proveedor devolvio el 401."
    exit 1
}

# Los candidatos que no se probaron quedan como respaldo, salvo opencode-free:
# no figura entre los providers aceptados como fallback.
$fallbacks = @($Remaining | Where-Object { $_.Provider -ne "opencode-free" } |
               ForEach-Object { @{ provider = $_.Provider; model = $_.Model } })
$fbJson = ($fallbacks | ConvertTo-Json -Compress -Depth 4)
if (-not $fbJson) { $fbJson = "[]" }
if ($fallbacks.Count -eq 1) { $fbJson = "[$fbJson]" }

$code = @"
import io, json, yaml
p = r'$CfgFile'
with io.open(p, encoding='utf-8') as f:
    c = yaml.safe_load(f) or {}
fb = json.loads(r'''$fbJson''')
if fb:
    c['fallback_providers'] = fb
else:
    c.pop('fallback_providers', None)
c.pop('fallback_model', None)
with io.open(p, 'w', encoding='utf-8') as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
print('   Respaldos: ' + (', '.join(e['provider'] for e in fb) if fb else 'ninguno'))
"@
Write-Host (Invoke-Native $pyExe @("-c", $code)).Output

Write-Host "[OK] Jarvis quedo en $($Winner.Provider) / $($Winner.Model)" -ForegroundColor Green
Write-Host ""
Write-Host "Falta un paso que si tenes que dar vos: reiniciar el gateway para que"
Write-Host "Telegram tome el modelo nuevo."
Write-Host "  schtasks /End /TN <tarea-de-jarvis>; schtasks /Run /TN <tarea-de-jarvis>"
