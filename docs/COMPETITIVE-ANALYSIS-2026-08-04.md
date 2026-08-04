# Coral — análisis competitivo

**Última actualización: 2026-08-04.** Documento **vivo**: sustituye a cualquier versión anterior
(no es un diario — solo el estado actual). Renómbralo con la fecha del último update al revisarlo.
Fuentes con URL; lo no confirmado va marcado.

---

## Dónde estamos

**Una frase:** el único orquestador multi-agente **nativo de Mac** que corre sobre **tus propias
suscripciones** (Claude Code / Codex / Gemini — sin medición, sin cuenta), **open source (MIT)**, con un
**verificador de otra familia de proveedor**, **procedencia por línea** y **auto-mejora del equipo (RAI)**.

| Eje | Nota | Lectura |
|---|---|---|
| **Producto / posicionamiento en el nicho** | **8.5 / 10** | La combinación {nativo + BYO-suscripción + sin medición + sin cuenta + MIT + verificador cross-family + provenance + Mapa + mezcla por rol + RAI} no la tiene nadie. |
| **Fuerza de negocio hoy** | **5.5 / 10** | Solo-founder, pre-escala, sin financiación ni distribución. Foso técnico real; el de adopción, empezando. |

**El cuello de botella no es tecnología, es adopción/distribución** (web, onboarding, viralidad).

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
| 12 | **Conductor** (Melty, YC S24) | App **Mac nativa** parallel Claude/Codex/Cursor; ~$22M | **6.5** | 🔴 **La más directa** — misma categoría exacta |
| 13 | **Bolt** (StackBlitz) | Prompt→app en navegador; ~$700M | **6.5** | 🟢 Baja — nicho web, dependiente de Claude |

---

## Los 3 que quitan el sueño (🔴) y nuestra cuña

- **Conductor** — *el gemelo directo*: nativa Mac, local, BYO-suscripción, parallel-worktree, YC. **Ganamos:**
  MIT (ellos cerrados) · añadimos **Gemini** · **mezcla cross-provider por rol + verificador de otra familia**
  (ellos: sesiones paralelas + review humano) · **auto-mejora RAI**.
- **Warp** — ya orquesta Claude+Codex+Gemini en app nativa (motor "Oz"), pero **mete créditos medidos** y
  **rechazó el login por suscripción** (GitHub #9609, cerrada sin enviar); AGPL + Oz propietario. **Ganamos:**
  tus suscripciones **sin medición**, MIT puro, verificador cross-provider.
- **Cognition / Devin Review** — único **reviewer independiente maduro** (+Autofix). **Ganamos:** su reviewer
  es el **mismo proveedor**; el nuestro es **otra familia**; y somos BYO/sin-ACUs/nativo/abierto.

---

## Vigilancia de features de competidores (lo último a seguir)

- **Cognition:** Windsurf → "Devin Desktop" (jun-2026); Agent Command Center + Spaces; Devin Review incluido en todos los planes.
- **Warp:** universal agents (Claude/Codex/Gemini/OpenCode) + "Oz" cloud; cliente open-source AGPL (abr-2026).
- **Zed:** Parallel Agents + ACP (multi-CLI, BYO-keys) — el más cercano en filosofía nativa+abierta.
- **Google:** **mató la Gemini CLI OSS** por `agy` cerrada (18-jun-2026) — backlash; oportunidad de "abierto" para nosotros.
- **Claude Code:** subagents/Agent Teams/grader de 1ª parte + app de escritorio con sesiones paralelas → **riesgo de absorción** (el "¿por qué no el oficial?").
- **Mercado:** más medición en todos (Anthropic + Copilot pasaron a usage-based, mediados 2026) → nuestra postura sin-markup se vuelve más valiosa.

---

## Lo que Coral tiene ya (diferenciadores enviados)

- **Multi-agente cross-provider en una tirada** (orquestador Claude + workers Codex/Gemini) con **streaming en vivo** (Claude vía stream-json; Codex/Gemini bajo PTY) y **fallo rápido + reconexión de login** de un toque.
- **Verificador independiente** (reviewer≠author, otra familia) que gatea loops y revisa diffs de worktree aislado.
- **Procedencia por línea** (qué modelo escribió cada línea, cross-provider).
- **Mapa de código** (grafo visual + inyectado a agentes + ahorro estimado) — incontestado.
- **Arena** (modelos/equipos cara a cara con juez + recomendación).
- **Auto-mejora del equipo (RAI)** — deriva probes del uso real, corre la suite juzgada independientemente, y edita una palanca por ronda hasta converger; humano aprueba. *(Nadie auto-mejora el diseño del equipo con tu historial + juez cross-provider.)*
- **Ship fino** (Vercel/Netlify/Cloudflare) sin ser PaaS. **BYO, sin cuenta, MIT.**
- **"Trabajo repetido" visible** — detecta que un segundo agente rehace lo que otro ya hizo (misma herramienta+objetivo) y lo muestra en la trayectoria; los agentes reportan rutas descartadas/fallos (evidencia, no solo la conclusión). *(Hanako 2026.)*
- **Puerta por blast-radius** — clasifica el diff (contenido→auto · amplio→gate · irreversible→nunca); confirma antes de fusionar irreversibles en aislamiento **y bloquea el auto-merge del Loop** para irreversibles (aditivo; el `loop.sh` generado aún no). La confianza del modelo NO cuenta. *(Eval Engineering 2026.)*
- **Vista de trayectoria "A vs B"** — columnas por agente con los pasos que un compañero rehízo resaltados ("REPETIDO") y "pagado dos veces". *(Hanako 2026.)*
- **Panel de jueces multi-familia** para verificar el diff (promediar rompe el sesgo de familia) + se registra el juez/modelo usado.
- **Memory como "verdad operativa"** — lo auto-cosechado entra como *pendiente de revisión*; solo lo revisado/pinned se inyecta a los agentes (gatekeeping humano). *(Replit 2026.)*

---

## Qué nos falta (prioridad)

| Prio | Hueco | Por qué |
|---|---|---|
| **P0** | **Adopción:** publicar la **web** (`web/` lista) + **tap Homebrew**; **vídeo demo 60s**; medir "time-to-first-run" | El foso técnico no se traduce en usuarios; es el eje donde perdemos. |
| **P1** | **Transparencia app-wide:** que ninguna operación larga parezca congelada (progreso en vivo en todo) | Máxima del founder: "si parece bloqueado, nadie lo usa". ✅ barrido hecho (chat, evals/RAI, map, verify, ship, usage). |
| **P1** | **Riesgo macro:** absorción por 1ª parte (app de Claude Code con sesiones paralelas) | Respuesta = cross-provider + abierto + verificador + RAI (lo que un mono-vendor no puede). |
| **P2** | **Paridad:** memoria dos niveles (User+Org, como Factory); sandboxing por-agente (Conductor NO lo tiene → oportunidad) | Cierra brechas donde Factory nos iguala. |
| **P2** | **Blast-radius en el `loop.sh` generado** (el auto-merge in-app ya lo tiene) | El script ships a otros repos; necesita una versión bash diseñada por humano. |

---

## Viento a favor (datos externos)

- **Stack Overflow 2025:** uso IA **84%** pero solo **33% confía** (46% desconfía); devs senior los más escépticos; 66% pierde tiempo arreglando código "casi correcto". → el verificador + provenance + RAI es la "correa" que piden.
- **Anthropic 2026:** "la verificación es el nuevo cuello de botella"; reviewer de **distinta familia** aún no es estándar → foso defendible.
- **Tamaño de mercado (2026, direccional):** AI code tools ~**$9.4–10.1B**, CAGR ~23–28%.

> **Fuentes clave:** conductor.build · github.com/warpdotdev/warp/issues/9609 · devin.ai/blog/devin-review-windsurf ·
> factory.ai/pricing · docs.factory.ai/cli/byok/overview · zed.dev/pricing · thenewstack.io/gemini-cli-antigravity-replacement ·
> cnbc.com (Cursor) · techcrunch.com (Cognition $10.2B; Cursor precios) · survey.stackoverflow.co/2025/ai ·
> resources.anthropic.com/2026-agentic-coding-trends-report · ampcode.com/manual · aider.chat/docs ·
> sacra.com (Lovable/Replit/Bolt) · mordorintelligence.com / fortunebusinessinsights.com (tamaño mercado).
