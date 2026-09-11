#!/usr/bin/env bash
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
# Uso:
#   ./arreglar_jarvis.sh
#
# Variables opcionales:
#   JARVIS_NO_UPDATE=1   no actualizar Hermes aunque este viejo
#   OPENROUTER_API_KEY   habilita openrouter como candidato
#   NVIDIA_API_KEY       habilita nvidia como candidato

set -uo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"
CFG_FILE="$HERMES_HOME/config.yaml"
MIN_VERSION="0.20.5"

if ! command -v hermes >/dev/null 2>&1; then
    echo "❌ Hermes no está instalado o no está en PATH"
    exit 1
fi

PY=""
for cand in "$(dirname "$(readlink -f "$(command -v hermes)")")/python3" \
            "$HERMES_HOME/hermes-agent/venv/bin/python3" \
            /usr/local/lib/hermes-agent/venv/bin/python3 \
            python3; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import yaml" >/dev/null 2>&1; then
        PY="$cand"; break
    fi
done
[ -n "$PY" ] || { echo "❌ No encontré un Python con PyYAML"; exit 1; }

env_file_has() { grep -q "^$1=" "$ENV_FILE" 2>/dev/null; }

cfg_get() {   # cfg_get <ruta.con.puntos>
    CFG="$CFG_FILE" K="$1" "$PY" -c '
import io, os, yaml
try:
    with io.open(os.environ["CFG"], encoding="utf-8") as f:
        c = yaml.safe_load(f) or {}
except FileNotFoundError:
    c = {}
for part in os.environ["K"].split("."):
    c = c.get(part) if isinstance(c, dict) else None
print("" if c is None else c)'
}

cfg_set_model() {   # cfg_set_model <provider> <model> <base_url>
    CFG="$CFG_FILE" P="$1" M="$2" B="$3" "$PY" -c '
import io, os, yaml
p = os.environ["CFG"]
try:
    with io.open(p, encoding="utf-8") as f:
        c = yaml.safe_load(f) or {}
except FileNotFoundError:
    c = {}
m = c.setdefault("model", {})
m["provider"], m["default"], m["base_url"] = os.environ["P"], os.environ["M"], os.environ["B"]
with io.open(p, "w", encoding="utf-8") as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)'
}

# ---------------------------------------------------------------- 1. estado
echo "══ Estado actual ══"
ORIG_PROVIDER="$(cfg_get model.provider)"
ORIG_MODEL="$(cfg_get model.default)"
ORIG_BASEURL="$(cfg_get model.base_url)"
echo "   Proveedor: ${ORIG_PROVIDER:-(sin definir)}"
echo "   Modelo:    ${ORIG_MODEL:-(sin definir)}"
echo "   base_url:  ${ORIG_BASEURL:-(vacío)}"

VER_RAW="$(hermes version 2>/dev/null | head -5)"
VER="$(HV="$VER_RAW" "$PY" -c '
import os, re
m = re.search(r"v?(\d+)\.(\d+)\.(\d+)", os.environ.get("HV", ""))
print(".".join(m.groups()) if m else "")')"
echo "   Hermes:    ${VER:-(ilegible)}"
echo

# ------------------------------------------------------------ 2. actualizar
version_lt() {   # version_lt A B  ->  0 si A < B
    A="$1" B="$2" "$PY" -c '
import os, sys
t = lambda s: tuple(int(x) for x in s.split("."))
sys.exit(0 if t(os.environ["A"]) < t(os.environ["B"]) else 1)'
}

if [ -n "$VER" ] && version_lt "$VER" "$MIN_VERSION"; then
    if [ "${JARVIS_NO_UPDATE:-0}" = "1" ]; then
        echo "⚠️  Hermes $VER es anterior a $MIN_VERSION y opencode-free no va a"
        echo "    funcionar, pero JARVIS_NO_UPDATE=1: no lo actualizo."
    else
        echo "══ Actualizando Hermes ($VER → ≥$MIN_VERSION) ══"
        echo "   opencode-free sólo es keyless desde $MIN_VERSION; antes de eso"
        echo "   pide credencial y da 'Provider authentication failed'."
        hermes update 2>&1 | tail -5
        VER_RAW="$(hermes version 2>/dev/null | head -5)"
        VER="$(HV="$VER_RAW" "$PY" -c '
import os, re
m = re.search(r"v?(\d+)\.(\d+)\.(\d+)", os.environ.get("HV", ""))
print(".".join(m.groups()) if m else "")')"
        echo "   Ahora: ${VER:-(ilegible)}"
    fi
    echo
fi

# ------------------------------------------------------------ 3. candidatos
# En orden de preferencia. Se salta el que no cumpla su requisito.
CANDIDATES=()
if [ -z "$VER" ] || ! version_lt "$VER" "$MIN_VERSION"; then
    CANDIDATES+=("opencode-free|deepseek-v4-flash-free|")
fi
env_file_has OPENROUTER_API_KEY && CANDIDATES+=("openrouter|nvidia/nemotron-3-super-120b-a12b:free|")
env_file_has NVIDIA_API_KEY     && CANDIDATES+=("nvidia|nvidia/nemotron-3-super-120b-a12b|")

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
    echo "❌ No queda ningún candidato gratis que probar."
    echo "   Hermes $VER es anterior a $MIN_VERSION (sin opencode-free) y no hay"
    echo "   OPENROUTER_API_KEY ni NVIDIA_API_KEY en $ENV_FILE."
    echo "   Actualizá Hermes ('hermes update') o cargá una key gratuita."
    exit 1
fi

echo "══ Probando proveedores gratis ══"
WINNER="" ; WINNER_MODEL="" ; LAST_ERR=""
REMAINING=()
for entry in "${CANDIDATES[@]}"; do
    IFS='|' read -r prov model baseurl <<< "$entry"
    if [ -n "$WINNER" ]; then
        REMAINING+=("$prov|$model")   # los que sobran van de respaldo
        continue
    fi
    printf '   %-16s ' "$prov"
    cfg_set_model "$prov" "$model" "$baseurl"
    if out=$(hermes -z "Responde unicamente con la palabra OK." 2>&1) && [ -n "$out" ]; then
        echo "✅ responde"
        WINNER="$prov" ; WINNER_MODEL="$model"
    else
        echo "❌ falló"
        LAST_ERR="$(printf '%s' "$out" | tail -3)"
        [ -n "$LAST_ERR" ] && echo "$LAST_ERR" | sed 's/^/        /'
    fi
done
echo

# ---------------------------------------------------------------- 4. cierre
if [ -z "$WINNER" ]; then
    echo "❌ Ningún proveedor gratis respondió. Restauro la configuración original."
    cfg_set_model "$ORIG_PROVIDER" "$ORIG_MODEL" "$ORIG_BASEURL"
    echo "   Proveedor: ${ORIG_PROVIDER:-(sin definir)} / ${ORIG_MODEL:-(sin definir)}"
    echo
    echo "   Último error:"
    [ -n "$LAST_ERR" ] && echo "$LAST_ERR" | sed 's/^/     /'
    echo
    echo "   El log del gateway dice qué proveedor devolvió el 401."
    exit 1
fi

# Los candidatos que no se probaron quedan como cadena de respaldo, salvo
# opencode-free: no figura entre los providers aceptados como fallback.
FB="[]"
for entry in "${REMAINING[@]:-}"; do
    [ -n "$entry" ] || continue
    IFS='|' read -r prov model <<< "$entry"
    [ "$prov" = "opencode-free" ] && continue
    FB=$(FB="$FB" P="$prov" M="$model" "$PY" -c '
import json, os
fb = json.loads(os.environ["FB"])
fb.append({"provider": os.environ["P"], "model": os.environ["M"]})
print(json.dumps(fb))')
done

FB="$FB" CFG="$CFG_FILE" "$PY" - <<'PYEOF'
import io, json, os, yaml
p = os.environ["CFG"]
with io.open(p, encoding="utf-8") as f:
    c = yaml.safe_load(f) or {}
fb = json.loads(os.environ["FB"])
if fb:
    c["fallback_providers"] = fb
else:
    c.pop("fallback_providers", None)
c.pop("fallback_model", None)
with io.open(p, "w", encoding="utf-8") as f:
    yaml.safe_dump(c, f, allow_unicode=True, sort_keys=False)
print("   Respaldos: " + (", ".join(e["provider"] for e in fb) if fb else "ninguno"))
PYEOF

echo "✅ Jarvis quedó en $WINNER / $WINNER_MODEL"
echo
echo "Falta un paso que sí tenés que dar vos: reiniciar el gateway para que"
echo "Telegram tome el modelo nuevo."
echo "  pkill -f 'hermes gateway run' && hermes gateway run"
