# Coral — análisis competitivo

**Última actualización: 2026-08-05.** Documento **vivo**: sustituye a cualquier versión anterior
(no es un diario — solo el estado actual). Renómbralo con la fecha del último update al revisarlo.
Fuentes con URL; lo no confirmado va marcado.

---

## Dónde estamos

**Una frase:** el único orquestador multi-agente **nativo de Mac** que corre sobre **tus propias
suscripciones** (Claude Code / Codex / Gemini — sin medición, sin cuenta), **open source (MIT)**, con un
**verificador de otra familia de proveedor**, **procedencia por línea** y **auto-mejora del equipo (RAI)**.

| Eje | Nota | Lectura |
|---|---|---|
| **Producto / posicionamiento en el nicho** | **8.5 / 10** | La combinación {nativo + BYO-suscripción + sin medición + sin cuenta + MIT + verificador cross-family + provenance + Mapa + mezcla por rol + RAI} sigue sin tenerla nadie — pero la categoría "app Mac nativa multi-agente BYO" se ha **poblado** (ver abajo): ya no somos casi únicos en el *contenedor*, solo en el *motor cross-provider + verificador + RAI*. |
| **Fuerza de negocio hoy** | **5.5 / 10** | Solo-founder, pre-escala, sin financiación ni distribución. Foso técnico real; el de adopción, empezando. |

**El cuello de botella no es tecnología, es adopción/distribución** (web, onboarding, viralidad) —
y ahora, con 5+ apps nativas Mac nuevas en el nicho, **la ventana para plantar bandera se estrecha**.

---

## Mapa del mercado (nota = fuerza competitiva holística hoy, 1–10)

| # | Competidor | Qué es | Nota | Amenaza |
|---|---|---|---|---|
| 1 | **Claude Code** (Anthropic) | CLI agéntica 1ª parte; subagents/Agent Teams/grader; mono-proveedor | **9.5** | 🔴 Alta — es nuestro sustrato y el "¿por qué no el oficial?" |
| 2 | **Cursor** (Anysphere) | IDE Electron; parallel agents + best-of-N; ~$29B | **9.0** | 🟠 Media — ubicuo, pero mete su propia medición |
| 3 | **Cognition** (Devin + Windsurf/Devin Desktop) | Ingeniero autónomo + **Devin Review**; ~$26B (reportado) | **8.5** | 🔴 Alta — Devin Review contesta nuestro titular "verificador" |
| 4 | **Google Antigravity + `agy`** | Plataforma agéntica + Agent Manager; gratis, multi-modelo | **8.0** | 🟠 Media — escala Google; cerró la Gemini CLI OSS (18-jun-2026) |
| 5 | **Factory.ai** (Droids) | SDLC agéntico enterprise; ~$1.5B | **8.0** | 🟠 Media — enterprise, **API-key-only**, medido |
| 6 | **Replit** (Agent 4) | IDE cloud + parallel agents + hosting; ~$9B, ~35M users | **8.0** | 🟢 Baja — otro público (no-devs/greenfield) |
| 7 | **Lovable** | Vibe-coding web; ~$6.6B, ~$400M ARR | **7.5** | 🟢 Baja — no-devs, silo cloud medido |
| 8 | **Zed** | Editor **nativo Rust, OSS**; parallel agents + ACP | **7.5** | 🟠 Media — peer filosófico más cercano (nativo+abierto+multi-provider) |
| 9 | **Warp** | Terminal nativo (cliente AGPL); "Oz" orquesta las 3 CLIs | **7.5** | 🔴 Alta — solapamiento arquitectónico más directo |
| 10 | **Amp** (Sourcegraph) | Agente + "Oracle" reviewer; sin markup; 40k equipos | **7.0** | 🟠 Media — reviewer real, pero cerrado/medido/cloud |
| 11 | **Aider** | Pair-programmer **CLI OSS**, BYO-keys | **7.0** | 🟠 Media — análogo OSS; single-agent, sin GUI |
| 12 | **Conductor** (Melty, YC S24) | App **Mac nativa** parallel Claude/Codex/Cursor; ~$22M | **6.5** | 🔴 **Gemelo directo** — misma categoría exacta |
| 13 | **Agentastic.dev** 🆕 | App **Mac nativa**; Claude/Codex/Gemini/Cursor/Copilot + **36+** integraciones; worktrees + diff/review; **BYO-suscripción**, usa CLIs nativas + **skills/hooks/MCP**, auto-descubre agentes | **6.5** | 🔴 **La más parecida en posicionamiento** — nativo + BYO + skills, casi nuestro pitch textual |
| 14 | **diri** 🆕 (cristicretu) | Orquestador **Mac nativo OSS** (Rust+GPUI); Claude/Codex/Cursor/Gemini + shells en paralelo por worktree **y hosts remotos**; menú-bar; **MCP server** (agentes lanzan agentes) | **6.0** | 🔴 Directa — nativo + abierto; añade remoto/MCP que no tenemos |
| 15 | **Unpeel** 🆕 | App **Mac nativa** (motor Ghostty); multi-CLI; worktrees; **control remoto desde iPhone** (relay E2E); cerrado, free + remoto de pago | **5.5** | 🟠 Media — pulida; su cuña es el remoto móvil |
| 16 | **Bolt** (StackBlitz) | Prompt→app en navegador; ~$700M | **6.5** | 🟢 Baja — nicho web, dependiente de Claude |
| 17 | **kodo / constellagent / clave** 🆕 | Varios: kodo = multi-agente autónomo nocturno sobre Claude Max + verificación independiente; constellagent/clave = apps Mac multi-terminal/worktree | **5.0** | 🟢 Vigilar — kodo roza nuestro "verificador"; el resto son runners paralelos |

---

## Los que quitan el sueño (🔴) y nuestra cuña

- **Agentastic.dev** 🆕 — *el nuevo pitch-gemelo*: nativo Mac, BYO-suscripción, usa las CLIs nativas
  **con sus skills/hooks/MCP**, worktrees + review, 36+ integraciones. **Ganamos:** orquestación
  **cross-provider en UNA tirada con roles mixtos** (no solo runners paralelos aislados) · **verificador
  de otra familia** que gatea · **procedencia por línea** · **auto-mejora RAI** · MIT. *Riesgo:* su amplitud
  de integraciones y "usa tus skills" nos igualan la narrativa de superficie — hay que **liderar por el motor**.
- **Conductor / diri** — nativas Mac, local, BYO, parallel-worktree; **diri** suma **hosts remotos + MCP
  server**. **Ganamos:** mezcla cross-provider por rol + verificador cross-family + RAI + provenance + Mapa;
  ellos = sesiones paralelas + merge. *Hueco a cubrir:* remoto/MCP-para-lanzar-agentes (diri) y sandbox.
- **Warp** — orquesta Claude+Codex+Gemini (motor "Oz") pero **mete créditos medidos** y **rechazó el login
  por suscripción** (GitHub #9609). **Ganamos:** tus suscripciones **sin medición**, MIT, verificador cross-provider.
- **Cognition / Devin Review** — único **reviewer independiente maduro** (+Autofix), pero **mismo proveedor**;
  el nuestro es **otra familia**, BYO/sin-ACUs/nativo/abierto.

---

## Vigilancia de features de competidores (lo último a seguir)

- **Categoría "app Mac nativa multi-agente" ahora saturada** (nuevos: Agentastic, diri, Unpeel, constellagent, clave, kodo). El *contenedor* dejó de ser diferenciador — el diferenciador es el **motor** (cross-provider por rol + verificador + RAI + provenance).
- **Agentastic.dev:** BYO-suscripción explícito + "usa tus CLIs, skills, hooks y MCP" + auto-descubre agentes → nos copia la narrativa de superficie; 36+ integraciones.
- **diri (OSS):** hosts **remotos** + **MCP server** para que un agente lance/orqueste a otros → dos features que no tenemos.
- **Unpeel:** **control remoto desde iPhone** (relay self-host E2E) → nadie más lo tiene; posible "wow" futuro.
- **kodo:** autónomo **nocturno** sobre Claude Max + **verificación independiente** → roza nuestro titular.
- **Cognition:** Windsurf → "Devin Desktop"; Agent Command Center + Spaces; Devin Review en todos los planes.
- **Warp:** universal agents + "Oz" cloud; cliente OSS AGPL.
- **Google:** mató la Gemini CLI OSS por `agy` cerrada (18-jun-2026) — oportunidad "abierto" para nosotros; ya soportamos `agy` como fallback.
- **Claude Code:** subagents/Agent Teams/grader 1ª parte + app de escritorio con sesiones paralelas → **riesgo de absorción**.
- **Mercado:** más medición en todos (Anthropic + Copilot usage-based, mediados 2026) → nuestra postura sin-markup se revaloriza.

---

## Lo que Coral tiene ya (diferenciadores enviados)

- **Multi-agente cross-provider en una tirada** (orquestador Claude + workers Codex/Gemini) con **streaming en vivo** (Claude vía stream-json; Codex/Gemini bajo PTY) y **fallo rápido + reconexión de login** de un toque.
- **Eficiencia y honestidad de coste (nuevo, ago-2026):** *pre-flight de login* — si un proveedor no tiene sesión válida, sus workers **no se lanzan** (antes: 4–5 instancias de Gemini colgadas hasta el watchdog de 10 min gastando la tirada); **watchdog de silencio a 2 min** para un CLI atascado; el turno **falla en segundos** con "reconecta X", no en minutos. *(Este es un diferenciador de confianza frente a los runners paralelos que simplemente cuelgan.)*
- **Verificación de conexión real (nuevo):** "conectado" = **login válido** (token en disco), no solo "CLI instalado" — con punto ámbar de reconexión y **diagnóstico instantáneo** (sin colgarse).
- **Verificador independiente** (reviewer≠author, otra familia) que gatea loops y revisa diffs de worktree aislado.
- **Procedencia por línea** (qué modelo escribió cada línea, cross-provider).
- **Catálogo de modelos auto-actualizable (nuevo):** `models.json` remoto (repo público, cacheado) se fusiona al arrancar → **añadir/deprecar modelos sin release**. Incluye GPT-5.5 · GPT-5.6 Terra/Luna · Gemini 3 Pro/Flash · 2.5 · Opus 5 · Fable 5 · Sonnet 5, y campo de modelo libre por rol.
- **Skills desde cualquier fuente (nuevo):** el catálogo Discover ya no es solo de Anthropic — `skills.json` remoto + descubrimiento comunitario por estrellas; formato SKILL.md **portable** (base para uso cross-provider; aplicación a workers no-Claude, pendiente).
- **Mapa de código** (grafo visual + inyectado a agentes + ahorro estimado) — ahora **agrupable/filtrable como los chats** (fecha/tipo) y con **paleta coral fluor** (estética orb). Incontestado como concepto.
- **Arranque con splash (nuevo):** orbe 3D coral que **precalienta cachés** (detección de proveedores, uso local, lista de repos) y **verifica logins** antes de dejar la app interactiva → primera navegación instantánea.
- **Arena** (modelos/equipos cara a cara con juez + recomendación).
- **Auto-mejora del equipo (RAI)** — deriva probes del uso real, corre la suite juzgada independientemente, edita una palanca por ronda hasta converger; humano aprueba. *(Nadie auto-mejora el diseño del equipo con tu historial + juez cross-provider.)*
- **Ship fino** (Vercel/Netlify/Cloudflare) sin ser PaaS. **BYO, sin cuenta, MIT.**
- **"Trabajo repetido" visible** + rutas descartadas/fallos como evidencia. *(Hanako 2026.)*
- **Puerta por blast-radius** — contenido→auto · amplio→gate · irreversible→nunca; bloquea auto-merge del Loop para irreversibles. *(Eval Engineering 2026.)*
- **Vista de trayectoria "A vs B"** con pasos "REPETIDO"/"pagado dos veces". *(Hanako 2026.)*
- **Panel de jueces multi-familia** + registro del juez usado.
- **Memory como "verdad operativa"** — auto-cosechado entra *pendiente de revisión*; solo lo pinned se inyecta. *(Replit 2026.)*
- **Lente de coste nodo/arista** — separa pensamiento (nodos) de enrutado evitable (aristas). *(Graph Engineering.)*
- **Countdowns de reset** (5h + semana) + **filtrar/agrupar/ordenar chats**. *(CodexBar.)*
- **Uso sin fricción de llavero (nuevo):** abrir "Uso" **nunca** toca el Keychain (muestra el % cacheado); el prompt solo aparece bajo ↻ deliberado.
- **Visor de diff SOTA en Código (nuevo, ago-2026):** paridad de UX de revisión con Cursor/Zed/GitHub — resaltado de sintaxis + **word-level intraline**, **vista unificada ↔ side-by-side** conmutable, **navegación por hunks** (▲/▼ + contador), **stage / descarte POR HUNK** (parche de un solo hunk vía `git apply --cached`/`--reverse`, probado), **"Visto" por archivo** con barra de progreso, hallazgos del **verificador independiente fijados al diff** (marca en gutter por severidad + clic→scroll), **filtro por severidad** (chips high/medium/low para triar bloqueantes vs nits), y **checkpoints / rewind** (snapshot no destructivo con `git stash create`, vuelta atrás confirmada) como red de seguridad al aceptar trabajo de agentes. Además la **vista de agentes ya no expulsa al diff**: es un compañero flotante colapsable sobre el diff (ves al equipo trabajar Y su diff a la vez). *(Cierra el hueco "el visor de diff se sentía plano" frente a Devin Review/Amp Oracle: la revisión cross-familia se lee y se acciona dentro del código, no en una lista aparte.)*
- **Pasada de diseño "limpio" (nuevo, ago-2026):** revisión con 6 agentes especializados vs. las tendencias limpias (Claude/ChatGPT/Codex/**Agentastic**/Cursor) → aplicado: **un solo acento** (coral solo en lo vivo/primario), **un banner de estado a la vez**, rail plano (Chats·Code·Team + More), composer con menú "+" (Grill/Approaches/Isolate ocultos), cabecera y empty-state más calmados, copy de seguridad en lenguaje llano ("qué tan difícil de deshacer"). Norte de diseño fijado como ley del producto. *(Respuesta directa a "Coral se ha complicado" y al listón de UI de Agentastic.)*

---

## Qué nos falta (prioridad)

| Prio | Hueco | Por qué |
|---|---|---|
| **P0** | **Adopción:** publicar la **web** (`web/` lista) + **tap Homebrew**; **vídeo demo 60s**; medir "time-to-first-run" | El foso técnico no se traduce en usuarios; y ahora hay 5+ apps nativas nuevas compitiendo por el mismo hueco — **plantar bandera ya**. |
| **P0 🆕** | **Liderar por el MOTOR, no el contenedor:** que el onboarding/web muestre en 10s lo que un runner paralelo (Agentastic/Conductor/diri) NO hace: **un equipo cross-provider con verificador de otra familia + RAI + provenance**. | La categoría "app Mac multi-agente" se saturó; nuestra defensa es el motor, no "corro varias CLIs". |
| **P1** | **Skills cross-provider (aplicación):** inyectar el cuerpo de la skill en los prompts de workers no-Claude (GPT/Gemini no leen `.claude/skills/`) | Ya tenemos fuentes extensibles; falta que la skill **aplique** a cualquier modelo (Agentastic ya presume de "usa tus skills"). |
| **P1** | **Transparencia app-wide** (ninguna op larga parece congelada) | ✅ barrido hecho + ahora fail-fast de login (no más "10 min sin señal"). |
| **P2 🆕** | **Remoto / MCP-server** (diri lo tiene: hosts remotos + agentes que lanzan agentes) y **control móvil** (Unpeel) | Nuevos vectores que los recién llegados usan como cuña. |
| **P2** | **Paridad:** memoria dos niveles (User+Org); **sandboxing por-agente** (Conductor/gemelos NO lo tienen → oportunidad) | Cierra brechas y abre una que ellos no cubren. |
| **P2** | **Blast-radius en el `loop.sh` generado** (el auto-merge in-app ya lo tiene) | El script ships a otros repos; necesita versión bash diseñada por humano. |

---

## Viento a favor (datos externos)

- **Stack Overflow 2025:** uso IA **84%** pero solo **33% confía**; 66% pierde tiempo arreglando código "casi correcto". → verificador + provenance + RAI + **fail-fast honesto** es la "correa" que piden.
- **Anthropic 2026:** "la verificación es el nuevo cuello de botella"; reviewer de **distinta familia** aún no es estándar → foso defendible.
- **Tamaño de mercado (2026, direccional):** AI code tools ~**$9.4–10.1B**, CAGR ~23–28%.

> **Fuentes clave:** conductor.build · agentastic.dev · github.com/cristicretu/diri · (Unpeel) · amux.io/blog/best-multi-agent-orchestrators-2026 · rywalker.com/research/mac-coding-agent-apps · github.com/warpdotdev/warp/issues/9609 · devin.ai/blog/devin-review-windsurf · factory.ai/pricing · zed.dev/pricing · thenewstack.io/gemini-cli-antigravity-replacement · techcrunch.com (Cognition; Cursor) · survey.stackoverflow.co/2025/ai · resources.anthropic.com/2026-agentic-coding-trends-report · ampcode.com/manual · aider.chat/docs · sacra.com (Lovable/Replit/Bolt) · mordorintelligence.com / fortunebusinessinsights.com (tamaño mercado).
