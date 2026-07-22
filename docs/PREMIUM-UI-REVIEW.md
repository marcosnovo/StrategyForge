# Coral — Revisión "premium" (panel de 4 diseñadores senior) + plan

Inspirada en una referencia premium (una app de viajes "Booked" con glass flotando sobre piedras
cálidas). Panel: **dirección de arte**, **materiales/profundidad (Liquid Glass)**, **tipografía/
jerarquía espacial**, **color/calidez**. Todos anclados en el código real. Esto es síntesis + plan;
no implementa nada aún.

## Tesis unificada

Lo premium de la referencia **no es decoración — es confianza + fisicidad + calidez.** Coral ya tiene
la *contención* y el *color correcto* (olas de diseño y color previas), pero le falta: **profundidad
física** (las tarjetas se leen planas, no como objetos apoyados en una superficie), **un momento hero
tipográfico confiado** por pantalla (el display es tímido, ~26pt, igual que un título de sección),
**neutros cálidos** (el reef oscuro es frío-azulado y el claro es blanco plano) y **aire generoso**
(la escala de espaciado se corta en 24pt). La forma de subir a premium **sin** parecer una app de
viajes: dar profundidad real + una tipografía hero grande + neutros greige cálidos + un gesto de
acento coral — manteniendo coral=héroe, teal=estado, reef dark-first y la CoralSphere como mascota.

## Hallazgos de consenso (deduplicados)

1. 🔴 **Sin profundidad física.** La superficie más usada (`PanelCard`, `AgentActivityPanel.swift:993`)
   **no tiene sombra** — relleno plano + hairline. Las sombras existentes son un único token plano
   `black 0.12` que en modo oscuro (el default) **casi no se ve** sobre reef-ink. No hay escalera de
   elevación ni fuente de luz. *El mayor salto premium disponible.*
2. 🔴 **Neutros fríos y planos.** Reef oscuro azulado (R−B −9 a −20), claro = blanco puro (`cardBg
   #FFFFFF`). `cardBg == columnBg` en oscuro (separación cero). El "greige cálido" es *la* señal
   premium de la referencia y Coral no la tiene.
3. 🟠 **Display tipográfico tímido.** `sfDisplay` ≈26pt hace doble trabajo (heroes Y títulos de
   sección). El saludo que debería ser el "Booked" es del tamaño de un header de ajustes. No hay
   tier hero separado.
4. 🟠 **Aire insuficiente.** `Space` se corta en `xl:24`. Los heroes nunca respiran a escala
   referencia (40/64pt). (Los paneles densos deben quedarse tight — el contraste es la clave.)
5. 🟠 **Glass funcionalmente monocromo.** `glassPanel` es `.glassEffect(.regular)` pelado, sin tint
   ni sombra → un panel de glass y una tarjeta plana se ven igual. Solo 2 de ~6 sitios usan tint.
   Cero `GlassEffectContainer` (perf + cohesión desaprovechadas).
6. 🟡 **Fondo (aurora) es un wash plano** (5-6% bloom) — no hay "superficie cálida con dirección de
   luz" sobre la que los objetos proyecten sombra de contacto.
7. 🟡 Radios sin sistema (20/16/18 casi iguales → el anidamiento no lee profundidad); tracking de
   eyebrows disperso (0.3–0.8); labels sub-10pt (suelo a 10) = jerarquía falsa.

## Tensión resuelta
La referencia usa **un CTA oscuro** de alto contraste. **No encaja en Coral** (el color agent lo
argumenta): el acento de Coral **es** el CTA héroe (coral brillante). Un segundo primario oscuro
crearía dos primarios en competencia y rompería la contención. **Coral se queda como el ancla
primaria**; solo hay que plantarla de forma consistente donde falta (TeamBrowse). La calidez viene
de los **neutros** alrededor del coral, no de más coral.

---

> **Estado (2026-07-22):** ✅ **Ola 1** — P1 elevación (`elevation(.e1…e4)`), **P2 CORREGIDO**:
> el greige cálido se sentía sucio/off-identity → revertido a los neutros **reef fríos** de Coral
> conservando la *escalera de profundidad* (card≠column) + el ladder de sombras; P3 `sfHero` 40/−0.8
> en los 2 saludos, P4 `Space.xxl/xxxl`, P5 punto coral. ✅ **Ola 2 completa** — glass + command palette
> con profundidad; **tint del glass** e **iluminación del reef** iteradas *a la Coral* (frío/reef, pura
> luminancia, **sin** calidez). ✅ **Ola 3 (firma)** — CoralSphere con **sombra de contacto** (apoyada
> en el reef). ⏸️ **No hechos (bajo valor/contestado/churn):** ancla `.moon` en TeamBrowse (es un
> browser, CTA forzado = ruido), delta de radios (materiales dijo que ya están bien), higiene de
> eyebrows (~30 sitios, impacto visual casi nulo). Retomables si los pides tras la revisión visual.
> **Lección:** la calidez greige NO pega con Coral; el premium viene de **profundidad + tipo hero +
> el acento coral**, no de calentar el tono. **CI de tests pausado** para no quemar Actions.

## Plan por olas (impacto ÷ esfuerzo ÷ riesgo)

> Casi todo es **token-only, bajo riesgo** — pero profundidad/calidez/tipo hero **necesitan
> verificación visual en claro Y oscuro** (RenderPreview no arranca con el AppModel; gate = tests +
> tu ojo). Los paneles densos NO se tocan; el premium es heroes airosos *contra* paneles densos.

### Ola 1 — carácter premium (token-only, un archivo `Theme.swift` casi todo)
- **P1. Escalera de elevación** (modifier `elevation(.e1…e4)`, ambient+contact, colorScheme-aware,
  2–3× más fuerte en oscuro, con rim de luz superior). Aplicar `.e1` a `PanelCard` y `.e2` a `card()`.
  *El mayor salto.* [#1]
- **P2. Neutros greige cálidos + escalera real** (hex exactos del color agent, AA-verificados; separa
  `cardBg`≠`columnBg` en oscuro; claro deja de ser blanco plano). [#2]
- **P3. `sfHero`** (40pt, tracking −0.8) distinto del `sfDisplay` de sección; a los 2 saludos +
  onboarding. Split hero≠sección. [#3]
- **P4. `Space.xxl 40` / `xxxl 64`** solo para el momento hero por pantalla. [#4]
- **P5. Punto de acento coral** en el saludo (`Text(saludo) + Text(".").foregroundStyle(coral)`) — el
  gesto-firma de la referencia, on-brand, riesgo casi nulo. [#3]

### Ola 2 — profundidad de materiales (necesita ojo)
- **P6. Warm-tint `glassPanel`** (`.regular.tint(cardBg·0.5)`) + sombra e1 → glass cálido flotante,
  no frost gris. **P7. `GlassEffectContainer`** para clusters de chips (activity badges, pills del
  composer). [#5]
- **P8. Reef con dirección de luz** — gradiente de luminancia top-down muy sutil bajo los blooms, para
  que el glass "descanse" en una superficie. ⚠️ el más arriesgado para la *calma*, tunear en vivo. [#6]

### Ola 3 — momento hero + anclas (necesita ojo)
- **P9. CoralSphere "apoyada en el reef"** — sombra de contacto elíptica bajo la esfera en los estados
  vacíos + `sfHero` + un `.moon`. El "objeto físico" de Coral.
- **P10. Un `.moon` de ancla** en TeamBrowse y landings sin primario.
- **P11. Delta de radios decisivo** (exterior 24 / interior 14).

### Ola 4 — higiene tipográfica
- **P12. `sfEyebrow`** canónico (mono, un solo tracking) migrando `FieldLabel` + los ~30 sitios
  dispersos. **P13.** colapsar `scaledFont(7/8)` a `9`.

## Lo que NO se toca (ya es premium)
Composer de-glassed, asimetría burbuja-usuario/asistente, sheen+glow del `.moon`, one-coach-slot,
teal=estado, fallbacks de Reduce Transparency/Motion, aurora de 2 blooms (contención), densidad de
los paneles de trabajo. Y **no** añadir un segundo CTA oscuro (rompería el "un acento manda").
