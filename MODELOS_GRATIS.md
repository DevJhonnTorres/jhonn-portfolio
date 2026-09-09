# Jarvis con modelos gratis

Cómo dejar de quemar créditos de pago en el Jarvis de Telegram.

---

## Antes que nada: el post de Instagram no aplica acá

El repo del post (`musistudio/claude-code-router`) **no es un skill** y **no toca
a Jarvis**. Es un gateway local para *agentes de código* — Claude Code, Codex,
OpenCode y compañía: se instala con `npm`, escucha en `127.0.0.1:3456` y ahí es
donde apuntás tu CLI. Sirve para que **Claude Code** te salga gratis, no para el
bot de Telegram. Eso está al final, en [Aparte: Claude Code
gratis](#aparte-claude-code-gratis-eso-sí-es-claude-code-router).

Jarvis es otra cosa: corre sobre **Hermes Agent** (`hermes gateway run`) en la
PC con Windows, y Hermes ya trae adentro lo que el router hace por fuera —
elegir proveedor, cambiar de modelo y encadenar respaldos. No hace falta
instalar nada nuevo: hay que **reconfigurarlo**.

Y un detalle: los créditos que se están yendo no son de ChatGPT. `setup_jarvis.ps1`
dejaba a Jarvis en el provider `deepseek` con el modelo `deepseek-v4-flash`. Lo
que se vacía es el saldo de **DeepSeek**.

---

## Por qué se muere tan rápido

Ya se midió con `hermes prompt-size` (ver commit `8d62aba`): cada llamada al
modelo arrastra ~22 KB de system prompt más ~23 KB de esquemas de herramientas.
Y **un solo mensaje de Telegram no es una llamada**: Hermes itera con sus
herramientas hasta `agent.max_turns`, hoy en 20.

O sea: un mensaje tuyo puede costar hasta 20 llamadas de ~45 KB. Eso es lo que
vacía cualquier saldo — y también lo que hace que varias capas gratuitas
"generosas" no sirvan (más abajo).

---

## La solución: `opencode-free` como modelo principal

Hermes trae un provider llamado **`opencode-free`**: sin API key, sin cuenta,
peticiones anónimas. Su catálogo se sirve en vivo desde OpenCode e incluye
—hoy— `deepseek-v4-flash-free`: **el mismo modelo que Jarvis ya usa, gratis**.

Ahora es el **default** de `setup_jarvis.ps1` / `setup_jarvis.sh`: reprovisionar
a Jarvis ya no te devuelve al modelo de pago, y `DEEPSEEK_API_KEY` pasó a ser
opcional. Y `setup_free_model.ps1` / `.sh` cambian sólo el modelo, sin
reprovisionar nada, más una cadena de respaldo para cuando el gratis se caiga o
te limite.

### En Windows (donde vive Jarvis)

```powershell
cd C:\ruta\a\Jarvis-IA
.\setup_free_model.ps1
```

### En Linux / contenedor

```bash
./setup_free_model.sh
```

El script cambia **sólo el bloque de modelo** — provider, modelo, `base_url` y
`fallback_providers`. No toca `SOUL.md`, ni la memoria, ni la allowlist de
Telegram, ni el control de costo. Al final hace una llamada real (`hermes -z`)
y te dice si el modelo respondió: un cambio de modelo sin probar es un bot mudo
del que te enterás por Telegram.

Después reiniciá el gateway para que Telegram tome el modelo nuevo.

### Variables

| Variable | Para qué |
|---|---|
| `JARVIS_PROVIDER` | `opencode-free` (default), `openrouter`, `nvidia`, `deepseek` |
| `JARVIS_MODEL` | Forzar un id de modelo distinto al default del provider |
| `JARVIS_FALLBACK_PAID` | `1` deja a DeepSeek (de pago) como último respaldo |
| `OPENROUTER_API_KEY` | Necesaria para el provider/respaldo `openrouter` |
| `NVIDIA_API_KEY` | Necesaria para el provider/respaldo `nvidia` |

Por defecto **el respaldo de pago está apagado**: si los gratis fallan, Jarvis
falla, en vez de gastar sin avisar. Si preferís que responda igual:

```powershell
$env:JARVIS_FALLBACK_PAID="1"; .\setup_free_model.ps1
```

### Volver a como estaba

```powershell
$env:JARVIS_PROVIDER="deepseek"; .\setup_free_model.ps1
```

---

## Las opciones gratis, con los números reales

| Opción | Costo | Límite real | Sirve para Jarvis |
|---|---|---|---|
| **`opencode-free`** | $0, sin key | Rate limit no publicado; el catálogo rota | ✅ **La primera a probar** |
| **OpenRouter `:free`** | $0 con cuenta | 20 req/min y **50 req/día** (1.000/día si alguna vez cargaste US$10) | ⚠️ Como respaldo. 50 req/día ≈ 3 mensajes largos |
| **NVIDIA NIM** | $0 con key | Créditos gratis al registrarte, sin tarjeta | ✅ Buen respaldo |
| **Groq** | $0 con key | 14.400 req/día, pero **6.000 tokens/min** | ❌ El prompt de Hermes (~12k tokens) no entra en 1 minuto |
| **Gemini free tier** | $0 con key | 1.000 req/día en Flash-Lite | ❌ La doc de Hermes lo desaconseja: "las keys de capa gratuita se agotan tras un puñado de turnos" |
| **Ollama / LM Studio local** | $0, ilimitado | Tu GPU/RAM | ✅ Si la PC aguanta un modelo con tool-calling |

Dos cosas que conviene tener claras:

1. **Un mensaje ≠ una petición.** Con `max_turns` en 20, un límite de "50 por
   día" pueden ser 3 mensajes. Por eso OpenRouter va de respaldo y no de
   principal.
2. **Los catálogos gratis rotan.** Los ids `:free` y los de OpenCode aparecen y
   desaparecen. Si el script falla en la verificación, corré `hermes model`,
   elegí uno de la lista y volvé a correrlo con `JARVIS_MODEL=<id>`.

Modelos `:free` de OpenRouter con tool-calling verificados contra su API el
2026-09-09 (17 de 18): `nvidia/nemotron-3-super-120b-a12b:free`,
`nvidia/nemotron-3.5-lightning:free` (1M de contexto),
`google/gemma-4-31b-it:free`, `poolside/laguna-s-2.1:free`,
`thinkingmachines/inkling:free`. El único sin herramientas es
`nvidia/nemotron-3.5-content-safety:free` — ése no sirve, Jarvis vive de sus
herramientas.

---

## Si aun así se te va el saldo

Bajar el consumo pesa más que cambiar de proveedor. Lo grande ya está aplicado
en `setup_jarvis.ps1`, pero se puede apretar más:

```powershell
hermes config set agent.max_turns 10          # hoy 20; es el multiplicador
hermes config set compression.threshold 0.25  # hoy 0.35; comprime antes
hermes config set session_reset.idle_minutes 60   # hoy 240
```

Y medir antes de tocar, no adivinar:

```powershell
hermes prompt-size
```

---

## Aparte: Claude Code gratis (eso sí es claude-code-router)

Esto no tiene nada que ver con Jarvis; es para tu terminal.

```sh
npm install -g @musistudio/claude-code-router   # necesita Node 22+
ccr ui
```

Abrís `http://127.0.0.1:3458` y seguís el flujo **Providers → Server → Agent
Config**:

1. **Providers → Add Provider**: elegís un preset (OpenRouter, DeepSeek, Gemini,
   Kimi…) o un endpoint propio, ponés la API key y los modelos.
2. **Server → Start**: el gateway queda escuchando en `http://127.0.0.1:3456`.
3. **Agent Config**: elegís *Claude Code*, le asignás modelo y aplicás el perfil.
4. **Routing**: acá es donde se hace lo del post — las tareas pesadas a un modelo
   fuerte, las livianas a uno gratis, con reintentos y fallbacks ordenados.

También hay app de escritorio para Windows en los releases del repo, si preferís
no usar npm.

---

## Fuentes

- [Providers de Hermes Agent](https://hermes-agent.nousresearch.com/docs/integrations/providers/) — ids de provider, variables de entorno, `opencode-free`
- [Fallback Providers](https://hermes-agent.nousresearch.com/docs/user-guide/features/fallback-providers) — formato de `fallback_providers`
- [Configuring Models](https://hermes-agent.nousresearch.com/docs/user-guide/configuring-models) — `model.provider`, `model.default`, `model.base_url`
- [OpenRouter — rate limits](https://openrouter.ai/docs/api-reference/limits) — 20 req/min, 50 o 1.000 req/día
- [claude-code-router](https://github.com/musistudio/claude-code-router) — instalación y flujo de la UI
- [Groq free tier](https://tokenmix.ai/blog/groq-free-tier-limits-2026) — 30 RPM, 6.000 TPM, 14.400 req/día
