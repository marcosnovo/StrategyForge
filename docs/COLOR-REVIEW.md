# Coral — Revisión de color & UI (panel de 4 especialistas)

Panel: **arquitecto de sistema de color**, **especialista macOS/Liquid Glass**,
**auditor de accesibilidad/contraste**, **director de arte/marca**. Todos anclados en el
código real (citan `archivo:línea`). Este documento es la **síntesis + plan**. No implementa
nada todavía.

> **Estado (2026-07-22):** ✅ **Fase 1** (correcciones objetivas de contraste + error fuera del
> tono coral + `tealText`/`warningText` + aurora base = `appBg`) en `main`, 330 verdes. ✅
> **Titular de Fase 2/3 — coral hero brillante** (burbuja/CTA/send desde #FF6B54 con scrim en el
> glifo + glow coral; "answered by team" → neutro) en `main`. Descartado P1.3 (loader teal =
> demos del ParticleLab, no el loader real). ✅ **Teal-diet data-viz** (spend bar + anillos/barras
> de uso del rail → coral; teal reservado a vivo). ✅ **Modo claro lleva la marca** (accentSoft
> 0.12→0.18, selectionFill 0.16→0.22). ✅ **Uso siempre visible** (el rail
> tenía el card de uso condicional a datos → añadido punto de entrada permanente al fondo que
> progresa a las métricas en vivo). ✅ **`glassPanel(material:)` muerto borrado**. ⏳ **Pendiente —
> todo subjetivo/visual, requiere tu ojo y decisión:** delegaciones en reposo → neutro (pierde la
> señal de "handoff", tu llamada), coral-por-sustracción (demote iconos-no-acción a neutro; barrido
> grande), 1.4.1 (glifo en dot de atención/update), texto neutro → `.primary/.secondary/.tertiary`
> (⚠️ *choca con los hex de contraste afinados en Fase 1*; barrido enorme), espectro de equipo
> gobernado y desaturado (acertar 5 tonos nuevos — mejor contigo mirando).

## Tesis unificada

El coral (#FF6B54) es un gran color de marca al que se le pide hacer demasiados trabajos, a
demasiadas opacidades, mientras un segundo palette (colores de rol/proveedor) y el teal le roban
el protagonismo. **La forma de que el naranja "cante" no es más naranja — es menos, más fuerte y
con significado**: un ramp coral real, una regla de opacidades, sacar el rojo de error del tono
del coral, devolver el brillo a los momentos hero, y poner el teal a dieta ("teal = vivo, y solo
vivo"). Modo oscuro está bien afinado; **el modo claro es donde el diseño se rompe** (contraste).

## La decisión de diseño clave (hay que elegir)

Hay una tensión entre dos agentes que define el enfoque:

- **Accesibilidad** pide oscurecer tokens para pasar AA (accent, danger, secundarios…).
- **Dirección de arte** señala que los gradientes hero **ya** están oscurecidos a rojo-ladrillo
  (#D53C24→#C8321C) para pasar "blanco sobre coral", así que **el naranja vívido de la marca casi
  nunca aparece en sus momentos hero** (burbuja de usuario, CTA, avatar, send).

**Resolución propuesta:** separar *color de texto/icono* de *relleno hero*.
- Texto/icono coral → se oscurece a un `accent` que pasa AA (es chrome, no marca).
- Rellenos hero (burbuja, `.moon`, avatar) → corren desde **#FF6B54 brillante** hacia un fondo
  controlado, y el contraste del texto blanco se garantiza en el **glifo** (texto `.bold` o un
  scrim sutil detrás del texto), **no** browneando todo el relleno. Así la burbuja vuelve a ser
  "el coral del founder", no óxido.

→ **Esto es lo único que necesita tu OK explícito de gusto.** El resto es corrección objetiva.

---

## Hallazgos de consenso (deduplicados, por severidad)

### 🔴 Críticos (rompen significado o accesibilidad)

1. **`danger` #F03E27 ≈ el tono del coral.** Error y marca son el mismo naranja-rojo
   (coral vs danger = **1.38:1** entre sí; indistinguibles en protanopia/deuteranopia).
   Un botón de borrar y uno de enviar llevan el mismo color de urgencia. `Theme.swift:140`.
   → Repintar danger a un rojo más frío/magenta (~350°): **#CE2A15 / #D42D3F** (claro).

2. **Fallos de contraste AA en modo claro** (texto pequeño 9–11pt sobre blanco):
   - `teal` como texto **2.1–2.25:1** (peor ofensor; usado en labels "running"/"TOOLS").
   - `tertiaryOnMaterial` **3.2–3.5:1** (mayor volumen; todas las métricas/eyebrows).
   - `secondaryOnMaterial` **~4.0–4.4:1**; `accent` texto **3.7–4.15:1**; `warning` **2.21:1**.
   → Fixes de hex exactos (todos preservan el tono), del auditor:
     `secondaryOnMaterial` L → **#5D6A67**, `tertiaryOnMaterial` L → **#736A5F**,
     `accent` L → **#C33A22**, `warning`(texto) → **#8F5A00**, `danger` L → **#CE2A15**,
     `tertiaryOnMaterial` D → **#7E9A9A** (único fallo en oscuro).
   → **Teal es especial**: no puede oscurecerse sin dejar de ser teal. **Partir el token**:
     `teal` para rellenos/puntos/bordes; nuevo **`tealText` = #0A7D6E** (claro) / #14C2AB (oscuro)
     para todo texto/icono teal (`5.03:1`).

3. **Estado solo-por-color (WCAG 1.4.1).** Punto coral 7×7 = "necesita atención"
   (`SidebarView.swift:265`) y punto = "actualización" (`NavRail.swift:98`) — sin forma/label.
   → Añadir glifo (`bell.badge.fill` / `arrow.down.circle.fill`). Rutar logout a `danger`
   (`SettingsView.swift:126`) para que destructivo = rojo en todas partes.

### 🟠 Marca / jerarquía (el naranja no canta)

4. **Los gradientes hero son rojo-ladrillo, no coral.** (Ver "decisión clave".) `Theme.swift:85-96`.
   El coral puro solo se ve en la marca de 24pt, los puntos del CoralSphere y dos gradientes.

5. **Sopa de opacidades: ~19 alphas de coral distintas** inventadas por sitio (0.05/0.06/0.08/
   0.10/0.12/0.13/0.14/0.16/0.18/0.20/0.22/0.30…). No es un ramp, es ruido. `coralDeep` está
   **muerto** (1 uso decorativo); los gradientes hardcodean otros 4 hexes coral.
   → **Ramp coral nombrado** (50/100/300/500/600/700) + **3 alphas sancionadas**
     (`wash .08`, `soft .14`, `edge .32`) + `glow .30`. Prohibir `.opacity()` crudo sobre coral.

6. **Teal escapó de "solo estado" a decoración/data-viz.** Delegaciones en reposo permanecen
   teal (`AgentActivityPanel.swift:1020-1053`), barras de spend/uso, anillos del rail
   (`NavRail.swift:352-384`), chip "answered by team" (`ChatView.swift:1041`). El panel
   protagonista (multi-agente) se lee **teal-first**; la marca es una extraña ahí.
   → Teal SOLO para: punto/pulso running, fila del agente activo, barra de progreso viva, badge
     `activity.running`. Data-viz → neutro/grafito o coral. "Answered by team" → coral/neutro.

7. **El loader de marca se dibuja en teal la mitad de las veces.** `WorkingLogo`/`CoralSphere`
   son "la esfera coral" por definición pero se instancian en teal (`ParticleField.swift:613-724`).
   → Recolorear todo spinner/esfera a coral. Find/replace de alto payoff.

8. **Segundo palette fuera de `Theme` que out-shouts el coral.** `AgentRole.tint`
   (`AgentRole.swift:59-63`) y `AIProvider` definen azul/verde/violeta/ámbar/rosa inline a
   saturación plena. Peor: reviewer #E5A13A = `Theme.warning` byte-a-byte; researcher #35B06A =
   el `success` viejo → mismo tono = dos significados.
   → Mover a `Theme` como "espectro de equipo" **gobernado y desaturado** (~30% menos croma,
     sesgo frío); reviewer→`warning`, researcher→`success`; **orquestador se queda coral500 a
     plena fuerza** → el nodo cálido es siempre el director rodeado de compañeros fríos apagados.

9. **Modo claro se lee gris/genérico.** Los rellenos coral viven a 12% sobre blanco → casi
   invisibles (selección del rail, badges, hooks). Oscuro lleva la marca; claro parece sin
   terminar. → Subir rellenos claro a **0.18–0.22** + borde coral hairline (`selectionBorder`).

### 🟡 Nativo macOS / higiene

10. **Tokens de texto neutro custom vs semánticos del sistema.** `ink`/`secondaryOnMaterial`/
    `tertiaryOnMaterial` sobre materiales deberían ser a menudo `.primary/.secondary/.tertiary`
    → boost de vibrancy automático, paridad claro/oscuro y atenuado de ventana inactiva gratis.
    La app ya está partida en dos vocabularios. (Mantener `ink` para display type de marca.)

11. **APIs que mienten.** `glassPanel(material:)` acepta `material:`/`strokeOpacity:` y los
    **ignora** (`Theme.swift:489` + `GlassPanelModifier`); los call-sites creen diferenciar glass
    y no. `.tint(Theme.accent)` re-declarado en ~14 subvistas (ya está en la raíz
    `StrategyForgeApp.swift:47`) = ruido muerto.
    → Honrar o borrar el parámetro; quitar los `.tint` redundantes; unificar el tint de los dos
      `ProgressView` (uno coral, otro teal hoy).

12. **Duplicación de superficies.** Base del aurora hardcodeada (`ContentView.swift:327-328`) ≠
    `Theme.appBg` → el fondo cambia según el aurora esté montado. `cardBg` == `columnBg` en oscuro
    (#121E21) → una card sobre columna no tiene separación de superficie.
    → Apuntar el aurora a `appBg`; separar `cardBg` oscuro a ~#16242A. Tokenizar los `Color(red:)`
      reef-ink repetidos.

13. **Rail material (nota).** El comentario dice "native `.sidebar`" pero implementa
    `.regularMaterial` (mi D5 fue una elección predecible por no poder verificar `.sidebar`
    behindWindow). Con tu OK visual se puede pasar al `.sidebar` nativo de verdad.

---

## Plan por fases (impacto ÷ esfuerzo ÷ riesgo)

### Fase 1 — Correcciones objetivas de paleta (1 archivo, `Theme.swift`, bajo riesgo)
*Sin cambios de vista; corrige la mayoría de fallos AA de golpe. Gate de tests después.*
- P0.1 **danger fuera del tono coral** (#CE2A15/#FF5C6C). [#1]
- P0.2 **Fixes de contraste claro**: secondary/tertiary/accent/warning + tertiary-oscuro. [#2]
- P0.3 **Partir `tealText`** (#0A7D6E) y repuntar los ~5 sitios de texto teal. [#2]
- P0.4 **Retirar `coralDeep`**, apuntar aurora base a `appBg`, separar `cardBg` oscuro. [#5,#12]

### Fase 2 — Sistema coral + teal a dieta (Theme + barrido mecánico)
- P1.1 **Ramp coral nombrado + 3 alphas sancionadas**; reemplazar las ~19 alphas y 4 hexes de
  gradiente inline por pasos nombrados; colapsar los 5 washes de selección/hover. [#5]
- P1.2 **Teal solo-estado**: neutralizar delegaciones en reposo + data-viz (barras/anillos);
  "answered by team" → coral/neutro. [#6]
- P1.3 **Loader de marca → coral** en todos los spinners/esferas. [#7]

### Fase 3 — Marca hero + modo claro (necesita tu ojo)
- P2.1 **Rellenos hero brillantes** (burbuja/CTA/avatar desde #FF6B54, contraste en el glifo) +
  glow coral real en la burbuja. ⚠️ *decisión de gusto — ver arriba.* [#4]
- P2.2 **Modo claro lleva la marca**: subir rellenos a 0.18–0.22 + borde coral; rail activo con
  barra coral plena. [#9]
- P2.3 **Coral por sustracción**: auditar cada `foregroundStyle(Theme.accent)` en iconos que no
  son acción y bajarlos a neutro (un momento coral por vista). [#6 art]

### Fase 4 — Nativo macOS + espectro de equipo (deeper, con revisión visual)
- P3.1 **Texto neutro → `.primary/.secondary/.tertiary`** sobre materiales. [#10]
- P3.2 **Arreglar/borrar `glassPanel(material:)`**, quitar `.tint` redundantes, unificar progress. [#11]
- P3.3 **Espectro de equipo gobernado y desaturado** en `Theme`; orquestador coral. [#8]
- P3.4 (opcional) Rail `.sidebar` nativo, selección nativa por tint, aurora afinado. [#13]

---

## Cómo verificar
Modo **claro Y oscuro** en macOS 26 tras cada fase; `xcodebuild test` como gate. Los cambios de
vibrancy/tint/contraste solo revelan su look real en pantalla, no en lectura.
