# Análisis competitivo — Coral vs. orquestadores de agentes de código

**Fecha:** 2026-07-23
**Método:** investigación con 5 agentes en paralelo (WebSearch + WebFetch) sobre repos, sitios y docs
públicos de cada competidor. Todas las afirmaciones citan fuente; donde la fuente devolvió 403 o el
dato no estaba documentado públicamente se marca **(no confirmado)**.
**Audiencia:** producto/roadmap interno.

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
2. Coral vende "mezcla de proveedores por rol" como diferenciador pero no tiene **procedencia por
   línea** (qué modelo escribió qué) — nadie más lo tiene resuelto tampoco: oportunidad de ser
   primeros, no de ponerse al día. **→ Resuelto en PR #27** a nivel de línea en la ruta nativa
   (cross-proveedor por línea sigue pendiente).
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
| Procedencia por línea (qué modelo/rol escribió qué) | ✅ (por línea en el diff, ruta nativa Claude; cross-proveedor pendiente) | ❌ | ❌ | ❌ | ❌ | ❌ |
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

**Nota sobre "procedencia por línea":** Coral pasa a ser el único de la categoría con atribución por
línea en el diff, pero con un matiz honesto: es **a nivel de línea en la ruta nativa Claude** (donde
los subagentes editan ficheros de verdad). La atribución **cross-proveedor** por línea sigue
pendiente — los workers cross-proveedor devuelven texto, no editan ficheros — y necesita el paso
arquitectónico de que cada worker edite en un worktree aislado que podamos diffear. El modelo de
datos (`EditProvenance`, `LineAttributor`) ya está listo para ese salto.

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
     en los tres niveles (en Code puntúa los diffs). *Resultado:* Coral **supera** a Parallel Code —
     su Arena es solo de modelos, sin juez ni aislamiento. *Siguiente paso:* equipos con orquestador
     **no-Claude** editando (necesita el paso cross-proveedor).
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
      compite ahora *proveedores sueltos* O *equipos enteros*: un equipo se materializa en el worktree
      (`.claude/agents` + `CLAUDE.md`, commit baseline) y corre nativo con `claude` (orquestador →
      subagentes editando). El diff comparado excluye el andamiaje. `CodeContestant` unifica ambos.
      Verificado con test de git real. *Restante:* equipos con orquestador **no-Claude** editando —
      necesita el paso cross-proveedor (↓).
- [ ] **Procedencia por línea cross-proveedor** — workers editando en worktrees aislados que podamos
      diffear. **Ya desbloqueado en parte:** `CodeArenaEngine` demuestra la ejecución write-capable
      aislada por proveedor; falta atribuir líneas del diff al proveedor (modelo `EditProvenance` listo).
- [ ] **P2 · Estimación de coste previa** en las arenas de equipos/código (reutiliza `CostEstimationHooks`).
- [ ] Sandboxing Docker opcional por loop
- [ ] Sesiones remotas SSH — solo si hay señal de demanda

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
