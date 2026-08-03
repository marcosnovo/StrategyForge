# Análisis competitivo — Coral vs. orquestadores de agentes de código

**Fecha:** 2026-07-23
**Método:** investigación con 5 agentes en paralelo (WebSearch + WebFetch) sobre repos, sitios y docs
públicos de cada competidor. Todas las afirmaciones citan fuente; donde la fuente devolvió 403 o el
dato no estaba documentado públicamente se marca **(no confirmado)**.
**Audiencia:** producto/roadmap interno.

> **Actualización 2026-07-29 — refresh competitivo (panel de 3 agentes, mercado a julio 2026).**
>
> **Nota:** ~**8.5/10 en su nicho** (orquestador nativo BYO), ~**6.5–7/10 vs el mercado amplio de
> "AI coding tools"** (donde ganan las web hospedadas Cursor/Lovable/Replit por distribución, pulido
> y pipeline de "ship"). El foso **se mantiene pero se ha estrechado por eje**.
>
> **La reivindicación 5-en-1 SIGUE en pie:** ningún competidor combina *equipo multi-agente +
> verificador independiente + multi-proveedor + corre sobre TU suscripción CLI (BYO) + app nativa
> macOS*. Pero por separado: multi-proveedor ya es **table-stakes** (Antigravity, Factory, Zed, Warp,
> Amp), y la orquestación multi-agente también (Warp `/orchestrate`, Claude Code **Agent Teams**,
> Antigravity Agent Manager, Factory Missions). Lo que **sigue siendo raro** es el **verificador
> independiente** (solo Codex Code Review, **Devin Review**, y los *validator agents* de **Factory**);
> el resto se auto-atesta. Lo verdaderamente **incontestado** = verificador independiente + modelo
> económico **BYO-CLI** + **app nativa** juntos.
> - **Amenazas más cercanas:** **Factory.ai (Droids)** — la más completa: orquestador→workers→
>   *validators* en distinto proveedor (verificador real), multi-proveedor BYOK; le falta ser nativa
>   SwiftUI y BYO-por-defecto. **Conductor** (Melty, YC S24, **Serie A $22M ~mar-2026**) — nativa macOS
>   + BYO, pero **solo Claude+Codex (sin Gemini)**, cerrada, sin equipo-coordinado ni verificador.
>   **Devin Review** (Cognition, ex-Windsurf) — verificador real pero Electron + hospedado.
> - **El Mapa (grafo de código) es INCONTESTADO:** nadie ofrece grafo **visual interactivo + inyectado
>   al agente + ahorro de tokens estimado + portable a tu CLI + nativo mac**. Lo commodity es RAG por
>   embeddings (Cursor/Copilot/Windsurf); el grafo real (Sourcegraph SCIP / graphify / Aider repo-map)
>   no es visual+nativo+portable+inyectado. graphify (que Coral envuelve) es una CLI Python + HTML.
> - **Hueco nativo:** hasta la **app Mac oficial de Claude es Electron** ("criminally bad", Gruber);
>   Codex app también Electron; Cursor/Windsurf Electron. Zed/Warp son nativas pero editores/terminales,
>   no orquestadores opinados. → munición para posicionarnos "nativo, sin Electron, MIT, BYO, 3 provs".
>
> **🔴 URGENTE / table-stakes ROTO:** **Gemini CLI se retiró el 18-jun-2026**, sustituida por `agy`
> (Antigravity CLI, Go, quotas peores). **Si Coral sigue lanzando `gemini`, el soporte Gemini está roto
> para la mayoría de usuarios.** → necesita un **adaptador `agy`** ya (ver Bet 1). Verificar
> `ProviderRun`/`ClaudeRunner` resolución del binario `gemini`.
>
> **5 apuestas para ponerse por encima (impacto × unicidad × factibilidad solo-founder):**
> 1. **[HACER YA] Adaptador `agy`** — arreglar Gemini (roto hoy). Table-stakes, no diferencia pero da
>    credibilidad por llegar pronto y correcto.
> 2. **Firma = Arena con juez independiente como motor de recomendación** "¿qué modelo/equipo para esta
>    tarea?" (Claude vs Codex vs equipo mixto → juez puntúa + coste/latencia). Whitespace en nativo.
> 3. **Posicionamiento "autónomo pero rendible/accountable"** — soldar **verificador + procedencia por
>    línea + Loop** en un solo relato. Stack Overflow 2026: 69% mantiene los agentes "con correa", 60%
>    bloquea cambios no aprobados → el verificador independiente + provenance ES la correa que quieren.
>    Barato (usa lo que ya hay), altísima unicidad.
> 4. **"Ship" fino vía MCP** (Vercel/Supabase/Stripe) — tocar idea→desplegado sin ser un PaaS; ningún
>    orquestador-worktree despliega. (shipper.now NO es de Hostinger; el de Hostinger es Horizons;
>    Base44/Lovable/Replit ya integran hosting+dominio+Stripe pero son web para no-devs.)
> 5. **Ganar el hueco "nativo/sin-markup/abierto" a propósito** — benchmarks RAM/arranque vs Electron,
>    "tu gasto no sube con tu proveedor" vs el backlash de precios de Cursor.
>
> **Secuencia:** Bet 1 ya → Bet 3 como núcleo de posicionamiento → Bet 2 como demo-firma → Bet 5
> continuo → Bet 4 cuando el núcleo esté. **Cuidado ToS:** Anthropic prohíbe llevar tokens OAuth
> Pro/Max a clientes de terceros; la vía sancionada es **invocar la CLI oficial con el login del
> usuario** (Coral lo hace — decirlo alto). Fuentes: code.claude.com/docs/agent-teams · factory.ai/news/missions ·
> conductor.build · cognition.com/blog/windsurf · zed.dev/blog/parallel-agents · developers.googleblog.com
> (retiro Gemini CLI) · daringfireball.net (Claude Mac Electron) · stackoverflow.blog (agents on a leash) ·
> graphify.net · sourcegraph.com/blog/announcing-scip · aider.chat/docs/repomap.
>
> **✅ Actualización 2026-07-29 (tarde) — las 5 apuestas ENVIADAS a `main`, gate verde (451 tests).**
> Todas implementadas y probadas en una tirada, cada una como slice separada:
> 1. **agy** — `AIProvider.alternativeBinaries` (`gemini` → `agy`) + resolución de binario en
>    `ProviderRun`/`ProviderRegistry`. Gemini deja de estar roto. *(URGENTE resuelto — quitar de riesgos.)*
> 2. **Arena recomendadora** — `recommendationBanner` en `ArenaView`: nombra ganador (proveedor·modelo),
>    razón (calidad-juez o más-barato) y alternativa más económica.
> 3. **Autónomo pero accountable** — `DiffReviewer` + `ChatViewModel.verifyIsolation()`: verifica el
>    diff del worktree aislado con un **revisor de otra familia de proveedor** antes del merge; veredicto
>    con severidad en `isolationBar`. (Soldado con provenance-por-línea + Loop en el relato del README.)
> 4. **"Ship" fino** — `ShipService` maneja Vercel/Netlify/Cloudflare `wrangler` (detecta CLIs instaladas,
>    despliega en el repo, saca la URL en vivo); menú + confirmación (acción externa) + hoja de resultado.
>    *Nota:* se implementó vía **CLIs de deploy**, no MCP — más honesto con "BYO, corre en tu máquina, sin PaaS".
> 5. **Posicionamiento nativo/BYO/verificador+provenance** — sección "Why Coral is different" en README
>    (nativo-no-Electron, gasto plano, reviewer≠author, provenance por línea, Mapa inyectado, Arena
>    recomendadora, MIT) con brechas honestas (sin pipeline de deploy propio, fuera de MAS).
>
> **Próximo hueco a vigilar:** distribución/pulido web (donde ganan Cursor/Lovable) sigue siendo el eje
> más débil; el foso técnico (verificador+BYO+nativo+Mapa) está reforzado, pero el foso de *adopción* no.

> **Actualización 2026-07-29 (noche) — deep-dive Factory.ai + primer ataque al eje de adopción.**
>
> **Factory.ai (Droids) — amenaza #1, radiografiada.** Unicornio enterprise: ~**$220M** levantados,
> **Serie C $150M @ $1.5B** (abr-2026, Khosla/Keith Rabois), clientes NVIDIA/EY/Adobe/Palo Alto/bancos
> (sesgo fin-serv fuerte, oficina en NYC). Producto **maduro y agent-native multi-superficie**: CLI
> `droid` (buque insignia), app desktop (framework **no revelado** — probable Electron-class), web+móvil,
> extensiones IDE, Slack; ejecución **local o remota** ("Droid Computers" + registro de tu máquina).
> - **Donde son iguales o MEJORES que nosotros (no subestimar):** verificadores separados reales
>   (**Scrutiny** revisa cada worker + **User-testing** black-box; **no arreglan lo que juzgan**);
>   memoria de dos niveles **User+Org**; comprensión de código **"HyperCode"** (grafo **+** embeddings +
>   retrieval "ByteRank") + "Deferred Context Engine" (~50% menos tokens); **Terminal-Bench #1 (63.1%)**
>   por diseño de agente. Regla: **NO** afirmar que a Factory le falta memoria, grafo o verificador.
> - **Grietas estructurales que Coral ataca (nuestras cuñas verificadas):**
>   1. **BYOK solo API-key** — Claude Max / ChatGPT-Codex / Gemini-CLI por *suscripción* **no soportados**
>      (la gente usa proxies no oficiales). Coral conduce esas suscripciones nativamente → **$0 incremental**.
>      *Es la cuña más afilada.*
>   2. **Cobran por tokens** sobre asiento de $20–200/mes con rate-limits rodantes → su queja #1 (HN,
>      reviews) es **facturación impredecible**. Coral no mete capa de medición.
>   3. **Binario cerrado con login obligatorio** + config propietaria + repo público vacío → Coral MIT,
>      sin cuenta, portable, sin lock-in.
>   4. **"Native" desktop de framework opaco**; reviews 2025 citaron lentitud "brutal" y "reporta tests
>      como pasados sin ejecutarlos" → SwiftUI real gana en ligereza/confianza.
>   5. **Enterprise-first explícito** ("la productividad del ingeniero individual ya no basta") → el dev
>      individual / equipo pequeño en **Mac** es el hueco que desprecian y nuestra diana.
>   6. **Paralelismo multi-modelo a nivel Mission = "pregunta de investigación abierta"** (van secuencial)
>      → nuestra mezcla cross-provider en una tirada ya enviada.
>   7. **Sin procedencia por línea.** Coral sí.
>   Fuentes: factory.ai/pricing · /news/missions-architecture · /news/series-c · docs.factory.ai/cli/byok/overview ·
>   techcrunch.com/2026/04/16 (Serie C) · news.ycombinator.com/item?id=45379834 · hyperdev.matsuoka.com (review).
>
> **Diagnóstico confirmado: perdemos en ADOPCIÓN, no en tecnología.** Auditado el onboarding: cuellos =
> (1) Node.js ausente = callejón sin salida, (2) OAuth abre navegador en silencio, (3) sin web/Homebrew,
> (4) onboarding solo hablaba de Claude, (5) la copy no decía la cuña anti-Factory.
>
> **Primer ataque enviado a `main` (gate verde, 451 tests) — 4 slices:**
> 1. **Onboarding "yours, not rented"** — tira de 3 insignias en el primer arranque (sin medición · tus
>    llaves, tu Mac · mezcla proveedores) + línea open-source. Clava la cuña anti-Factory en la primera
>    impresión y surfacea los 3 proveedores como first-class.
> 2. **Fin del callejón Node** — estado dedicado con "Instalar Node con Homebrew" de un toque (reinicia el
>    connect solo) o enlace a nodejs.org; + aviso prominente "mira tu navegador" en el sign-in.
> 3. **Landing page real** (`web/index.html`, estática, sin build) con la cuña + tabla honesta Coral-vs-
>    agente-cloud-medido; **se come su propia comida** (desplegable con la feature Ship).
> 4. **Cask de Homebrew** (`Casks/coral.rb` + `docs/HOMEBREW.md`) → `brew install --cask coral` (publicar
>    el tap es paso manual único).
>
> **Sigue pendiente en adopción:** publicar la web + el tap (hosting/repo, manual del founder); vídeo demo
> de 60s; medir "time-to-first-run". El foso técnico está completo; el de adopción es ahora el trabajo.

---

## 📊 Actualización 2026-08-03 — informe completo del panorama (14 competidores, con notas)

*Método: 4 agentes de investigación en paralelo (WebSearch/WebFetch) sobre docs/sitios/precios oficiales,
a agosto 2026. Afirmaciones con fuente; lo no confirmado va marcado. Nota = fuerza competitiva holística
hoy (producto + foso + momento + distribución), 1–10 — no "cuánto se parecen a Coral".*

### Mapa del mercado + notas

| # | Competidor | Qué es | Nota | Amenaza |
|---|---|---|---|---|
| 1 | **Claude Code** (Anthropic) | CLI agéntica 1ª parte; subagents/Agent Teams/grader; mono-proveedor | **9.5** | 🔴 Alta — es nuestro sustrato y el "¿por qué no el oficial?" |
| 2 | **Cursor** (Anysphere) | IDE Electron; parallel agents + best-of-N; Serie D $2.3B @ **$29.3B** | **9.0** | 🟠 Media — ubicuo, pero mete su propia medición (trauma precios jun-2025) |
| 3 | **Cognition** (Devin + Windsurf/Devin Desktop) | Ingeniero autónomo + **Devin Review** (reviewer real); ~$26B (reportado) | **8.5** | 🔴 Alta — Devin Review contesta nuestro titular "verificador" |
| 4 | **Google Antigravity + `agy`** | Plataforma agéntica + Agent Manager; gratis, multi-modelo (incl. Claude) | **8.0** | 🟠 Media — escala Google, pero **cerró la Gemini CLI OSS** (18-jun-2026) |
| 5 | **Factory.ai** (Droids) | SDLC agéntico enterprise; Serie C $150M @ **$1.5B** (abr-2026) | **8.0** | 🟠 Media — enterprise, **API-key-only**, medido |
| 6 | **Replit** (Agent 4) | IDE cloud + parallel agents + hosting; Serie D $400M @ **$9B**; ~35M users | **8.0** | 🟢 Baja — otro público (no-devs/greenfield); backlash precios "effort-based" |
| 7 | **Lovable** | Vibe-coding web; Serie B $330M @ **$6.6B**; ~$400M ARR | **7.5** | 🟢 Baja — no-devs, silo cloud medido |
| 8 | **Zed** | Editor **nativo Rust, OSS** (1.0 abr-2026); parallel agents + ACP | **7.5** | 🟠 Media — **peer filosófico más cercano** (nativo+abierto+multi-provider) |
| 9 | **Warp** | Terminal nativo (cliente AGPL); **"Oz" orquesta las 3 CLIs** | **7.5** | 🔴 Alta — **solapamiento arquitectónico más directo** |
| 10 | **Amp** (Sourcegraph) | Agente + **"Oracle"** (2ª opinión) reviewer; **sin markup**; 40k equipos | **7.0** | 🟠 Media — reviewer real, pero cerrado/medido/cloud |
| 11 | **Aider** | Pair-programmer **CLI OSS**, BYO-keys, architect/editor | **7.0** | 🟠 Media — **nuestro análogo OSS**; single-agent, sin GUI |
| 12 | **Conductor** (Melty, YC S24) | App **Mac nativa** parallel Claude/Codex/Cursor; **$22M** Serie A | **6.5** | 🔴 **La más directa** — misma categoría exacta |
| 13 | **Bolt** (StackBlitz) | Prompt→app en navegador (WebContainers); ~$700M | **6.5** | 🟢 Baja — nicho web, dependiente de Claude |

### Los 3 que quitan el sueño (amenaza 🔴) y dónde ganamos

- **Conductor** — *el gemelo directo*: nativa Mac, local, BYO-suscripción, parallel-worktree, YC, mindshare
  de categoría. **Ganamos:** **MIT** (ellos cerrados) · añadimos **Gemini** (ellos no) · **mezcla
  cross-provider por rol + verificador de otra familia** (ellos: sesiones paralelas + review humano).
- **Warp** — ya orquesta Claude+Codex+Gemini en app nativa (motor "Oz"), pero **mete créditos medidos** y
  **rechazó el login por suscripción** (GitHub issue #9609, cerrada sin enviar); AGPL+Oz propietario.
  **Ganamos:** conducimos **tus suscripciones sin medición**, MIT puro, verificador cross-provider.
- **Cognition/Devin Review** — único **reviewer independiente maduro y enviado** (+Autofix). **Ganamos:**
  su reviewer es el **mismo proveedor**; el nuestro es **otra familia**; y somos BYO/sin-ACUs/nativo/abierto.

### Nuestra nota

| Eje | Nota | Lectura |
|---|---|---|
| **Producto/posicionamiento en el nicho** | **8.5 / 10** | La combinación {nativo + BYO-suscripción + sin medición + sin cuenta + MIT + verificador cross-family + provenance por línea + Mapa + mezcla por rol} **no la tiene nadie** (verificado vs 14 productos). |
| **Fuerza de negocio hoy** | **5.5 / 10** | Solo-founder, pre-escala, sin financiación ni distribución. Foso técnico real; foso de adopción empezando. |

**Posicionamiento (una frase):** el único orquestador multi-agente **nativo de Mac** que corre sobre **tus
propias suscripciones** (sin medición, sin cuenta), **open source**, con **verificador de otra familia** y
**procedencia por línea**.

### Viento a favor (datos externos)

- **Stack Overflow 2025** (49k respuestas): uso IA **84%** pero solo **33% confía** (46% desconfía); **devs
  senior los más escépticos**; 66% pierde tiempo arreglando código "casi correcto". → *El verificador
  independiente + provenance ES la correa que piden.*
- **El mercado mete MÁS medición** (Anthropic y Copilot pasaron a usage-based a mediados 2026) → nuestra
  postura **BYO-sin-markup** se vuelve más rara y valiosa.
- **"La verificación es el nuevo cuello de botella"** (informe Anthropic 2026), pero **reviewer de distinta
  familia aún no es estándar** → foso defendible.
- **Tamaño de mercado** (estimaciones comerciales, direccional): AI code tools ~**$7.4–7.9B (2025) →
  ~$9.4–10.1B (2026)**, CAGR ~23–28%.

### Qué nos falta (prioridad honesta)

| Prio | Hueco | Por qué |
|---|---|---|
| **P0** | Publicar **web** (`web/` ya lista) + **tap Homebrew**; **vídeo demo 60s** | El foso técnico no se traduce en usuarios; es el eje donde perdemos. |
| **P1** | **Riesgo macro:** absorción por 1ª parte (la app de Claude Code ya hace sesiones paralelas) | Respuesta = cross-provider + abierto + verificador (lo que un mono-vendor **no puede**). |
| **P1** | **Lente de coste nodo/arista** (del artículo *Graph Engineering con Opus 5*) + auditar que los workflows generados paralelizan de verdad | Convierte "sin markup" en visible/medible. Barato. |
| **P2** | Paridad: **memoria dos niveles** (User+Org, como Factory); **sandboxing por-agente** (Conductor NO lo tiene → oportunidad) | Cierra brechas donde Factory nos iguala. |

> **✅ Actualización 2026-08-03 (tarde) — las 4 filas atacadas. Gate NO ejecutado (sesión Linux;
> hay que pasar `xcodebuild test` en el Mac antes de mergear).**
>
> - **P0 — web.** `web/` reescrita **bilingüe (EN + `/es/`)** con los tokens *reales* de la app
>   (paleta `classic` de `DesignSystem.swift`, claro por defecto + oscuro, escala `Space`,
>   `.btn.moon`, fondo aurora + grano) y una **réplica en HTML del shell** (rail → lista de chats →
>   hilo → panel de actividad con topología, veredicto cross-family y ahorro del Mapa). Copy al día
>   con lo enviado (Mapa, Arena, loops, Review, Ship, memoria, export de config). `og.png` 1200×630
>   generada desde `og.source.html` versionado. **Pendiente del fundador:** dominio + desplegar +
>   URLs absolutas de OG.
> - **P0 — vídeo + tap.** [`DEMO-VIDEO.md`](DEMO-VIDEO.md): guion de rodaje de 60s (shot list,
>   subtítulos, ajustes de captura, entregables) — el vídeo hay que grabarlo en el Mac.
>   [`HOMEBREW.md`](HOMEBREW.md) lleva ahora una ruta de día-de-lanzamiento con el orden correcto de
>   dependencias (release → notarización → tap → web).
> - **P1 — riesgo macro (absorción por 1ª parte).** Respuesta escrita y colocada donde se lee: nueva
>   sección en el `README` y en ambas webs. Los tres argumentos estructurales: *un proveedor no te
>   enruta a su rival*, *un verificador de la misma familia no verifica*, *abierto le gana a feature
>   incluida* — más la nota de ToS (invocamos la CLI oficial con tu login).
> - **P1 — lente de coste nodo/arista + auditoría.** `WorkflowShape` extraída de `WorkflowGenerator`
>   como única fuente de verdad; `GraphCostLens` la tarifica (nodos pagados vs aristas gratis,
>   anchura paralela, camino crítico, comparación contra la línea recta) y se muestra en el popover
>   de coste. **La auditoría encontró un bug real:** un rol con `count: 3` emitía **una sola** rama
>   de Work — un equipo que el usuario había ensanchado corría en línea recta. Corregido, y un test
>   sobre `StrategyLibrary.all` asegura que el grafo nunca sea más estrecho que la plantilla.
> - **P2 — memoria dos niveles.** `LearningScope {user, team}`: lo de equipo rankea por delante, se
>   marca `[team]` en el digest como vinculante, y entra en la clave de dedupe (promover una nota
>   personal a convención ya no la colapsa). Una base sin entradas de equipo rankea y renderiza
>   exactamente igual que antes.
> - **P2 — sandboxing por-agente.** `AgentSandbox {auto, worktree, readOnly, shared}` por rol, con
>   selector en el editor. Es **imposición, no prompt**: `readOnly` recorta el `tools:` del agente
>   generado al conjunto de solo-lectura (incluido el grant vacío, que si no heredaría todo) y
>   `worktree` emite `isolation: 'worktree'` en el nodo del workflow. `auto` = comportamiento previo.
> - **Lectura del eje de adopción:** el foso técnico ya no tiene huecos abiertos de este informe. Lo
>   que queda para lanzar es **artefacto, no código** — release + notarización + dominio + vídeo.
>   Ver [`PRODUCT-HUNT.md`](PRODUCT-HUNT.md).

### Nota del artículo *"Graph Engineering con Opus 5"* (@angeldot_)

Tesis: pasar de agentes en **línea recta** a **grafos paralelos**; *"los nodos piensan, las aristas
transportan"* y *"un montón de lo que pagas en tokens es en realidad una arista, y las aristas son gratis"*
(la transformación de datos debe vivir en código, no en llamadas al modelo). **Valida el ADN de Coral**
(las estrategias ya son grafos; verificación adversarial y enrutado dinámico ya enviados). **Acción nueva:**
una **lente de coste nodo(pagado)/arista(código, gratis)** en la vista de estrategia con ahorro estimado, y
**verificar que `WorkflowGenerator` emite diamantes paralelos, no líneas rectas**.

> **Fuentes clave (agosto 2026):** conductor.build · github.com/warpdotdev/warp/issues/9609 ·
> devin.ai/blog/devin-review-windsurf · factory.ai/pricing · docs.factory.ai/cli/byok/overview ·
> zed.dev/pricing · thenewstack.io/gemini-cli-antigravity-replacement · cnbc.com (Cursor $29.3B, nov-2025) ·
> techcrunch.com (Cursor precios jul-2025; Cognition $10.2B) · survey.stackoverflow.co/2025/ai ·
> resources.anthropic.com/2026-agentic-coding-trends-report · ampcode.com/manual · aider.chat/docs ·
> sacra.com (Lovable/Replit/Bolt) · mordorintelligence.com / fortunebusinessinsights.com (tamaño mercado).

---

> **Actualización 2026-07-28 — `main`, gate verde (447 tests).** Nueva feature con foso propio:
> **Mapa de código (grafo de conocimiento)**. Es el mayor diferenciador desde el análisis:
> - **Qué es:** convierte cualquier repo en un grafo de conocimiento consultable (integra la CLI
>   open-source **graphify**, Apache-2.0; AST determinista con tree-sitter + clustering Leiden).
>   Coral la **gestiona sola** (venv Python aislado, pinneado, bootstrap en el primer uso) — no
>   bundlea Python en el `.app`. Render **nativo en Canvas** (lóbulos por clúster, foco por selección
>   con partículas, zoom/pan, búsqueda/filtro) + el `graph.html` interactivo de graphify.
> - **Mapea sin copia local:** acepta URL de GitHub o **elige de tus repos** (`gh repo list`), clona
>   en shallow a una carpeta gestionada, y **cachea solo el grafo** (no el repo) → reabrir es
>   instantáneo y **sin gastar tokens** (`MapStore` persistente).
> - **El diferenciador real (orquestación):** el mapa se **inyecta en el contexto del agente** en el
>   primer turno (persiste vía session-resume) para que arranque con la estructura en vez de releer
>   archivos; **ahorro de tokens estimado** mostrado junto al % de uso. Acciones nodo↔código↔chat:
>   Abrir archivo, Explicar (`graphify explain`), Ruta (`graphify path`), Preguntar (abre chat atado
>   al repo con el mapa inyectado), y Watch (rebuild en caliente).
> - **Posición:** **ningún** rival tiene un grafo de código **nativo + inyectado a los agentes + con
>   ahorro medible**. Cursor/Windsurf indexan para su propio chat (no exportan a tu CLI ni orquestan
>   equipos); graphify suelto es un skill sin app. Refuerza el foso "orquestador nativo".
> - **Huecos recién detectados (honesto):** (1) **cola de "ship it"/deploy** — investigado shipper.now:
>   sin API pública, así que sería nativo (Vercel/Cloudflare/Supabase CLIs); **no construido**. (2)
>   **MCP multi-proveedor** — hoy Coral solo escribe `.mcp.json` (Claude); Codex (`config.toml`) y
>   Gemini (`settings.json`) también soportan MCP pero con otros formatos: pendiente generar sus
>   configs. (3) UI/UX del Mapa e **IA del rail** a pulir (en curso).
> - **Nota interna orientativa:** Coral ~**8.5/10** en su nicho (orquestación nativa multi-proveedor +
>   loop verificador + memoria + mapa); pierde puntos por lo aún-manual (notarización/release sin
>   estrenar, sync CloudKit dormido, deploy inexistente) y por pulido de UX en las secciones nuevas.
>
> **Actualización 2026-07-27 — `main`, gate verde (430 tests).** Iteración de **diseño +
> rendimiento** (no de features nuevas de competidores, así que el análisis de abajo sigue
> vigente). Refuerza directamente el foso "**única app nativa macOS pulida y liviana**" frente
> a los rivales Electron/web/CLI:
> - **Diseño "Living Reef"**: default claro espectacular (porcelana + amanecer coral) con oscuro
>   bioluminescente a un clic; grano de película; héroe editorial; disciplina de coral (un acento).
> - **Layout ChatGPT-calm**: rail de iconos expandible/colapsable, lista de chats bajo demanda,
>   panel de actividad inline, barra superior unificada, acciones con hover+tooltip.
> - **Firma multi-agente cohesiva**: topología coloreada por rol (Equipos + panel), lista de agentes
>   "quién hace qué" estilo Codex.
> - **Huella mínima** (auditoría 3 agentes + supervisor, ×2): en reposo no anima nada; RAM acotada
>   (evicción de ViewModels, provenance capada, stdout recortado); arranque en paralelo; trabajo pesado
>   fuera del hilo principal; git con watchdog. Ver `docs/CHATGPT-STYLE-REDESIGN.md` §2026-07-27.
> - **Equipos multi-proveedor/agente** re-verificados por las suites (Meta/Advisor/Arena/CrossProvider).
>
> **Estado a 2026-07-24 — en `main`, gate `xcodebuild test` verde (401 tests).** Todo lo
> "Inmediato" y la **memoria entre proyectos** completa están mergeados y verdes; ya no es
> una proyección. Cerrado desde que se escribió el análisis:
> 1. **Loop de Review cerrado** — botón opt-in "Corregir todo" que reinyecta los hallazgos
>    al equipo autor.
> 2. **Procedencia por línea** — atribución por línea en el diff (ruta nativa Claude),
>    barra tintada por proveedor + tooltip "Agente · Modelo". Coral es **el único de la
>    categoría** con esto (cross-proveedor por línea sigue pendiente).
> 3. **Notificación remota de loops** — webhook (ntfy→móvil / Slack / Discord / genérico)
>    al terminar un run, además de la notificación local existente.
> 4. **Memoria de conocimiento entre proyectos** — base global de learnings que se inyecta
>    en `CLAUDE.md` y en el `LOOP.md` del loop, con captura (manual / STATE.md / Review) y
>    **reflexión post-run**. Sync CloudKit codificado pero dormido (Slice 7). Item de *medio
>    plazo* adelantado.
> 5. **Modo "Arena"** en tres niveles — *Models* (N proveedores), *Teams* (estrategias de
>    equipo enteras, progreso en vivo) y *Code* (edita en worktree git aislado → comparas
>    diffs → aplicas el ganador; **compite proveedores sueltos O equipos multi-agente enteros**),
>    + **juez independiente** que puntúa por calidad. **Supera** a Parallel Code (solo modelos,
>    sin juez ni aislamiento). Varios items de *medio plazo* adelantados.
>
> Único trabajo manual restante (no bloquea código): **captura visual light/dark** de las
> features nuevas, y **verificar el sync CloudKit en dispositivo** (añadir el record type
> "Learning" al esquema del container — tarea de fundador, igual que el sync de config).

---

## 1. Resumen ejecutivo

**Posición de mercado.** Coral compite en una categoría que aún no tiene nombre asentado
("orquestador nativo de equipos de agentes de código, sobre tu propia suscripción CLI"). Es la
**única app nativa macOS** de la lista que combina: topología orquestador→subagentes con un solo
nivel de delegación, mezcla de proveedores por rol dentro de un mismo equipo, loop autónomo con
verificador independiente no auto-calificado, y exportación de la configuración real de Claude Code
para que el equipo diseñado corra también fuera de la app. Nadie más junta las cuatro cosas.

**Hallazgos clave:**
1. Coral ya notifica localmente (`LoopNotifier`, notificación del sistema) cuando un loop termina o
   falla, incluso en segundo plano — pero solo si el Mac está despierto. El hueco real y de mayor
   impacto práctico es la falta de **notificación remota/fuera del Mac** (móvil, email) para cuando
   el equipo está dormido o el usuario no está delante — varios competidores resuelven parte de esto.
   **→ Resuelto en PR #27** (webhook ntfy/Slack/Discord/genérico).
2. Coral vende "mezcla de proveedores por rol" como diferenciador pero no tenía **procedencia por
   línea** (qué modelo escribió qué). **→ Resuelto por completo:** por línea en la ruta nativa Claude
   **y cross-proveedor** (`CrossProviderEditor` corre workers de distinto proveedor editando en
   secuencia y atribuye cada línea a su proveedor). Nadie más en la categoría lo tiene.
3. El "Review" de Code mode hoy es de un solo sentido (agente lee el diff, humano decide) mientras
   que Traycer y metaswarm ya **cierran el bucle**: hallazgos categorizados que vuelven solos al
   agente autor para arreglarse. **→ Resuelto en PR #27** (botón opt-in de reinyección).
4. metaswarm tenía la **memoria entre proyectos** más madura de la categoría (base de conocimiento +
   reflexión post-merge). **→ Resuelto:** Coral ya tiene base global de learnings que se inyecta en
   el `CLAUDE.md` de cada equipo y en el `LOOP.md` del loop, **y reflexión post-run** que cosecha el
   STATE.md a la base al terminar (`MemoryStore`/`MemoryDigest`/`LoopStore.harvestStateFile`). La
   diferencia restante con metaswarm es de *madurez* (BEADS, reflexión más rica), no de existencia.
5. Nadie en la categoría —ni Coral— resuelve bien la tensión "sandbox-off por diseño" vs. confianza;
   Parallel Code es el único con sandboxing Docker opcional por tarea.

**Implicación estratégica:** Coral no compite hoy por paridad de features (ya tiene la combinación
más completa en equipos+loops+exportabilidad); compite por **cerrar los tres o cuatro huecos que
más fricción/desconfianza generan** sin diluir su identidad ("nativo, tu suscripción, sin servidor").

---

## 2. Perfiles de competidores

### Traycer (traycer.ai / github.com/traycerai/traycer)
- **Producto:** app de escritorio Electron, open source (MIT), builds macOS/Linux/Windows.
- **Cliente objetivo:** equipos de desarrollo que ya usan varias CLIs/extensiones (Claude Code,
  Codex, Cursor, OpenCode) y quieren coordinarlas sin perder contexto.
- **Propuesta de valor:** "trae tu propia suscripción" + agentes que se comunican entre sí (debate/
  peer-review) + "Epic Mode" que convierte intención en PRD → plan técnico → tickets ejecutados en
  fases, con un modo "Smart YOLO" que auto-decide rigor.
- **Fuerte en:** Review Mode con severidad (Critical/Major/Minor) que **realimenta al agente
  autor automáticamente**; colaboración multi-humano en tiempo real (boards compartidos, asignación
  de tickets) — la única de la lista con esto.
- **Débil en:** no es nativo (Electron); topología orquestador↔subagentes menos estricta que la de
  Coral (agentes "debaten" en vez de un solo orquestador delegando); sin aislamiento por git worktree
  documentado.
- **Actividad reciente:** lanzamiento del Desktop App gratuito/open source (anuncio en X, 2026);
  precio de la app en sí no confirmado — planes de $10–40/usuario/mes parecen ligados a su servicio
  de "artifacts", no a la app de escritorio en sí **(no confirmado del todo — docs.traycer.ai y la
  página de precios devolvieron 403)**.

### Parallel Code (github.com/johannesjo/parallel-code / parallelcode.app)
- **Producto:** app Electron (SolidJS), MIT, gratis, macOS + Linux (sin Windows).
- **Cliente objetivo:** desarrolladores solo que quieren lanzar varias tareas independientes a la vez
  sin pisarse.
- **Propuesta de valor:** cada tarea = su propio git worktree + rama; revisar diffs y hacer merge con
  un atajo de teclado; "AI Arena" para correr la misma tarea con Claude/Codex/Gemini a la vez y
  quedarte con el mejor resultado.
- **Fuerte en:** aislamiento por worktree muy pulido (symlink automático de `node_modules`, modo
  "directo" sin git), sandboxing Docker opcional por proyecto, panel de cobertura de tests por
  archivo, vigilancia de estado de CI de una PR con notificación de escritorio.
- **Débil en:** no hay jerarquía de equipo ni reparto de roles (cada agente trabaja una tarea aislada,
  no colabora en una); sin loop autónomo de verificación; sin tracking de coste/tokens; sin memoria
  entre tareas.
- **Actividad reciente:** proyecto activo, blog con comparativas Claude Code vs Codex vs Gemini CLI.

### maestro-orchestrate (github.com/josstei/maestro-orchestrate) y metaswarm (github.com/dsifry/metaswarm)
- **Producto:** ambos son *frameworks* de configuración (no apps con interfaz), instalables como
  plugin/extensión sobre Gemini CLI, Claude Code, Codex (y Qwen Code). maestro: Apache-2.0, ~39
  agentes especialistas. metaswarm: MIT, ~18-19 agentes.
- **Cliente objetivo:** equipos que ya viven en la terminal y quieren un pipeline de desarrollo
  disciplinado (spec → plan → implementar → validar → PR) sin salir de la CLI.
- **Propuesta de valor:** gates de aprobación explícitos entre fases; auditorías integradas
  (seguridad, accesibilidad, SEO, cumplimiento — maestro); pipeline spec-driven con revisión
  adversarial de 3 revisores y regla explícita "el escritor siempre es revisado por un modelo
  distinto" (metaswarm).
- **Fuerte en:** metaswarm tiene la **memoria entre proyectos más madura** de toda la categoría — una
  base de conocimiento (BEADS + JSONL) de la que los agentes "priman" antes de cada tarea y a la que
  aportan aprendizajes tras cada merge. Los gates de ambos son genuinamente independientes (agentes
  separados, no auto-calificación). *(Actualización 2026-07-24: Coral ya tiene base de conocimiento
  entre proyectos con inyección + reflexión post-run; la ventaja de metaswarm se reduce a madurez
  —BEADS, reflexión más rica—, no a existencia.)*
- **Débil en:** sin interfaz gráfica; maestro no confirma mezcla de proveedores dentro de una misma
  tarea colaborativa (cada runtime se apunta por separado); sin exportación a otro formato — la
  config *es* el producto.
- **Actividad reciente:** maestro ~449 estrellas, ~115 commits, releases hasta v1.6.4 (actividad
  aparente). Fechas de metaswarm inconsistentes en las fuentes consultadas — **cadencia de
  mantenimiento no confirmada, revisar manualmente**.

### Clave (github.com/codika-io/clave)
- **Producto:** app nativa macOS (Apple Silicon/Intel), MIT, gratis.
- **Cliente objetivo:** desarrolladores que ya corren Claude Code/Codex/Antigravity y quieren
  gestionar muchas sesiones en paralelo, incluidas máquinas remotas.
- **Propuesta de valor:** grid/split de sesiones PTY ilimitadas, agrupadas por proyecto; **sesiones
  remotas por SSH** con SFTP integrado (única de la lista con esto); "MagicSync" (pull→stage→mensaje
  de commit generado por IA→commit→push en un clic); sin backend en la nube, sin cuenta.
- **Débil en:** sin jerarquía de equipo, sin mezcla de roles, sin loop de verificación, sin tracking
  de uso/coste documentado, sin sync entre Macs (por diseño de privacidad).
- **Actividad reciente:** proyecto activo en GitHub **(fecha de última release no confirmada)**.

### ccmanager (github.com/kbwo/ccmanager) y agent-orchestrator (github.com/AgentWrapper/agent-orchestrator)
- **Producto:** ccmanager es un gestor de sesiones en terminal (Node/Bun, MIT, sin GUI).
  agent-orchestrator es una "Agent IDE" Electron+React con un daemon en Go (Apache-2.0).
- **Cliente objetivo:** ccmanager → desarrolladores de terminal que alternan entre muchas sesiones/
  worktrees. agent-orchestrator → equipos que quieren que los agentes reaccionen solos a CI/PR.
- **Propuesta de valor:** ccmanager copia el historial/contexto de Claude Code al crear una rama-
  worktree nueva, y tiene auto-aprobación experimental de prompts "seguros" vía Haiku.
  agent-orchestrator tiene un "SCM Observer" que **sondea la API de GitHub cada 30s** (no webhooks)
  y enruta fallos de CI/comentarios de review de vuelta a la sesión del agente que originó el PR —
  el soporte más amplio de la categoría, 23+ CLIs.
- **Débil en:** ninguno de los dos tiene jerarquía de equipo con roles ni mezcla de proveedores
  dentro de una tarea; si agent-orchestrator auto-empuja el fix o espera aprobación humana **no está
  confirmado** en su documentación pública.

### LittleLLM (referencia de otro segmento, no competidor directo)
Cliente de chat multi-proveedor (Electron) que usa **API keys de pago por token**, no CLIs por
suscripción — el eje que lo separa de Coral y de todos los anteriores. Se incluye solo como
referencia de posicionamiento (ver mapa, sección 5), no en la matriz de features porque compite en
una tesis de producto distinta.

---

## 3. Matriz de funcionalidades

Leyenda: ✅ Completo/producción · ⚠️ Limitado, parcial o no confirmado · ❌ Ausente

| Funcionalidad | **Coral** | Traycer | Parallel Code | metaswarm | Clave | agent-orchestrator |
|---|---|---|---|---|---|---|
| App nativa (no Electron) | ✅ | ❌ | ❌ | ❌ (sin GUI) | ✅ | ❌ |
| Motor: CLI de tu suscripción (no API keys) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Orquestador→subagentes, 1 nivel de delegación | ✅ | ⚠️ (peer-to-peer, no confirmado como jerarquía estricta) | ❌ | ✅ | ❌ | ⚠️ |
| Mezcla de proveedores por rol en un mismo equipo | ✅ | ✅ | ❌ (Arena = competir, no repartir roles) | ✅ (regla explícita autor≠revisor) | ❌ | ⚠️ |
| Plantillas de estrategia/topología predefinidas | ✅ (13, editables) | ⚠️ (Epic Mode auto-decide, sin catálogo nombrado) | ❌ | ✅ (pipeline fijo) | ❌ | ❌ |
| Loop autónomo con verificador independiente | ✅ | ✅ | ❌ | ✅ | ❌ | ⚠️ |
| **Auto-fix cerrado desde la revisión** (hallazgo → vuelve solo al autor) | ✅ (botón opt-in "Corregir todo") | ✅ | ❌ | ✅ | ❌ | ⚠️ (no confirmado auto-push) |
| Aislamiento por git worktree | ✅ (en loops) | ❌ | ✅ (su feature central) | ⚠️ | ⚠️ | ✅ |
| Ejecución competitiva multi-proveedor ("Arena") | ✅✅✅ (nuevo — **tres niveles**: *Models* (N proveedores), *Teams* (estrategias enteras multi-proveedor, progreso en vivo) y *Code* (**edita en worktree git aislado** → compara diffs → aplica ganador; árbol intacto hasta aplicar). *Code* compite **proveedores sueltos O equipos multi-agente enteros** —cada equipo corre nativo con sus subagentes editando, andamiaje `.claude` como baseline para que el diff sea solo el código—. + **juez** que puntúa por calidad en los tres. Solo Coral: *Teams* y *Code*-de-equipos no los tiene nadie) | ❌ | ✅ (solo *Models*, sin juez ni aislamiento) | ❌ | ❌ | ❌ |
| Memoria/conocimiento persistente **entre proyectos** | ✅ (nuevo — base global de learnings patrón/decisión/error, `MemoryStore`; se inyecta en `CLAUDE.md` **y en el `LOOP.md` del loop**; captura manual / import de STATE.md / promote desde Review; **reflexión post-run** que cosecha el STATE.md a la base al terminar. Sync CloudKit codificado pero dormido hasta verificar en dispositivo) | ⚠️ (contexto compartido, alcance sin confirmar) | ❌ | ✅ (BEADS + base de conocimiento + reflexión) | ❌ | ❌ |
| Sandboxing opcional (Docker) por tarea | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Sesiones remotas (SSH a otra máquina) | ❌ | ❌ | ⚠️ (solo ver progreso vía QR/Tailscale) | ❌ | ✅ | ❌ |
| Notificación/companion remoto del estado del loop | ✅ (webhook ntfy→móvil / Slack / Discord / genérico al terminar; + notificación local `LoopNotifier`) | ⚠️ (sync entre dispositivos, sin push explícito) | ⚠️ (notif. de escritorio + QR remoto) | ❌ | ❌ | ⚠️ (vigila CI, no notifica al usuario fuera de la app) |
| Procedencia por línea (qué modelo/rol escribió qué) | ✅✅ (por línea en el diff en la ruta nativa Claude **Y cross-proveedor**: `CrossProviderEditor` corre los workers de distinto proveedor en secuencia editando el mismo worktree y atribuye cada línea a su proveedor vía `LineAttributor`; se ve en la Arena de código con panel "escrito por") | ❌ | ❌ | ❌ | ❌ | ❌ |
| Exporta config real reutilizable fuera de la app | ✅ (`.claude/agents` + `CLAUDE.md` + workflow) | ❌ | ❌ | N/A (la config *es* el producto) | ❌ | ❌ |
| Sync multi-dispositivo (config/equipos) | ✅ (CloudKit) | ✅ | ❌ | ❌ | ❌ (por diseño) | ❌ |
| Seguimiento de uso/coste (tokens, % de plan) | ✅ | ⚠️ (cuotas por "artifacts", no tokens) | ❌ | ❌ | ❌ | ❌ |
| Vigilancia automática de CI/PR (reacciona sola) | ❌ | ⚠️ | ✅ (notif. escritorio) | ❌ | ❌ | ✅ (sondeo cada 30s a GitHub) |
| Colaboración multi-humano en tiempo real | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Marketplace comunitario de plantillas/agentes | ❌ | ❌ | ❌ | ⚠️ (marketplace de *instalación*, no de plantillas de terceros) | ❌ | ❌ |
| Licencia | MIT | MIT | MIT | MIT | MIT | Apache-2.0 |
| Precio | Gratis | Freemium ~$10-40/u/mes (app en sí, gratis) | Gratis | Gratis | Gratis | Gratis |

**Nota de calidad:** "✅" en verificador/gates no significa lo mismo en todos — metaswarm y Traycer
tienen el bucle más cerrado (hallazgo → fix automático). Coral **cierra su bucle de Review** (botón
opt-in que reinyecta los hallazgos al equipo autor), sumándose a ese grupo; la diferencia restante es
que en Traycer/metaswarm el reintento es automático dentro del pipeline, mientras en Coral es un tap
deliberado (opt-in por diseño, para no gastar tokens sin que lo pidas).

**Nota sobre "procedencia por línea":** Coral es el único de la categoría con atribución por línea en
el diff — y ahora **en ambas rutas**: la nativa Claude (subagentes editando en una sesión `claude`) y
la **cross-proveedor** (`CrossProviderEditor` corre los workers de distinto proveedor en secuencia
editando el mismo worktree, y `LineAttributor` acredita cada línea a su proveedor). Se ve en la Arena
de código. *Polish restante:* un diff coloreado línea a línea por proveedor (los datos ya están en
`CrossProviderResult.lineAuthors`).

---

## 4. Mapa de posicionamiento

Ejes: **X** = motor de ejecución (API keys de pago por token ←→ tu propia suscripción CLI) · **Y** =
forma de coordinar agentes (gestor de sesiones/tareas paralelas ←→ orquestador jerárquico de equipo
con roles).

```
        Orquestador jerárquico de equipo
                    │
        metaswarm   │   ● Coral
      (sin GUI)     │   (única nativa aquí)
                     │
   Traycer ●         │
                     │
API keys ────────────┼──────────────── Tu suscripción CLI
                     │
   LittleLLM ●       │  Parallel Code ●
  (chat + personas)  │  agent-orchestrator ●
                     │  Clave ● ccmanager ●
                     │
        Gestor de sesiones/tareas paralelas
```

**Hueco blanco (whitespace):** el cuadrante "arriba-derecha" — nativo + jerarquía de equipo real +
tu propia suscripción — está ocupado casi en solitario por Coral. metaswarm comparte el eje Y pero no
el X en distribución (sin GUI). El resto de la categoría vive en el cuadrante inferior (gestión de
sesiones paralelas), que es un problema más simple y ya tiene varios jugadores maduros.

---

## 5. Por qué ganamos / por qué perdemos

**Por qué ganamos:**
- Usuarios que quieren una experiencia nativa macOS pulida (no Electron).
- Quien diseña equipos con roles y quiere mezclar proveedores a propósito (Claude orquestando,
  Codex programando, Gemini revisando), no solo lanzar la misma tarea a varias CLIs.
- Quien valora que el verificador de un loop **no pueda ser convencido por el propio agente que
  hizo el trabajo** — el freno duro + verificador independiente es más estricto que la mayoría.
- Quien quiere que el diseño hecho en la app también funcione en una sesión `claude` normal fuera
  de la app (nadie más exporta config real).
- Quien ya paga varias suscripciones (Claude, ChatGPT, Gemini) y no quiere gestionar facturación
  por token ni repartir sus claves de API entre apps de terceros.

**Por qué perdemos:**
- Si el usuario necesita Windows/Linux → Traycer, Parallel Code, agent-orchestrator.
- Si quiere ejecutar en un servidor remoto siempre encendido → Clave (SSH).
- Si necesita colaboración de varias personas en tiempo real sobre el mismo tablero → Traycer.
- Si quiere el roster más amplio posible de CLIs soportadas (23+) → agent-orchestrator.
- ~~Si quiere memoria de conocimiento acumulada entre proyectos *ya hoy* → metaswarm.~~ **(cerrado:**
  Coral tiene base de conocimiento entre proyectos con inyección en `CLAUDE.md`/`LOOP.md` y reflexión
  post-run; metaswarm solo mantiene ventaja de *madurez*, no de existencia.)
- Si prefiere no instalar/autenticar CLIs propias y pagar por token vía un agregador → LittleLLM
  (segmento distinto, pero roba consideración a usuarios menos técnicos).

---

## 6. Recomendaciones estratégicas

**Inmediato (0-3 meses) — ✅ HECHO en PR #27** (pendiente gate `xcodebuild test` en Mac). Los tres
eran extensiones de features ya existentes; se implementaron en una sola tanda:

1. **Cerrar el loop de Review** — ✅ botón opt-in "Corregir todo" en el panel de Review que compone
   los hallazgos (`DiffReviewer.fixPrompt`) y los reinyecta al equipo autor como un turno de chat
   (`ChatViewModel.requestReviewFixes`). Revisor ≠ autor se mantiene: el revisor solo califica.
   *Resultado:* Coral se suma a Traycer/metaswarm; la diferencia restante es automático (ellos) vs.
   opt-in de un tap (nosotros, por diseño para no gastar tokens sin permiso).
2. **Procedencia por línea** — ✅ atribución por línea en el diff (`LineAttributor`, diff por
   snapshot en cada edición) con barra tintada por proveedor + tooltip "Agente · Modelo"; punto por
   fichero (último editor) en la lista de cambios. *Resultado:* Coral queda **solo** en la categoría
   con esto. *Restante:* es a nivel de línea en la ruta nativa Claude; la versión cross-proveedor
   necesita workers editando en worktrees aislados (medio plazo — ver abajo).
3. **Notificación remota de loops** — ✅ `LoopWebhookNotifier` hace POST a un webhook configurable
   (ntfy→móvil / Slack / Discord / genérico) al terminar un run, junto a la notificación local
   existente. Off por defecto, sin backend, URL local. *Resultado:* cubre el caso "no estoy delante
   del Mac" que era el hueco de mayor impacto práctico. *Elección de diseño:* webhook en vez de
   email (SMTP) o APNs (servidor) para no romper el ethos "sin backend, sin credenciales".

**Medio plazo (3-12 meses)** — más ambiciosas, requieren diseño propio o tocan el modelo de
confianza:

1. **Memoria de conocimiento persistente entre proyectos** — ✅ **HECHO** (base + inyección + UI).
   Base global `MemoryStore` de learnings (patrón/decisión/error) con `source` obligatoria (sin
   conocimiento fabricado por LLM); ranking puro (`MemorySelector`) e inyección del digest
   (`MemoryDigest`) dentro del bloque gestionado del `CLAUDE.md` de cada equipo (digest vacío =
   salida byte-idéntica). Captura: manual, import de `STATE.md` (`StateFileParser`), y "Guardar en
   memoria" desde el panel de Review. Sección de nav **Memoria** para gestionarla. *Resultado:*
   refuerza "equipos que mejoran con el tiempo". **Slice 6 hecho:** inyección también en el `LOOP.md`
   del loop (gated, revisión del diff vetado hecha) + **reflexión post-run** que cosecha el `STATE.md`
   a la base al terminar (`LoopStore.harvestStateFile`). **Slice 7 hecho (dormido):** sync CloudKit
   codificado (`LearningSyncStore`/`LearningMerge` LWW), pendiente solo de añadir el record type
   "Learning" al esquema y verificar en dispositivo.
2. **Modo "Arena"** — ✅ **HECHO en dos niveles.**
   - **Models** (`ArenaEngine` sobre `OneShotRunner`): misma tarea a N proveedores, tarjeta por
     competidor con respuesta + tokens/coste, ganador sugerido = el más barato, "Seguir en un chat".
   - **Teams** (`StrategyArenaEngine` sobre `MetaOrchestrator`): compite **estrategias de equipo
     enteras** (multi-proveedor/multi-modelo) en la misma tarea. **Seguro por construcción** (runner
     solo-lectura → los competidores no se pisan). **Transparencia en vivo** por competidor —fase
     (planificar/delegar/sintetizar), agentes activos como chips, reloj que avanza cada segundo,
     tokens/coste acumulando— porque un run agéntico tarda minutos y no puede parecer bloqueado.
     Guard de coste con confirmación antes de lanzar; cancelable.
   - **Code** (`CodeArenaEngine`): compite **proveedores sueltos O equipos multi-agente enteros**,
     cada uno **editando en su propio git worktree aislado**; los equipos corren nativos (`.claude`
     materializado + `claude` con sus subagentes editando, andamiaje como baseline para que el diff sea
     solo el código). Comparas diffs y **solo el ganador que apliques** se mergea (el resto se limpia;
     árbol del usuario intacto hasta aplicar). Verificado con tests de git real.
   - **Juez independiente** opt-in (`ArenaJudge`, read-only, autor≠juez) que puntúa 0-100 por *calidad*
     en los tres niveles (en Code puntúa los diffs). **Estimación de coste previa** (`ArenaCostEstimator`)
     junto a Run y en las confirmaciones. **Cross-proveedor:** equipos con roles de distinto proveedor
     editan por el `CrossProviderEditor` (workers en secuencia, procedencia por línea). *Resultado:*
     Coral **supera** con creces a Parallel Code (solo modelos, sin juez, sin aislamiento, sin
     procedencia). *Polish restante:* diff coloreado por proveedor línea a línea.
3. **Sandboxing Docker opcional por loop.** *Por qué:* responde directamente a la objeción de
   confianza que el propio SECURITY.md ya reconoce (sandbox-off, ejecuta shell autónomamente), sin
   renunciar al modelo "tu propia máquina, tu propia suscripción".
4. **Evaluar sesiones remotas (SSH a otra máquina)** solo si hay señal real de demanda de "correr en
   un servidor siempre encendido en vez de mi portátil". *Por qué queda en medio plazo y no
   inmediato:* cambia la superficie de seguridad de la app de forma no trivial — merece diseño
   propio, no una réplica rápida de lo de Clave.

---

## 7. Backlog

**Hecho y en `main` (gate `xcodebuild test` verde):**

- [x] Loop de auto-fix cerrado desde Review (Code mode) — botón opt-in "Corregir todo"
- [x] Procedencia por línea de qué modelo/rol escribió cada línea — en el diff, ruta nativa Claude
- [x] Notificación remota de estado de loop — webhook (ntfy/Slack/Discord/genérico), + local existente
- [x] **Memoria entre proyectos** — base de conocimiento global (`MemoryStore`) + `Learning` con
      `source` obligatoria (sin conocimiento fabricado)
- [x] Inyección del digest en el `CLAUDE.md` de cada equipo **y en el `LOOP.md` del loop**
      (`ClaudeMdGenerator` / `LoopFileGenerator`, digest vacío = salida byte-idéntica)
- [x] Captura: manual, import de `STATE.md` (`StateFileParser`), promote desde Review, y **reflexión
      post-run** que cosecha el `STATE.md` a la base al terminar (`LoopStore.harvestStateFile`)
- [x] Sección de nav **Memoria** (lista + editor + filtros)
- [x] Sync CloudKit de la memoria — código hecho (`LearningSyncStore` + `LearningMerge` LWW), **dormido**
      tras `LocalOnly`

**Trabajo manual restante (no bloquea código):**

- [ ] Capturas light/dark del botón "Corregir todo", el punto por-fichero, la barra por-línea y la
      sección **Memoria** (verificación visual del fundador)
- [ ] Activar el sync CloudKit de memoria: añadir el record type "Learning" al esquema del container
      y verificar en dispositivo (misma tarea pendiente que el sync de config)

**Siguiente foco (medio plazo, sin empezar):**

- [x] ~~**Modo "Arena"** (competir proveedores en la misma tarea)~~ — hecho en 2 niveles: *Models*
      (`ArenaEngine`) y *Teams* (`StrategyArenaEngine` sobre `MetaOrchestrator`, con progreso en vivo,
      solo-lectura y guard de coste)

**Descubierto durante la Arena de equipos (priorizado):**

- [x] ~~**P1 · Arena para tareas de CÓDIGO**~~ — **HECHO** (`CodeArenaEngine`, modo *Code*). Cada
      proveedor edita en su propio **git worktree aislado** (rama off HEAD); se captura el diff (incl.
      ficheros nuevos), se comparan lado a lado y **solo el ganador que apliques** se mergea (mergeNoFF)
      al árbol del usuario — el resto de worktrees/ramas se limpian. Verificado con tests de git real
      (aislamiento, apply, cleanup). El juez puntúa los diffs. *Restante honesto:* hoy compite
      **proveedores** editando (Claude ya es agéntico dentro de su worktree); competir **equipos
      multi-agente enteros** editando (subagentes editando) necesita ejecución nativa por competidor —
      siguiente paso. Y comparte pieza con ↓.
- [x] ~~**P1 · Juez independiente para la Arena**~~ — **HECHO** (`ArenaJudge`). Botón opt-in "Juzgar"
      en Models y Teams: un agente read-only (el proveedor conectado más fuerte, prefiere Claude)
      puntúa 0-100 cada respuesta contra la tarea y elige ganador por *calidad*, no solo coste.
      Candidatos anonimizados por letra (juzga la sustancia, no la marca); autor≠juez; badge de nota +
      razón por tarjeta.
- [ ] **P2 · Estimación de coste previa en la Arena de equipos** — hoy se avisa y se muestra el coste
      en vivo; una estimación *antes* de lanzar (por nº de agentes/modelos) daría más control. Reutiliza
      `CostEstimationHooks`.

**Otras (medio plazo):**

- [x] ~~**P2 · Arena de CÓDIGO con equipos multi-agente enteros**~~ — **HECHO**. La arena de código
      compite *proveedores sueltos* O *equipos enteros* (nativo Claude o cross-proveedor, ↓).
      `CodeContestant` unifica ambos; diff comparado excluye el andamiaje. Verificado con git real.
- [x] ~~**Procedencia por línea cross-proveedor**~~ — **HECHO** (`CrossProviderEditor`). Workers de
      distinto proveedor editan el mismo worktree en secuencia; cada línea se atribuye a su proveedor
      (`LineAttributor`). Se ve en la Arena de código (panel "escrito por" por fichero). *Polish
      restante:* un diff coloreado por proveedor línea a línea (los datos ya están en `lineAuthors`).
- [x] ~~**Equipos con orquestador no-Claude editando**~~ — **HECHO** vía el editor secuencial de arriba.
- [x] ~~**P2 · Estimación de coste previa**~~ — **HECHO** (`ArenaCostEstimator`): chip "~Xk tok · $Y"
      junto a Run y en las confirmaciones de las tres arenas.
- [x] ~~**Polish:** diff coloreado por proveedor línea a línea en la Arena/Code mode~~ — **HECHO**
      (`ProvenanceDiff`): cada línea añadida se tinta con el tono del proveedor que la escribió.
- [ ] **P1 · Rediseño "ChatGPT-calm"** — plan completo en [`CHATGPT-STYLE-REDESIGN.md`](CHATGPT-STYLE-REDESIGN.md):
      bajar de ~11 destinos de nav a ~3+"Más", panel de agente calmado (chips + paso N/M + narración),
      selección gris, retirar teal como 2º acento, aplanar elevación/aurora, columna de lectura centrada.
      Fase 1 sin riesgo de marca; 3 decisiones de marca pendientes (teal, eyebrows mono, bubble usuario).
- [ ] Sandboxing Docker opcional por loop — *si hay demanda*
- [ ] Sesiones remotas SSH — *si hay demanda*

## Fuentes

- [Traycer](https://github.com/traycerai/traycer) · [Traycer Docs](https://docs.traycer.ai/) ·
  [Epic Mode](https://traycer.ai/blog/epic-mode-turning-intent-to-code)
- [Parallel Code](https://github.com/johannesjo/parallel-code) · [parallelcode.app](https://parallelcode.app/)
- [maestro-orchestrate](https://github.com/josstei/maestro-orchestrate)
- [metaswarm](https://github.com/dsifry/metaswarm)
- [Clave](https://github.com/codika-io/clave)
- [ccmanager](https://github.com/kbwo/ccmanager)
- [agent-orchestrator](https://github.com/AgentWrapper/agent-orchestrator) ·
  [architecture.md](https://raw.githubusercontent.com/AgentWrapper/agent-orchestrator/main/docs/architecture.md)
- [LittleLLM](https://github.com/NickPittas/littlellm)
- [awesome-agent-orchestrators](https://github.com/andyrewlee/awesome-agent-orchestrators)
- [awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents)
