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

## El camino corto: un solo comando

Si no querés diagnosticar nada:

```powershell
cd C:\ruta\a\Jarvis-IA
git pull
.\arreglar_jarvis.ps1
```

Hace solo todo lo que si no habría que hacer a mano: te dice en qué proveedor
estás, actualiza Hermes si es anterior a v0.20.5, prueba los proveedores gratis
en orden con una llamada real y se queda con el primero que responda, deja los
que sobraron como cadena de respaldo, y **si ninguno anda restaura la
configuración original** en vez de dejarte el bot mudo.

En Linux es `./arreglar_jarvis.sh`. Con `JARVIS_NO_UPDATE=1` no toca la versión
de Hermes.

Lo único que queda para vos es reiniciar el gateway al final: el script corre en
tu sesión, no en la tarea programada que atiende Telegram.

El resto de este documento es el porqué, y qué hacer si el camino corto falla.

---

### ¿Qué proveedor está activo?

El `config.yaml` de Hermes vive en la PC (`%LOCALAPPDATA%\hermes`), no en el
repo, así que lo que diga `setup_jarvis.ps1` puede no ser lo que está corriendo.
Para saberlo:

```powershell
hermes config get model.provider
hermes config get model.default
```

`setup_jarvis.ps1` provisiona `deepseek`; si alguien lo cambió a mano a
`openai-api`, el gasto es de OpenAI. Da igual para el arreglo: los scripts de
acá **pisan** el proveedor activo, sea cual sea.

Ojo con OpenAI en particular: **no tiene capa gratuita de API**. Lo que dan son
créditos de prueba que caducan (US$5–15 según la promo, a los 30–90 días), más
un programa opcional de tokens diarios a cambio de compartir tu tráfico para
entrenamiento. O sea que "está en free" ahí es una cuenta regresiva, no un
plan: por mucho que recortes el consumo, se acaba igual. Por eso el default de
este repo pasó a `opencode-free`, que sí es gratis de forma sostenida.

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
| `JARVIS_PROVIDER` | `opencode-free` (default), `openrouter`, `nvidia`, `deepseek`, `openai-api`, `anthropic` |
| `JARVIS_MODEL` | Forzar un id de modelo distinto al default del provider |
| `JARVIS_FALLBACK_PAID` | `1` deja a DeepSeek (de pago) como último respaldo |
| `OPENROUTER_API_KEY` | Necesaria para el provider/respaldo `openrouter` |
| `NVIDIA_API_KEY` | Necesaria para el provider/respaldo `nvidia` |
| `OPENAI_API_KEY` | Necesaria para el provider `openai-api` |
| `ANTHROPIC_API_KEY` | Necesaria para el provider `anthropic` |

Por defecto **el respaldo de pago está apagado**: si los gratis fallan, Jarvis
falla, en vez de gastar sin avisar. Si preferís que responda igual:

```powershell
$env:JARVIS_FALLBACK_PAID="1"; .\setup_free_model.ps1
```

### Volver a como estaba

```powershell
$env:JARVIS_PROVIDER="deepseek"; .\setup_free_model.ps1
```

`deepseek`, `openai-api` y `anthropic` son los de pago. `openai-api` no trae modelo por
defecto —el catálogo de cada cuenta cambia y no se adivina—, así que pide
`JARVIS_MODEL`; `hermes model` lista los tuyos.

El respaldo de pago (`JARVIS_FALLBACK_PAID=1`) sólo engancha DeepSeek, y sólo si
su key está en el `.env`. No mete a OpenAI: sería volver al problema.

---

## Las opciones gratis, con los números reales

| Opción | Costo | Límite real | Sirve para Jarvis |
|---|---|---|---|
| **`opencode-free`** | $0, sin key | Rate limit no publicado; el catálogo rota | ✅ **La primera a probar** |
| **OpenRouter `:free`** | $0 con cuenta | 20 req/min y **50 req/día** (1.000/día si alguna vez cargaste US$10) | ⚠️ Como respaldo. 50 req/día ≈ 3 mensajes largos |
| **NVIDIA NIM** | $0 con key | Créditos gratis al registrarte, sin tarjeta | ✅ Buen respaldo |
| **Groq** | $0 con key | 14.400 req/día, pero **6.000 tokens/min** | ❌ El prompt de Hermes (~12k tokens) no entra en 1 minuto |
| **Gemini free tier** | $0 con key | 1.000 req/día en Flash-Lite | ❌ La doc de Hermes lo desaconseja: "las keys de capa gratuita se agotan tras un puñado de turnos" |
| **OpenAI** | Créditos de prueba | Caducan a los 30–90 días; no hay capa gratuita | ❌ Es una cuenta regresiva, no un plan |
| **Anthropic** | De pago | Sin capa gratuita; Opus 4.8 a $5/$25 por 1M | ❌ El más caro: ~$0,39 por mensaje de 5 llamadas |
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

## Ojo con `/model` de Hermes

Cambiar el modelo desde el chat con `/model` tiene tres trampas.

**1. Es sólo de sesión.** Si el output termina en `session only — add --global to
persist`, el cambio muere con esa sesión. El gateway que atiende Telegram es
otro proceso: no se entera. Para que valga, `--global` o los scripts de acá.

**2. Anthropic no es gratis, y es el más caro de la lista.** Claude Opus 4.8
cuesta **US$5 por millón de tokens de entrada** y US$25 de salida. Con los
prompts que Hermes ya arrastra (~45 KB por llamada, medidos en el commit
`8d62aba`), eso es ~11.600 tokens de entrada **por llamada**:

| Mensaje de Telegram | Costo aproximado |
|---|---|
| 1 llamada | $0,08 |
| 5 llamadas | $0,39 |
| 10 llamadas | $0,78 |
| 20 llamadas (el tope de `max_turns`) | $1,56 |

Cien mensajes al día con 5 llamadas cada uno son **~US$39 por día**. Para
comparar: DeepSeek v4 Flash estaba en centavos al mes. Pasar de OpenAI a
Anthropic no resuelve el problema del saldo — lo multiplica.

**3. El warning significa que no se verificó nada.** "could not verify … against
this endpoint's model listing" quiere decir que el nombre del modelo se aceptó
**sin comprobar**. La API de Anthropic sí implementa `GET /v1/models`, así que si
esa comprobación falló, lo más probable es que `base_url` no esté apuntando a
Anthropic sino a un resto de la configuración anterior:

```powershell
hermes config get model.base_url
```

Si ahí aparece `api.openai.com` o `api.deepseek.com`, ése es el bug: ese valor
pisa el endpoint del provider nuevo. Los scripts de acá lo limpian solos.

Y como no se verificó, ese "Model switched" no prueba que funcione: la primera
llamada real es la prueba.

Si igual querés Claude en Jarvis, los ids válidos son `claude-opus-5` ($5/$25),
`claude-sonnet-5` ($2/$10) y `claude-haiku-4-5` ($1/$5) — Haiku es el único que
se acerca a razonable para un bot de chat, y aun así no es gratis:

```powershell
$env:JARVIS_PROVIDER="anthropic"; $env:JARVIS_MODEL="claude-haiku-4-5"
$env:ANTHROPIC_API_KEY="sk-ant-..."
.\setup_free_model.ps1
```

## "Provider authentication failed"

Casi siempre es una de estas tres, en este orden:

**1. Hermes viejo.** `opencode-free` recién es *keyless de verdad* en **v0.20.5**.
En versiones anteriores Hermes le pide credencial igual, y el error no dice
"actualizá" — dice que falló la autenticación, y te manda a buscar una key que
no existe. `HERMES_INSTALLATION.md` de este repo documenta una v0.20.0, así que
es el sospechoso número uno:

```powershell
hermes version
hermes update
```

Los scripts ahora comprueban esto antes de tocar nada y te frenan con el mensaje
correcto.

**2. El cambio no llegó a aplicarse.** Si `hermes config set model.provider`
rechazó el valor (provider desconocido en tu versión), seguís en el proveedor de
antes con su key muerta. Comprobalo:

```powershell
hermes config get model.provider
hermes config get model.default
```

Si ahí no dice `opencode-free`, el cambio no entró.

**3. Saltó un respaldo con la key vencida.** `fallback_providers` se dispara con
rate limits y 5xx, y si el respaldo tiene credencial muerta, el error que ves es
el del respaldo, no el del principal:

```powershell
hermes fallback list
```

Y en todos los casos, el log crudo del gateway es el que manda — dice qué
proveedor concreto devolvió el 401.

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
- [OpenAI free tier](https://www.aicredits.co/en/ai/openai-free-tier-2026) — créditos de prueba que caducan, sin capa gratuita permanente
