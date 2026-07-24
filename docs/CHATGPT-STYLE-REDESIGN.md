# Coral → ChatGPT-calm — plan de rediseño

**Fecha:** 2026-07-24 · **Origen:** panel de 2 diseñadores senior (IA/navegación + sistema visual)
sobre capturas de la app ChatGPT vs. el código real de Coral. El usuario encuentra ChatGPT más
**limpio y comprensible** y quiere orientar Coral hacia esa calma/legibilidad **sin perder su
identidad** (acento coral, núcleo multi-agente).

## Diagnóstico en una frase

El problema de Coral **no es falta de pulido — es exceso de ruido estructural y cromático**. Corre a la
vez 3-4 sistemas "premium" (escalera de elevación, aurora, doble acento coral+teal, chips de color por
semántica, hero de 40pt) y expone **~11 destinos** en el rail de iconos. ChatGPT se siente calmado
porque corre **uno de cada** y esconde casi todo hasta que hace falta. El arreglo es sobre todo
**restar y diferir**, no rediseñar.

---

## Los 3 grandes movimientos (ambos agentes coinciden)

1. **Navegación: de ~11 destinos a ~3 + "Más".** Primarios: **Chats** (+ Nuevo chat). Secundarios (un
   nivel dentro, tras un disclosure/"Más"): Team, Code, Connections. Avanzados (tras "Más" o en
   Settings): Loops, Skills, Memory, Arena, Usage, Advisor. Fundir la lista de chats **dentro** del
   rail (estilo ChatGPT) elimina una columna entera + su divisor. (`NavRail.swift`, `ContentView.swift`,
   `AppModel.NavSection`.)

2. **Panel de actividad del agente: de muro de tarjetas a tira calmada.** Estado en reposo objetivo:
   **chips por agente** (punto + nombre + palabra de estado) → **pill "Paso N/M"** → **una línea gris
   de narración** ("Outlining… · 2m14s") → **líneas de actividad** monocromas. Todo lo demás (diagrama
   de topología, gasto por modelo, historial) a un disclosure de profundidad. (`AgentActivityPanel.swift`.)

3. **Disciplina de color: de doble acento a monocromo + un acento.** La **selección pasa a gris suave**
   (no coral, sin borde ni espina) y el **teal se retira** de "live/agentes" (pasa a ser el acento coral
   o un punto neutro pulsante). Esto solo quita ~40% de la superficie de color. (`Theme.swift`.)

---

## Plan por fases (cada fase pasa el gate `xcodebuild test`)

### Fase 1 — barato, alto impacto, sin riesgo de marca (reposo más calmado)
- **Selección → gris suave.** `Theme.selectionFill` a neutro, `selectionBorder` → `.clear`, quitar la
  espina coral en `CoralRow` y `SelectedRow`. *(El cambio más definitorio y repetido.)*
- **Rail: quitar la `usageCard` persistente** (`NavRail.swift`) y fundir el grupo "workspace" (Code,
  Team) en el mismo disclosure que "advanced" → rail en primer arranque = Nuevo chat · Chats · Más ·
  Settings. Un solo header ("Chats").
- **Panel de actividad:** `showDiagram` y `showTeam` por defecto **false**; quitar el **segundo** punto
  parpadeante (`liveWorkingLine`); colapsar la lista de todos a un pill "Paso N/M".
- **Aplanar elevación:** quitar `.elevation` de `PanelCard`/`card()`/`equalCard()`; separar por hairline
  o solo whitespace (guardar e3/e4 solo para popovers/sheets).
- **Centrar la columna de lectura** del chat (~740, centrada, no pegada a la izquierda).

### Fase 2 — los movimientos firma (chips + una narración; sin cirugía de shell)
- **Team → fila de chips** (punto de estado + nombre + estado), tap abre el detalle existente; **borrar
  las barras de progreso por agente**.
- **Una sola narración gris** "haciendo ahora" (consolidar goalText + subtítulo del orquestador +
  liveWorkingLine).
- **Demote del bloque tokens/coste/plan/por-modelo** a un disclosure "Uso"; dejar solo un caption de una
  línea. (ChatGPT no muestra tokens durante un run.)
- **Filas de chat estilo ChatGPT:** título de una línea truncado, sin chrome de badges, wash gris suave
  al seleccionar. **Neutralizar la aurora** (fondo plano `appBg`, o solo la luz superior tenue; borrar
  los dos blooms) → quita el último wash global coral+teal.

### Fase 3 — más profundo (estructural, con revisión visual)
- **El rail posee los chats:** fundir `SidebarView` en el rail; rehacer el `if/else` de 11 ramas de
  `ContentView` (Chats/Team/Code como estados de ventana; Skills/Memory/Arena/Usage/Connections/Loops
  como superficies utilitarias o sheets tras "Más"). Remodelar `NavSection` a un set primario pequeño +
  un caso `utility(...)`.
- **De-slab del bubble de usuario:** quitar el glow/gradiente → coral plano (o gris). *(Decisión de
  marca — ver abajo.)*
- **Consistencia de iconos** (outline, no `.fill`, salvo estado real); aplanar `IconBadge`.

---

## Decisiones de marca (necesitan tu OK antes de Fase 2/3)

Estas tres son las **huellas** más distintivas de Coral; ir "ChatGPT-calm" del todo implica tocarlas:

1. **Retirar el teal como color de "sistema/agentes".** Es el mayor recorte de color, pero el propio
   `Theme.swift` define teal como identidad. → *¿Teal a acento coral / punto neutro, o conservarlo solo
   en el diagrama de topología?*
2. **Eyebrows monospace en mayúsculas → sans plano gris.** El mono es muy "developer tool"; ChatGPT usa
   gris plano. → *¿Cambiar los eyebrows a sans, guardando mono solo para código/IDs/modelos?*
3. **El bubble coral del usuario.** Es tu firma; la versión máxima-calma lo haría gris. Recomendación
   intermedia: **coral plano sin glow ni gradiente** (firma sí, brillo no).

## Qué NO tocar
- El **hero de 40pt + el punto coral** del saludo: on-brand y disciplinado (2-4 sitios). **Se queda.**
- El **acento coral** en el botón de enviar y el CTA primario: es exactamente el "un acento usado una
  vez" de ChatGPT. Se queda.
- El **núcleo multi-agente** y todas las features: esto es resta de *chrome*, no de capacidad.
- Los ficheros vetados del motor de loops (solo se mueve su *entrada* de navegación, no su código).

## Orden recomendado
Empezar por **Fase 1** entera (sin riesgo de marca, máximo impacto de calma), validar en claro+oscuro,
y decidir las 3 preguntas de marca antes de Fase 2.

---

## Progreso (2026-07-24)

**Decisiones de marca — el usuario aprobó las 3 recomendadas:** teal retirado · eyebrows sans · bubble
coral plano.

**Hecho (commits en `main`, tests verdes, pendiente validación visual claro/oscuro):**
- [x] Selección → gris (sin coral, sin borde, sin espina); hover neutro.
- [x] `card()`/`equalCard()` aplanadas (hairline, sin sombra de elevación).
- [x] **Teal retirado**: tokens `teal*` alias del acento coral (un solo acento en toda la app; team
      spectrum solo en el diagrama).
- [x] **Eyebrows sans** (`sfFieldLabel`); mono solo en `sfMono`/`sfCode`.
- [x] **Bubble usuario coral plano** (sin glow ni gradiente).
- [x] Columna de lectura del chat **centrada** (~760).
- [x] Aurora reducida a un bloom coral tenue (fuera el teal + un wash).
- [x] Panel de actividad: diagrama opt-in (`showDiagram` false); fuera el 2º punto parpadeante.

**Pendiente (Fase 1 cola + Fase 2/3 — más intrusivo, validar visualmente primero):**
- [ ] Rail: quitar la `usageCard` persistente + fundir grupos (≈11 destinos → ≈3 + "Más").
- [ ] Panel de actividad: **fila de chips por agente** + pill "Paso N/M" + una narración gris (sustituir
      las filas con barras de progreso por agente).
- [ ] Fundir la lista de chats en el rail; simplificar el `if/else` de 11 ramas de `ContentView`.
- [ ] Consistencia de iconos (outline); densidad (subir un paso el ritmo de `CoralRow`).
