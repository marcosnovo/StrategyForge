# Coral — revisión de diseño (panel de 4 especialistas)

Art director · diseñador de chat-apps · especialista macOS nativo · especialista UX "sensación
de fácil". Todos anclados en el código real (Theme.swift + vistas). Convergieron en una tesis.

## Tesis única
**Coral tiene materiales premium pero identidad y superficie sobrecargadas.** El cambio de
carácter no es *añadir* sino *restar*: pasar de "busy/impresionante" a "calm/premium". Tres
excesos concretos: (1) **5 motivos-héroe** compitiendo (marca-rama, esfera, campo de puntos,
aurora, glass); (2) **un banner por feature** (~10 tratamientos en 5 tintes alrededor del
chat); (3) **coral Y teal ambos como color de acción** → la identidad se diluye.

## North star
> **Coral es una chispa coral de tu intención moviéndose por un arrecife calmado y glassy —
> el teal solo significa "el equipo está vivo", el poder multi-agente es un chip discreto que
> tú alcanzas (nunca un banner que tienes que leer), y se conduce entero desde ⌘K y el teclado
> como una app de Mac de verdad.**

## Reglas de oro (las 3 que lo cambian todo)
1. **Un solo acento.** Coral = tú/intención/acción. **Teal = SOLO estado "algo está pasando"**
   (running, agente activo, gasto en vivo), nunca un color de acción. Repuntar cada acción
   secundaria en teal (connect-folder, chips de descarga, chip de equipo, "ver uso") a neutro
   con coral-en-hover.
2. **Color = estado, no sugerencia.** Un `CoachChip` neutro único (hairline + `cardBg`) para
   TODAS las sugerencias (loop/repo/2ª-opinión/cambiar-equipo/token-saver); solo **errores** y
   **permiso bloqueado** llevan fondo tintado. Nunca más de UNA sugerencia a la vez (`activeCoach`).
3. **Movimiento = algo está pasando AHORA.** Las esferas en reposo no respiran para siempre;
   reservar breathing/pulse para estado vivo. Aurora a 2 blooms (coral + teal), no 4.

---

## Plan por olas (impacto ÷ esfuerzo ÷ riesgo)

> **Estado (2026-07-21):** ✅ Ola A completa · ✅ **Ola B completa** · ✅ **Ola C completa**
> (C1 CTA onboarding, C2 bloqueador Claude, C3 des-jergon, C4 beat de finalización, C5 undo
> team-swap, C6 saludo dup) · ✅ **D1 ⌘K command palette** · ✅ **D2 menú File real**
> (duplicar/eliminar/importar/exportar + Stop ⌘.) · ⏳ **Pendiente, requiere DECISIÓN + revisión
> visual del usuario:** **D3** (`List(selection:)` con teclado — riesgo medio, prototipar look
> de selección), **D4** (header nativo en `.toolbar` — restyle), **D5** (material del rail —
> ⚠️ *contradice una decisión intencionada*: el rail usa hoy `translucentColumn()` a propósito
> para leerse como la misma superficie que la lista; D5 pide diferenciarlas — es una llamada
> subjetiva del usuario). · ✅ **A6 micro-tipografía** (hallazgo: `scaledFont` suela a 10pt,
> así que 7/8/8.5/9 renderizan idénticos; fundido el 8.5, documentada la regla, 9 = micro
> sancionada; normalizar los 7/8 restantes es puro aseo sin cambio visual, opcional).
> **⏳ Solo quedan D3/D4/D5** (arriba). Fuera de la review: **UX de clonado** — la fila pulsada
> muestra "Clonando…" en vez de congelarse. Todo ✅ está en `main`, compilando y 330 tests verdes.

### Ola A — wins globales de token/visual (una tarde, riesgo bajo, alta calidad percibida)
- A1. **Display type más grande y ceñido** (`Theme.sfDisplay` → `.largeTitle`/bold, tracking −0.5); héroes ~28–34pt.
- A2. **Aurora a 2 blooms** (coral top-trailing + teal bottom-leading); quitar peach/mint. `ContentView`.
- A3. **De-glass del composer** — quitar la capa `.glassPanel`, dejar `cardBg` sólido + hairline + focus ring. Más nítido y rápido. `ChatView`.
- A4. **Movimiento solo en estado vivo** — quitar `breathingGlow` de la marca del rail y héroes en reposo. `NavRail`, `ChatView`.
- A5. **Fallback de Reduce Transparency** en `translucentColumn`/`glassPanel`/aurora (hueco de accesibilidad real). `Theme`, `ContentView`.
- A6. **Consolidar la micro-tipografía** — de 8/8.5/9pt a dos tamaños (11 y 9); mono=labels, rounded=números en vivo. `Theme`, `AgentActivityPanel`.

### Ola B — el cambio de carácter (calm > busy) (medio esfuerzo)
- B1. **Teal → solo-estado**; acciones secundarias a neutro+coral-hover. `ChatView`, `NavRail`.
- B2. **Unificar los ~10 chips/strips en un `CoachChip` + slot único `activeCoach`**; color solo para error/bloqueado; "Equipo de N"/"2ª opinión" pasan al mismo slot o a icon-tertiary. `ChatView`.
- B3. **Panel de actividad: ~9 tarjetas → 3** (secciones dentro de una tarjeta con divisores). `AgentActivityPanel`.
- B4. **Pulir mensajes**: sombra de la burbuja de usuario a casi-plana + ancho máx ~560; copy/regenerate **icon-only, hover-reveal**, una sola acción con color; **un avatar por turno** (no por mensaje). `ChatView`.
- B5. **Bloque de código premium**: etiqueta de lenguaje + copy en hover + superficie algo más fuerte. `MarkdownView`.

### Ola C — voz y "sensación de fácil" (casi todo copy, una tarde)
- C1. **Onboarding: una sola CTA primaria** ("Empezar mi primer chat"); "Ver plantillas" a link; quitar la 3ª puerta. `OnboardingView`.
- C2. **Promover el bloqueador de "conecta Claude"** (coral, `sfCardTitle`, botón `.moon`), no `sfCaption2`+link. `OnboardingView`.
- C3. **Unificar el vocabulario de autonomía** (una etiqueta por estado: "Automático" vs "Full autonomy" ahora chocan). **Des-jergonizar**: orchestrator → "agente líder"; quitar "cross-provider" del copy; suavizar el confirm de "permitir siempre". `Localization`.
- C4. **Beat de finalización en el chat activo** — un settle coral + "Hecho · N ficheros · $X" al terminar el turno (hoy la respuesta acaba en silencio). `ChatView`.
- C5. **"…" del composer con label la 1ª vez** ("Opciones"); pills de sugerencia que **señalen que rellenan** (no envían); **Undo al cambiar de equipo**. `ChatView`.
- C6. **Matar el saludo duplicado** ("Welcome to Coral" en onboarding y en empty) + el 2º subtítulo redundante del empty in-chat. `Localization`, `ChatView`.

### Ola D — nativo macOS (mayor, más riesgo, deliberado)
- D1. **Command palette ⌘K / quick-switcher de chats** — el #1 para una app de cambiar entre agentes; riesgo estructural bajo. Nuevo `Views/CommandPalette.swift` + shortcut en `StrategyForgeApp`.
- D2. **`.focusedValue` + menú File/Edit completo** (Send/Stop/Rename/Delete/Duplicate/Export/Import). `StrategyForgeApp`, `AppModel`.
- D3. **Lista de chats como `List(selection:)`** con navegación por teclado (↑/↓, type-select, ⌫). Riesgo medio (prototipar primero el look de selección). `SidebarView`.
- D4. **Header en `.toolbar` nativo** (quita el hack de `titlebarInset`, gana traffic-lights/full-screen correctos). Riesgo medio (restyle). `ChatView`.
- D5. **Diferenciar el rail de la lista** materialmente (rail = `.sidebar`; lista = contenido) para que las dos columnas izquierdas no se lean como una sola. `NavRail`/`Theme`.

## Lo que NO se toca (ya es craft-tier)
Reduce Motion (impecable), la asimetría burbuja-usuario/asistente-plano, el `SelectedRow`, la
matemática de contraste AA de los corales, la esfera como identidad del asistente (una, quieta),
`zoomWindowOnDoubleClick`, el `ResizableDivider`, el sheen del `.moon`, el shimmer de streaming.
