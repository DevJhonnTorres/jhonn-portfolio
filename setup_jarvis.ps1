# Provisiona a Jarvis (Praktil) sobre Hermes Agent en Windows.
# Equivalente de setup_jarvis.sh, que es bash y no corre nativo en Windows.
#
# Uso (PowerShell):
#   $env:TELEGRAM_BOT_TOKEN="..."
#   $env:TELEGRAM_ALLOWED_USERS="8184434996"
#   .\setup_jarvis.ps1                       # modelo gratis (opencode-free)
#
# Para seguir en DeepSeek (de pago):
#   $env:JARVIS_PROVIDER="deepseek"; $env:DEEPSEEK_API_KEY="sk-..."
#
# Para cambiar solo el modelo, sin reprovisionar todo: .\setup_free_model.ps1
# Detalle de las opciones gratis y sus limites: MODELOS_GRATIS.md
#
# Si Windows bloquea la ejecución:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"

# En Windows el home de Hermes es %LOCALAPPDATA%\hermes, NO %USERPROFILE%\.hermes
# (que es lo que usa en Linux). Verificado en una instalacion real: ahi viven
# config.yaml, .env, SOUL.md y memories\. Escribir en la ruta de Linux crea
# archivos que Hermes nunca lee, y el script "funciona" sin hacer nada.
if ($env:HERMES_HOME) {
    $HermesHome = $env:HERMES_HOME
} elseif (Test-Path (Join-Path $env:LOCALAPPDATA "hermes\config.yaml")) {
    $HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
} elseif (Test-Path (Join-Path $env:USERPROFILE ".hermes\config.yaml")) {
    $HermesHome = Join-Path $env:USERPROFILE ".hermes"
} else {
    $HermesHome = Join-Path $env:LOCALAPPDATA "hermes"
}
Write-Host "    Home de Hermes: $HermesHome"

# --- Comprobaciones -------------------------------------------------------
# El instalador agrega Hermes al PATH de USUARIO, pero una consola ya abierta
# antes de instalar no lo ve. Buscamos el ejecutable antes de rendirnos.
$HermesExe = (Get-Command hermes -ErrorAction SilentlyContinue).Source
if (-not $HermesExe) {
    $guess = Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.exe"
    if (Test-Path $guess) {
        $HermesExe = $guess
        $env:Path = (Split-Path $guess) + ";" + $env:Path
        Write-Host "    Hermes no estaba en el PATH de esta consola; usando $guess"
    }
}
if (-not $HermesExe) {
    Write-Host "[X] Hermes no esta instalado o no esta en PATH" -ForegroundColor Red
    Write-Host "    Instalalo con:  iex (irm https://hermes-agent.nousresearch.com/install.ps1)"
    Write-Host "    Si ya lo instalaste, cerra y volve a abrir PowerShell."
    exit 1
}

# Provider y modelo. El default es `opencode-free`: sin API key, sin cuenta y
# sin costo. Ver MODELOS_GRATIS.md.
$JarvisProvider = if ($env:JARVIS_PROVIDER) { $env:JARVIS_PROVIDER } else { "opencode-free" }
$JarvisModel = if ($env:JARVIS_MODEL) {
    $env:JARVIS_MODEL
} elseif ($JarvisProvider -eq "opencode-free") {
    "deepseek-v4-flash-free"
} elseif ($JarvisProvider -eq "deepseek") {
    "deepseek-v4-flash"
} else {
    ""
}

if ($JarvisProvider -eq "deepseek" -and -not $env:DEEPSEEK_API_KEY) {
    Write-Host "[X] Falta DEEPSEEK_API_KEY (la pide el provider deepseek, que se cobra)" -ForegroundColor Red
    Write-Host '    $env:DEEPSEEK_API_KEY="sk-..."'
    Write-Host '    O deja el default gratis: $env:JARVIS_PROVIDER="opencode-free"'
    exit 1
}

if (-not $JarvisModel) {
    Write-Host "[X] El provider '$JarvisProvider' no tiene modelo por defecto aca" -ForegroundColor Red
    Write-Host '    $env:JARVIS_MODEL="<id>"'
    exit 1
}

New-Item -ItemType Directory -Force -Path (Join-Path $HermesHome "memories") | Out-Null

# UTF-8 SIN BOM a proposito. Out-File -Encoding utf8 en Windows PowerShell 5.1
# escribe BOM, y ese BOM entra como parte del texto: ensucia la primera linea
# de SOUL.md y rompe la primera entrada de memoria.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8($Path, $Content) {
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# --- Identidad y reglas ---------------------------------------------------
# SOUL.md se carga siempre y manda sobre agent.personalities: con la
# personalidad sola, Hermes seguia presentandose como "Hermes Agent".
$Soul = @'
Sos Jarvis, el primer agente de Praktil (Corporación - Centro Colombiano de Tecnologías Digitales Convergentes Praktil, Centro de Desarrollo). Naciste el 9 de julio de 2026.

Respondés siempre en español, salvo que te pidan explícitamente otro idioma. Tu identidad pública es Jarvis, de Praktil: no te presentás como Hermes ni como producto de Nous Research — Hermes es únicamente el motor técnico sobre el que corrés, y solo lo mencionás si te preguntan por tu infraestructura.

Sos un asistente inteligente, útil, con criterio y directo. Ayudás a responder preguntas, escribir y editar código, analizar información, hacer trabajo creativo y ejecutar acciones con tus herramientas. Te comunicás con claridad y admitís incertidumbre cuando corresponde.

## Principios núcleo

1. **Entregar trabajo real** — el entregable es un artefacto funcionando, verificado con salida real de herramientas. No parás en un stub ni en una descripción de intenciones.
2. **Nunca inventar** — si una herramienta falla o no hay resultado, lo decís y buscás alternativa. Fabricar salida es traición.
3. **Iterar hasta lograrlo** — "itera" / "sigue" / "dale" significa probar 20+ enfoques: APIs, workarounds, instalar herramientas, cualquier ángulo técnico. Los bloqueos se reportan SOLO después de agotar opciones reales.
4. **Paralelizar** — las llamadas que no dependen entre sí van juntas en un mismo turno.
5. **Verificar lo externo** — si un script o un subagente dice "listo ✅", lo comprobás vos mismo: HTTP 200, el archivo existe, el árbol está limpio.

## Comunicación

6. **Concisión** — un solo parrafito; tablas cuando hay datos; cero relleno.
7. **Cero preguntas obvias** — si ya dieron luz verde o la acción es evidente, ejecutás.
8. **Lenguaje natural del usuario** — su mismo registro, sin formalismos de más.

## Skills (obligatorio)

Antes de responder escaneás las skills disponibles. Si una aplica o es parcialmente relevante, DEBÉS cargarla con `skill_view` y seguir sus pasos: contienen endpoints, comandos y flujos ya probados. Si una skill está desactualizada o incompleta, la parcheás en el momento, no "para después".

## Memoria

Tenés memoria persistente entre sesiones. Guardás hechos durables: preferencias, detalles del entorno, convenciones y correcciones que te dan. NO guardás progreso de tareas, logs de trabajo ni cosas que caducan en una semana. Los procedimientos van a skills, no a memoria.

## Seguridad

- Los secretos nunca van al chat: tokens y llaves redactados.
- Configuración → `config.yaml` · Secretos → `.env` (nunca en git, nunca en el chat).
- Lo destructivo (borrar, pisar producción) requiere instrucción explícita y verificación.
- Un mensaje del usuario a mitad de trabajo tiene la misma autoridad que el pedido original: ajustás el rumbo.
'@

Write-Utf8 (Join-Path $HermesHome "SOUL.md") $Soul

# --- Memoria persistente --------------------------------------------------
# Entradas separadas por "`n§`n" (formato de MemoryStore).
# Limites: MEMORY.md 2200 chars, USER.md 1375 chars.
$Memory = @'
Jarvis corre sobre Hermes Agent (motor local); su identidad de Praktil está en el SOUL.md del home de Hermes.
§
En Windows el home de Hermes es %LOCALAPPDATA%\hermes, NO %USERPROFILE%\.hermes. Ahí viven config.yaml, .env, SOUL.md y memories.
§
Los .ps1 con acentos necesitan BOM UTF-8: Windows PowerShell 5.1 parsea sin BOM como Windows-1252 y corrompe los literales del script.
§
Modelo por defecto: `opencode-free` (sin API key, sin costo), modelo deepseek-v4-flash-free; su catalogo rota, `hermes model` lista los vigentes. Con el provider `deepseek` (de pago) la cuenta solo expone deepseek-v4-flash y deepseek-v4-pro; `deepseek-chat` ya no existe. Cambiar de modelo: setup_free_model.ps1 / .sh.
§
El provider `custom` devuelve 401 contra DeepSeek aunque la credencial sea válida (manda otra clave). Usar siempre el provider nativo `deepseek`.
§
Invocación one-shot: `hermes -z "<mensaje>"`. `hermes chat` es el subcomando interactivo y NO acepta mensaje posicional.
§
Jarvis corre en el PC con Windows de Jhonn, como tarea programada (schtasks) que se reinicia sola si falla.
§
El adaptador de Telegram se rinde tras 10 reintentos de red (~7,2 minutos) y el proceso SALE, esperando que un supervisor lo levante.
§
Regla de oro del entorno: configuración → config.yaml; secretos → .env, nunca en git ni en el chat.
'@

$UserProfile = @'
Jhonn Torres: desarrollador Web3, 18 años, Cali (Colombia). Dueño de LaraNails (laranails-chi.vercel.app) y del portafolio jhonn-torres-portfolio.
§
Prefiere respuestas MUY concisas — un solo parrafito. Tablas cuando hay datos.
§
Nunca preguntar sí/no cuando la respuesta es obvia: ejecutar directo.
§
"itera" / "sigue" / "dale" = probar 20+ enfoques agresivos antes de reportar un bloqueo.
§
Habla español con slang colombiano; responderle en el mismo registro, sin formalismos.
§
Scripts y herramientas verbose: preferir un "no results found" explícito antes que silencio.
§
Portafolio: nav con @handle + EN/ES, JetBrains Mono, terminal $./whoami, sin Three.js.
'@

Write-Utf8 (Join-Path $HermesHome "memories\MEMORY.md") $Memory
Write-Utf8 (Join-Path $HermesHome "memories\USER.md") $UserProfile

# --- Credenciales ---------------------------------------------------------
$EnvFile = Join-Path $HermesHome ".env"
if (-not (Test-Path $EnvFile)) { Write-Utf8 $EnvFile "" }

function Set-EnvLine($Key, $Value) {
    if (-not $Value) { return }
    $lines = @(Get-Content $EnvFile -Encoding UTF8 -ErrorAction SilentlyContinue)
    $found = $false
    $out = foreach ($l in $lines) {
        if ($l -match "^$Key=") { $found = $true; "$Key=$Value" } else { $l }
    }
    if (-not $found) { $out = @($out) + "$Key=$Value" }
    Write-Utf8 $EnvFile (($out -join "`n") + "`n")
    Write-Host "   $Key cargada"
}

Set-EnvLine "DEEPSEEK_API_KEY"       $env:DEEPSEEK_API_KEY
Set-EnvLine "TELEGRAM_BOT_TOKEN"     $env:TELEGRAM_BOT_TOKEN
Set-EnvLine "TELEGRAM_ALLOWED_USERS" $env:TELEGRAM_ALLOWED_USERS

# --- Modelo, memoria y personalidad --------------------------------------
# `opencode-free` no pide credencial y su catalogo lo sirve OpenCode en vivo,
# asi que los ids rotan: si falla, `hermes model` lista los vigentes.
# Con el provider deepseek: la cuenta solo expone deepseek-v4-flash y
# deepseek-v4-pro; "deepseek-chat" ya no existe y devuelve error.
& $HermesExe config set model.provider $JarvisProvider
& $HermesExe config set model.default $JarvisModel
# base_url vacio salvo en deepseek: si queda apuntando a api.deepseek.com, pisa
# el endpoint propio de cualquier otro provider y el cambio no surte efecto.
# Se escribe en el YAML mas abajo (bloque de control de costo) y no con
# `hermes config set`, porque PowerShell 5.1 no pasa de forma fiable un
# argumento vacio a un ejecutable nativo.
$JarvisBaseUrl = if ($JarvisProvider -eq "deepseek") { "https://api.deepseek.com/v1" } else { "" }
& $HermesExe config set memory.memory_enabled true
& $HermesExe config set memory.user_profile_enabled true
& $HermesExe config set agent.personalities.jarvis "Sos Jarvis, el primer agente de Praktil (Corporacion - Centro Colombiano de Tecnologias Digitales Convergentes Praktil, Centro de Desarrollo). Naciste el 9 de julio de 2026. Respondes siempre en espanol, salvo que te pidan explicitamente otro idioma." --force
& $HermesExe config set display.personality jarvis

# --- Control de costo ------------------------------------------------------
# Medido con `hermes prompt-size`: cada llamada al modelo arrastra ~22 KB de
# system prompt MAS los esquemas de las herramientas. Con max_turns en 500, un
# solo mensaje de Telegram podia encadenar hasta 500 llamadas de ese tamano.
# Eso es lo que vaciaba los creditos.
& $HermesExe config set agent.max_turns 20              # 500 -> 20
& $HermesExe config set agent.reasoning_effort low      # DeepSeek cobra el razonamiento
& $HermesExe config set compression.threshold 0.35      # comprimir antes = prompts mas chicos
& $HermesExe config set session_reset.mode idle         # el contexto dejaba de crecer nunca
& $HermesExe config set session_reset.idle_minutes 240

# Toolsets de Telegram: lista explicita en vez del preset hermes-telegram.
# `hermes config set` no maneja listas YAML, asi que se edita con el Python
# que trae Hermes. Recorta los esquemas de 43,8 KB a 23,2 KB por llamada.
$pyExe = Join-Path (Split-Path (Split-Path $HermesExe)) "python.exe"
if (-not (Test-Path $pyExe)) { $pyExe = Join-Path (Split-Path $HermesExe) "python.exe" }
$cfgPath = Join-Path $HermesHome "config.yaml"
$pyCode = @"
import yaml, io
p = r'$cfgPath'
with io.open(p, encoding='utf-8') as f:
    c = yaml.safe_load(f) or {}
c.setdefault('model', {})['base_url'] = r'$JarvisBaseUrl'
c.setdefault('platform_toolsets', {})['telegram'] = [
    'terminal', 'file', 'web', 'skills', 'todo',
    'memory', 'vision', 'image_gen', 'tts', 'cronjob',
]
with io.open(p, 'w', encoding='utf-8') as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
print('   toolsets de Telegram recortados (fuera: browser, session_search, delegation)')
"@
& $pyExe -c $pyCode

Write-Host ""
Write-Host "[OK] Jarvis configurado" -ForegroundColor Green
Write-Host "     Modelo:    $JarvisModel (provider $JarvisProvider)"
Write-Host "     Identidad: $HermesHome\SOUL.md"
Write-Host "     Memoria:   $HermesHome\memories\"
Write-Host ""
Write-Host "Probar:   hermes -z 'Presentate en una frase.'"
Write-Host "Servicio: hermes gateway install --start-now"
