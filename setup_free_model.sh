#!/usr/bin/env bash
# Pasa a Jarvis a un modelo gratis, sin volver a provisionar todo.
# Equivalente de setup_free_model.ps1 para Linux/macOS/contenedores.
#
# Cambia SÓLO el bloque de modelo: provider, modelo, base_url y la cadena de
# respaldo. La identidad (SOUL.md), la memoria y la allowlist de Telegram no se
# tocan, así que sirve para ir y volver entre modelos sin reprovisionar nada.
#
# Uso:
#   ./setup_free_model.sh                        # opencode-free, sin API key
#   JARVIS_PROVIDER=openrouter ./setup_free_model.sh
#   JARVIS_PROVIDER=deepseek   ./setup_free_model.sh   # volver a pago
#
# Variables opcionales:
#   JARVIS_PROVIDER      opencode-free (default) | openrouter | nvidia | deepseek
#   JARVIS_MODEL         id del modelo; si no, usa el default del provider
#   JARVIS_FALLBACK_PAID 1 para dejar a DeepSeek (de pago) como último respaldo
#   OPENROUTER_API_KEY   requerido por el provider openrouter
#   NVIDIA_API_KEY       requerido por el provider nvidia

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"
CFG_FILE="$HERMES_HOME/config.yaml"

if ! command -v hermes >/dev/null 2>&1; then
    echo "❌ Hermes no está instalado o no está en PATH"
    echo "   curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    exit 1
fi

# Python con PyYAML: el del sistema puede no tenerlo, el del venv de Hermes
# siempre lo trae (Hermes lee y escribe config.yaml con él).
PY=""
for cand in "$(dirname "$(readlink -f "$(command -v hermes)")")/python3" \
            "$HERMES_HOME/hermes-agent/venv/bin/python3" \
            /usr/local/lib/hermes-agent/venv/bin/python3 \
            python3; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import yaml" >/dev/null 2>&1; then
        PY="$cand"
        break
    fi
done
if [ -z "$PY" ]; then
    echo "❌ No encontré un Python con PyYAML para editar config.yaml"
    echo "   Instalalo con: python3 -m pip install pyyaml"
    exit 1
fi

# --- Catálogo de providers gratis ------------------------------------------
# opencode-free no pide API key: Hermes manda las peticiones de forma anónima.
# Su catálogo lo sirve OpenCode en vivo, así que los ids ROTAN. Si el de abajo
# ya no existe, corré `hermes model` y elegí otro, o pasalo en JARVIS_MODEL.
PROVIDER="${JARVIS_PROVIDER:-opencode-free}"

case "$PROVIDER" in
    opencode-free) DEFAULT_MODEL="deepseek-v4-flash-free";                 KEY_VAR="" ;;
    openrouter)    DEFAULT_MODEL="nvidia/nemotron-3-super-120b-a12b:free"; KEY_VAR="OPENROUTER_API_KEY" ;;
    nvidia)        DEFAULT_MODEL="nvidia/nemotron-3-super-120b-a12b";      KEY_VAR="NVIDIA_API_KEY" ;;
    deepseek)      DEFAULT_MODEL="deepseek-v4-flash";                      KEY_VAR="DEEPSEEK_API_KEY" ;;
    *)
        echo "❌ Provider desconocido: $PROVIDER"
        echo "   Válidos: opencode-free, openrouter, nvidia, deepseek"
        exit 1 ;;
esac

MODEL="${JARVIS_MODEL:-$DEFAULT_MODEL}"

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

env_file_has() { grep -q "^$1=" "$ENV_FILE" 2>/dev/null; }

set_env_line() {
    local key="$1" value="$2"
    [ -n "$value" ] || return 0
    if env_file_has "$key"; then
        sed -i.bak "s|^$key=.*|$key=$value|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
    echo "   $key cargada en .env"
}

# --- Credencial, si el provider la pide ------------------------------------
if [ -n "$KEY_VAR" ]; then
    from_env="${!KEY_VAR:-}"
    if [ -n "$from_env" ]; then
        set_env_line "$KEY_VAR" "$from_env"
    elif ! env_file_has "$KEY_VAR"; then
        echo "❌ El provider '$PROVIDER' necesita $KEY_VAR"
        echo "   export $KEY_VAR=...   y volvé a correr el script"
        exit 1
    fi
fi

# --- Modelo principal ------------------------------------------------------
# base_url se VACÍA a propósito: setup_jarvis.sh lo deja en
# https://api.deepseek.com/v1 y ese valor pisa el endpoint de cualquier otro
# provider. Sin limpiarlo, el cambio no surte efecto.
echo "→ Provider: $PROVIDER"
echo "→ Modelo:   $MODEL"
hermes config set model.provider "$PROVIDER"
hermes config set model.default "$MODEL"
# base_url no se toca con `hermes config set`: pasar un valor vacío por línea de
# comandos no es fiable. Se escribe abajo, junto con la cadena de respaldo.
if [ "$PROVIDER" = "deepseek" ]; then
    BASE_URL="https://api.deepseek.com/v1"
else
    BASE_URL=""
fi

# --- Cadena de respaldo ----------------------------------------------------
# Hermes prueba `fallback_providers` en orden cuando el principal falla
# (rate limit, 5xx, auth). OJO: opencode-free NO figura entre los providers
# aceptados como fallback, así que sólo sirve como principal.
FALLBACKS="[]"
add_fallback() {
    FALLBACKS=$(FB="$FALLBACKS" P="$1" M="$2" "$PY" -c '
import json, os
fb = json.loads(os.environ["FB"])
fb.append({"provider": os.environ["P"], "model": os.environ["M"]})
print(json.dumps(fb))')
}

if [ "$PROVIDER" != "openrouter" ] && env_file_has OPENROUTER_API_KEY; then
    add_fallback openrouter "nvidia/nemotron-3-super-120b-a12b:free"
fi
if [ "$PROVIDER" != "nvidia" ] && env_file_has NVIDIA_API_KEY; then
    add_fallback nvidia "nvidia/nemotron-3-super-120b-a12b"
fi
# DeepSeek se cobra: sólo entra si lo pedís explícitamente.
if [ "${JARVIS_FALLBACK_PAID:-0}" = "1" ] && [ "$PROVIDER" != "deepseek" ] && env_file_has DEEPSEEK_API_KEY; then
    add_fallback deepseek "deepseek-v4-flash"
    echo "   Respaldo de pago activado: DeepSeek entra si los gratis fallan"
fi

# `hermes config set` no escribe listas YAML; se edita el config a mano.
FB="$FALLBACKS" CFG="$CFG_FILE" BASE_URL="$BASE_URL" "$PY" - <<'PYEOF'
import io, json, os, yaml
p = os.environ["CFG"]
try:
    with io.open(p, encoding="utf-8") as f:
        c = yaml.safe_load(f) or {}
except FileNotFoundError:
    c = {}
# base_url heredado de DeepSeek pisa el endpoint propio de cualquier otro
# provider: si no se limpia, el cambio de modelo no surte efecto.
c.setdefault("model", {})["base_url"] = os.environ["BASE_URL"]
fb = json.loads(os.environ["FB"])
if fb:
    c["fallback_providers"] = fb
else:
    c.pop("fallback_providers", None)
c.pop("fallback_model", None)   # formato viejo: si queda, compite con el nuevo
with io.open(p, "w", encoding="utf-8") as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
print("   base_url: " + (os.environ["BASE_URL"] or "(vacio)"))
print("   respaldos: " + (", ".join(e["provider"] for e in fb) if fb else "ninguno"))
PYEOF

# --- Verificación ----------------------------------------------------------
# Un cambio de modelo que no se prueba es un bot mudo del que te enterás por
# Telegram. Se comprueba con una llamada real antes de dar el OK.
echo
echo "→ Probando el modelo con una llamada real..."
if probe=$(hermes -z "Responde únicamente con la palabra OK." 2>&1) && [ -n "$probe" ]; then
    echo "✅ El modelo responde: $probe"
else
    echo "❌ El modelo NO respondió"
    echo "$probe"
    echo
    echo "Lo más probable: el id '$MODEL' ya no está en el catálogo (los gratis"
    echo "rotan). Corré 'hermes model', elegí uno de la lista y volvé a correr"
    echo "esto con JARVIS_MODEL=<id>."
    exit 1
fi

echo
echo "Reiniciá el gateway para que Telegram tome el modelo nuevo:"
echo "  pkill -f 'hermes gateway run' && hermes gateway run"
