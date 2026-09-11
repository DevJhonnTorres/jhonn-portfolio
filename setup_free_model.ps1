# Pasa a Jarvis a un modelo gratis, sin volver a provisionar todo.
#
# Cambia SOLO el bloque de modelo: provider, modelo, base_url y la cadena de
# respaldo. La identidad (SOUL.md), la memoria, la allowlist de Telegram y el
# control de costo no se tocan, asi que sirve para ir y volver entre modelos sin
# reprovisionar nada.
#
# Uso (PowerShell):
#   .\setup_free_model.ps1                      # opencode-free, sin API key
#   $env:JARVIS_PROVIDER="openrouter"; .\setup_free_model.ps1
#   $env:JARVIS_PROVIDER="deepseek";   .\setup_free_model.ps1   # volver a pago
#
# Variables opcionales:
#   JARVIS_PROVIDER      opencode-free (default) | openrouter | nvidia |
#                        deepseek | openai-api  (los dos ultimos, de pago)
#   JARVIS_MODEL         id del modelo; si no, usa el default del provider
#   JARVIS_FALLBACK_PAID 1 para dejar a DeepSeek (de pago) como ultimo respaldo
#   OPENROUTER_API_KEY   requerido por el provider openrouter
#   NVIDIA_API_KEY       requerido por el provider nvidia
#   OPENAI_API_KEY       requerido por el provider openai-api
#
# Si Windows bloquea la ejecucion:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"

# --- Home y ejecutable de Hermes -----------------------------------------
# En Windows el home de Hermes es %LOCALAPPDATA%\hermes, NO %USERPROFILE%\.hermes.
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
    if (Test-Path $guess) {
        $HermesExe = $guess
        $env:Path = (Split-Path $guess) + ";" + $env:Path
    }
}
if (-not $HermesExe) {
    Write-Host "[X] Hermes no esta instalado o no esta en PATH" -ForegroundColor Red
    Write-Host "    iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
    exit 1
}

# --- Catalogo de providers gratis ----------------------------------------
# opencode-free no pide API key: Hermes manda las peticiones de forma anonima.
# Su catalogo lo sirve OpenCode en vivo, asi que los ids ROTAN (aparecen y
# desaparecen promociones). Si el id de abajo ya no existe, corre `hermes model`
# y elegi otro de la lista, o pasalo en JARVIS_MODEL.
$Catalog = @{
    "opencode-free" = @{ Model = "deepseek-v4-flash-free";                 KeyVar = $null }
    "openrouter"    = @{ Model = "nvidia/nemotron-3-super-120b-a12b:free"; KeyVar = "OPENROUTER_API_KEY" }
    "nvidia"        = @{ Model = "nvidia/nemotron-3-super-120b-a12b";      KeyVar = "NVIDIA_API_KEY" }
    "deepseek"      = @{ Model = "deepseek-v4-flash";                      KeyVar = "DEEPSEEK_API_KEY" }
    # OpenAI no tiene capa gratuita real: son creditos de prueba que caducan.
    # Esta aca solo para poder volver, y sin modelo por defecto a proposito:
    # el catalogo de la cuenta cambia y no se adivina.
    "openai-api"    = @{ Model = "";                                       KeyVar = "OPENAI_API_KEY" }
}

$Provider = if ($env:JARVIS_PROVIDER) { $env:JARVIS_PROVIDER } else { "opencode-free" }
if (-not $Catalog.ContainsKey($Provider)) {
    Write-Host "[X] Provider desconocido: $Provider" -ForegroundColor Red
    Write-Host "    Validos: $($Catalog.Keys -join ', ')"
    exit 1
}
$Entry = $Catalog[$Provider]
$Model = if ($env:JARVIS_MODEL) { $env:JARVIS_MODEL } else { $Entry.Model }

if (-not $Model) {
    Write-Host "[X] El provider '$Provider' no tiene modelo por defecto aca" -ForegroundColor Red
    Write-Host "    Corre 'hermes model' para ver los de tu cuenta, y despues:"
    Write-Host "    `$env:JARVIS_MODEL=`"<id>`"; .\setup_free_model.ps1"
    exit 1
}

# --- Credencial, si el provider la pide ----------------------------------
$EnvFile = Join-Path $HermesHome ".env"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-EnvFileValue($Key) {
    if (-not (Test-Path $EnvFile)) { return $null }
    foreach ($l in (Get-Content $EnvFile -Encoding UTF8)) {
        if ($l -match "^$Key=(.*)$") { return $Matches[1] }
    }
    return $null
}

function Set-EnvLine($Key, $Value) {
    if (-not $Value) { return }
    if (-not (Test-Path $EnvFile)) { [System.IO.File]::WriteAllText($EnvFile, "", $Utf8NoBom) }
    $lines = @(Get-Content $EnvFile -Encoding UTF8 -ErrorAction SilentlyContinue)
    $found = $false
    $out = foreach ($l in $lines) {
        if ($l -match "^$Key=") { $found = $true; "$Key=$Value" } else { $l }
    }
    if (-not $found) { $out = @($out) + "$Key=$Value" }
    [System.IO.File]::WriteAllText($EnvFile, (($out -join "`n") + "`n"), $Utf8NoBom)
    Write-Host "   $Key cargada en .env"
}

if ($Entry.KeyVar) {
    $fromEnv = (Get-Item "Env:$($Entry.KeyVar)" -ErrorAction SilentlyContinue).Value
    if ($fromEnv) {
        Set-EnvLine $Entry.KeyVar $fromEnv
    } elseif (-not (Get-EnvFileValue $Entry.KeyVar)) {
        Write-Host "[X] El provider '$Provider' necesita $($Entry.KeyVar)" -ForegroundColor Red
        Write-Host "    `$env:$($Entry.KeyVar)=`"...`"  y volve a correr el script"
        exit 1
    }
}

# --- Modelo principal ------------------------------------------------------
Write-Host "-> Provider: $Provider"
Write-Host "-> Modelo:   $Model"
& $HermesExe config set model.provider $Provider
& $HermesExe config set model.default $Model
# base_url NO se toca con `hermes config set`: PowerShell 5.1 no pasa de forma
# fiable un argumento vacio a un ejecutable nativo. Se escribe abajo en el YAML,
# junto con la cadena de respaldo.
$BaseUrl = if ($Provider -eq "deepseek") { "https://api.deepseek.com/v1" } else { "" }

# --- Cadena de respaldo ----------------------------------------------------
# Hermes prueba `fallback_providers` en orden cuando el principal falla
# (rate limit, 5xx, auth). OJO: opencode-free NO figura entre los providers
# aceptados como fallback, asi que solo sirve como principal.
$fallbacks = @()
if ($Provider -ne "openrouter" -and (Get-EnvFileValue "OPENROUTER_API_KEY")) {
    $fallbacks += @{ provider = "openrouter"; model = $Catalog["openrouter"].Model }
}
if ($Provider -ne "nvidia" -and (Get-EnvFileValue "NVIDIA_API_KEY")) {
    $fallbacks += @{ provider = "nvidia"; model = $Catalog["nvidia"].Model }
}
# DeepSeek se cobra: solo entra si lo pedis explicitamente.
if ($env:JARVIS_FALLBACK_PAID -eq "1" -and $Provider -ne "deepseek" -and (Get-EnvFileValue "DEEPSEEK_API_KEY")) {
    $fallbacks += @{ provider = "deepseek"; model = $Catalog["deepseek"].Model }
    Write-Host "   Respaldo de pago activado: DeepSeek entra si los gratis fallan"
}

# `hermes config set` no escribe listas YAML; se edita con el Python de Hermes.
$pyExe = Join-Path (Split-Path (Split-Path $HermesExe)) "python.exe"
if (-not (Test-Path $pyExe)) { $pyExe = Join-Path (Split-Path $HermesExe) "python.exe" }
$cfgPath = Join-Path $HermesHome "config.yaml"
$fbJson = ($fallbacks | ConvertTo-Json -Compress -Depth 4)
if (-not $fbJson) { $fbJson = "[]" }
if ($fallbacks.Count -eq 1) { $fbJson = "[$fbJson]" }   # ConvertTo-Json no envuelve el elemento unico

$pyCode = @"
import yaml, io, json
p = r'$cfgPath'
with io.open(p, encoding='utf-8') as f:
    c = yaml.safe_load(f) or {}
# base_url heredado de DeepSeek pisa el endpoint propio de cualquier otro
# provider: si no se limpia, el cambio de modelo no surte efecto.
c.setdefault('model', {})['base_url'] = r'$BaseUrl'
fb = json.loads(r'''$fbJson''')
if fb:
    c['fallback_providers'] = fb
else:
    c.pop('fallback_providers', None)
c.pop('fallback_model', None)   # formato viejo: si queda, compite con el nuevo
with io.open(p, 'w', encoding='utf-8') as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
print('   base_url: ' + (r'$BaseUrl' or '(vacio)'))
print('   respaldos: ' + (', '.join(e['provider'] for e in fb) if fb else 'ninguno'))
"@
& $pyExe -c $pyCode

# --- Verificacion ----------------------------------------------------------
# Un cambio de modelo que no se prueba es un bot mudo que te enteras por
# Telegram. Se comprueba con una llamada real antes de dar el OK.
Write-Host ""
Write-Host "-> Probando el modelo con una llamada real..."
# ErrorActionPreference "Stop" convierte cualquier linea de stderr de un
# ejecutable nativo en excepcion terminante (NativeCommandError, PS 5.1). Como
# aca queremos LEER el error y explicarlo, se baja durante la prueba.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$probe = & $HermesExe -z "Responde unicamente con la palabra OK." 2>&1
$probeExit = $LASTEXITCODE
$ErrorActionPreference = $prevEap
$probeText = ($probe | Out-String).Trim()
if ($probeExit -eq 0 -and $probeText) {
    Write-Host "[OK] El modelo responde: $probeText" -ForegroundColor Green
} else {
    Write-Host "[X] El modelo NO respondio" -ForegroundColor Red
    Write-Host $probeText
    Write-Host ""
    Write-Host "Lo mas probable: el id '$Model' ya no esta en el catalogo (los"
    Write-Host "gratis rotan). Corre 'hermes model', elegi uno de la lista y"
    Write-Host "volve a correr esto con `$env:JARVIS_MODEL=`"<id>`"."
    exit 1
}

Write-Host ""
Write-Host "Reinicia el gateway para que Telegram tome el modelo nuevo:"
Write-Host "  schtasks /End /TN <tarea-de-jarvis>; schtasks /Run /TN <tarea-de-jarvis>"
Write-Host "  (o cerra el 'hermes gateway run' y volvelo a levantar)"
