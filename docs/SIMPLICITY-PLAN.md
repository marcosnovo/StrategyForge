# Coral — "simple como ChatGPT/Kimi, potente como Coral"

Revisión multi-agente (2026-07-21): auditoría anclada en el código + principios de
simplicidad de Kimi/ChatGPT + estrategia de layering. Los tres convergieron en una tesis.

## Tesis
**Coral YA es "escribe y listo" por dentro** — un chat nuevo nace con "equipo automático"
(`AppModel.addConfiguration` → `strategyIsAuto`), y el Advisor elige el equipo desde el
primer mensaje (`autoRecommendStrategyIfNeeded`). Ninguna decisión (proveedor, carpeta,
modelo, equipo) bloquea el primer mensaje; el único gate real (CLI de Claude instalado)
está diferido al envío. **El problema es de PRESENTACIÓN, no de capacidad:** la app
*lidera con "diseña un equipo"*, tiene 9 secciones de nav, 3 superficies redundantes para
"tarea→estrategia", y un composer cargado. Kimi = **una caja dominante** ("Ask anything,
or task an agent…") y todo lo demás oculto hasta que hace falta.

## Modelo de una sola caja (mental model)
> **"Escribe para pensar · Escala a un equipo con un toque · Programa para que corra sin ti."**

- **Por defecto = chat normal.** Escribes, respondes. Cero setup. 80% del uso, se siente como ChatGPT.
- **Un toque más = equipo.** Cualquier mensaje tiene "Ejecutar como equipo" (el Advisor pre-asigna roles, muestra preview de una línea: "Claude planifica → Codex construye → Claude revisa" + "Go"). El editor completo es un "personalizar" al fondo.
- **Un toque más = proveedores.** El badge de proveedor en el composer/mensajes → "Segunda opinión de Codex", "Comparar entre proveedores".
- **Un toque más = loop.** Un mensaje con forma de objetivo/recurrencia → "¿Repetir/programar?" con control inline (frecuencia + condición de parada). Full `LoopPlan` al fondo.
- **El fondo de cada drill-down** = el poder actual de Coral, intacto. Se **degrada de puerta a detalle**, no se elimina.

## Los 3 tiers
- **Tier 0 — Solo chat:** una caja + hilo. Advisor invisible detrás. Provider = el CLI ya logueado. Objetivo: **tiempo al primer valor con 0 clics de config.**
- **Tier 1 — Asistencia contextual:** ofertas *ancladas a lo que ya está en pantalla* (nunca nav): chip "Respondido por un equipo de 3 agentes ▸" (expandible), sello de verificador, "¿Ejecutar en loop?", "Trabajar en el repo", atribución cross-provider. **Se gana su sitio referenciando un artefacto concreto.**
- **Tier 2 — Control total:** abierto a propósito (⌘K / "Personalizar" / expandir un chip): editor de equipo, mixing por rol, LoopPlan completo, Evals, memoria/skills, Code mode profundo, Usage/Settings.

## El default clave (mata la decisión "¿qué equipo/proveedor/modelo?")
El usuario **nunca elige**: el Advisor decide **por-mensaje** desde la primera tecla, **sesgado a UN solo agente para prompts simples** (así una pregunta trivial es tan rápida/barata como ChatGPT y no quema el plan del usuario), y solo monta equipo cuando la tarea lo pide. El equipo se **revela después** como chip expandible, no se pregunta antes.

## Estado (implementado)
- **Fase 1 ✅** — presentación: 1 CTA, onboarding reencuadrado, rail decluttered (Advanced colapsado, sin Advisor), composer limpio hasta el 1er mensaje, panel de actividad no auto-abre en el 1er run, picker beginner.
- **Fase 2 ✅** — reveals contextuales: chip "Equipo de N ▸", "¿Ejecutar en un loop?", "Adjunta una carpeta", "2ª opinión · X" (cross-provider, aislado del run path).
- **Fase 3 ✅ (realizada por los reveals + lo existente)** — ladder de escalación: cambiar/mejorar equipo (chip `followupSuggestion`, reversible), escalar a loop (chip → editor = preview+confirm), segunda opinión (iniciada por el usuario = consentida). Riesgos 1/2/3 mitigados (atribución visible, Advisor ya sesga + switch-down, todo inspeccionable/overridable).

## Plan por fases (impacto simplicidad ÷ riesgo al core)

### Fase 1 — Presentación (aditivo, seguro, sin tocar capacidades)
1. **Empty-editor: 3 CTAs → 1** ("Empezar" entra directo al chat con composer enfocado; "Set up for me" como link secundario). `ContentView.swift`.
2. **Reencuadrar onboarding paso 1**: de "Diseña tu equipo" → "Pregunta lo que sea / Coral elige los agentes / puedes rediseñar cuando quieras". `Localization.swift` (`onboard.step*`).
3. **Composer footer (mode/effort/context) oculto tras "…"** hasta ≥1 mensaje enviado o al abrirlo. `ChatView.swift`.
4. **No auto-abrir el panel de actividad en el primer run** (solo tras ver ≥1 run completado). `ChatView.swift`.
5. **Cap de tiras-coach a 1** y suprimir en el primer mensaje (mostrar como mucho el advisor card). `ChatView.swift`.
6. **Nav: agrupar Loops/Skills/Usage bajo "Avanzado" (colapsado)** y quitar Advisor del rail (redundante con el inline). Rail 9→~5. `NavRail.swift` + routing.
7. **Picker de estrategias por defecto = las 4 beginner** con "ver todas" en disclosure. `StrategyPickerColumn.swift`.

### Fase 2 — Reveals contextuales (cambio de comportamiento, valor alto)
- Chip **"Respondido por un equipo de N ▸"** en cada resultado con equipo (marketing del diferenciador, siempre glanceable).
- **"¿Ejecutar en loop?"** cuando el Advisor detecta forma de objetivo/recurrencia.
- **"Trabajar en el repo"** cuando el hilo menciona repo/PR/diff.
- **"Segunda opinión / Comparar proveedores"** en el badge de proveedor y en respuestas de baja confianza.
- Loops **reportan de vuelta al hilo de origen** como entradas con timestamp.

### Fase 3 — Escalación como ladder
- Chat → "hazlo equipo" → "hazlo loop", cada peldaño **un toque, reversible, con preview+confirm antes de gastar/actuar**.

## Lo que NO se simplifica (el core)
Auto-team-desde-prompt · mixing cross-provider · diseñador visual de equipo · loops
autónomos + verificador read-only · Code mode/PR · modelo de permisos graduado. Se
**degradan de gate a detalle**, nunca se quitan.

## Riesgos y mitigación
1. **Ocultar tanto el diferenciador que nadie lo descubra** → el *valor* visible aunque el
   *mecanismo* esté oculto: el chip "equipo de N" y el sello salen en CADA respuesta; un
   momento único "por qué esto es distinto" disparado por un evento real (primera vez que
   el cross-provider mejora una respuesta), no un tour.
2. **Auto-montar un equipo pesado/caro para algo trivial** → sesgar a single-agent; señal
   de coste/alcance antes de correr algo no-trivial ("usará un equipo de 3 — correr / mantener simple").
3. **Magia opaca erosiona el control del power user** → toda auto-decisión **inspeccionable
   y overridable de un clic** en el punto de reveal; "usar siempre este equipo para chats así".
   *Auto por defecto, nunca auto-only.*

## Anti-patrones a evitar
- Black-box de los agentes (colapsable ≠ invisible).
- Zero-config que signifique zero-consent en acciones caras/irreversibles.
- Aplanar en pestañas por *modo* (Chat/Teams/Loops) — eso ES mode-first disfrazado. Pestañas
  para *objetos* (hilos, índice de loops), nunca para *modos de operación*.
