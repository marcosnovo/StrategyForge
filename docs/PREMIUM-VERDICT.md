# Coral — Veredicto premium (3 directores senior sobre el resultado real)

Panel sobre las **capturas renderizadas** (no un plan en abstracto): director de arte, product
designer de sistemas, diseñador macOS-nativo. Convergieron con dureza. Este doc **supersede** el
enfoque de "olas" de `PREMIUM-UI-REVIEW.md`.

## Veredicto

**No es premium. Es *pulcro*, pero pulcro ≠ premium.** Las olas gastaron el presupuesto en **2
momentos hero** (los saludos) + ajustes de tokens, y **nunca construyeron los sistemas repetidos**
—filas, listas, estados vacíos, jerarquía de tarjetas— que es donde vive el "feel" de un producto.
Resultado: **un momento diseñado rodeado de fontanería sin diseñar.** Y, crítico: **la app pelea
contra la plataforma** — listas falsas hechas a mano en vez de `List`/`Form` nativos, que es *el*
delator de una app Mac genérica.

## Causas raíz (consenso)

1. 🔴 **No hay sistema de FILA/LISTA.** 4 pantallas, 4 anatomías de fila distintas (chat 38pt avatar
   2-líneas; repos 22pt icono 6pt; providers en un `Form`; catálogo otra). *El delator #1.* Los
   tokens son consistentes; la **composición** no. (`SidebarView.chatRow`, `CodeLauncherView.repoRow`,
   `ConnectedServicesView.providerRow`, `TeamCatalogView.curatedCard`.)
2. 🔴 **Pelea con la plataforma.** ~30 `ScrollView`+`VStack` re-implementando a mano selección/hover/
   separadores que `List(selection:)` da gratis + con navegación por teclado. **Conexiones es un
   `Form` nativo crudo** = la cara de Ajustes del Sistema. El motivo de las listas falsas fue
   *preservar un wash coral de selección* — un trato al revés (la lista nativa **es** lo premium;
   el tinte coral es un 20% de opacidad, y se puede mantener con `.listRowBackground`).
3. 🔴 **Profundidad en claro invisible** (sombras por debajo del umbral perceptible sobre blanco) →
   tarjetas planas. *[Ya corregido — ver commit de elevación.]*
4. 🟠 **Muro de tarjetas iguales** — cada pantalla = pila de `.card()` del mismo peso/elevación/radio
   = se lee como Ajustes. Sin foco, sin ritmo. (`CodeLauncherView.body`: resume/recent/github/create/
   pick/clone, seis cards e2 iguales.)
5. 🟠 **El coral es color de *chrome*, no de *contenido*** — botones/selección/dots; nunca toca las
   filas de contenido. Si desaturaras el coral a gris, el 90% de cada pantalla se vería igual.
6. 🟠 **Pantallas vacías/sparse se leen sin terminar** — no hay sistema de estado vacío (aunque
   `ContentUnavailableView` sí se usa en 3 sitios → aplicar en todos).

## Qué DEJAR de hacer
Afinar sombras invisibles · guarnición de motion como "premium" (sheen/glow/shimmer son el premio de
una base premium que aún no existe) · micro-ajustes de opacidad de washes · dar por hecho que "un
hero + resto plano" está terminado.

---

## Plan sistémico (construir los elementos REPETIDOS, no otro hero)

> Regla: el feel vive en lo repetido. **Una fila, un grupo, un estado vacío, una jerarquía**,
> aplicados EN TODAS PARTES, hacen más que una 4ª ola de heroes.

### Fase A — barato, alto impacto, riesgo bajo
- ✅ **A1. Profundidad en claro visible** (subir alphas de elevación). *Hecho.*
- **A2. `ContentUnavailableView`** en la lista de chats vacía (`SidebarView:115`) + pantallas sparse —
  el patrón nativo premium que ya usas en TeamView/SkillsView. Uniformidad = se lee terminado.
- **A3. Jerarquía de tarjetas en Code**: un `heroSurface` (Reanudar) + el resto como filas inset en
  2-3 grupos con `SectionHeader` — no seis cards flotantes iguales.

### Fase B — el sistema de FILA (la mayor palanca)
- **B1. `CoralRow`**: UNA fila reutilizable (altura fija 44/56, slot leading 28-32pt, título
  `sfBodyM.medium` + subtítulo `sfCaption2`, zona trailing consistente, `hoverTint`+`selectedRow`
  siempre, agrupada con hairlines). Adoptar en repos + providers + catálogo primero.
- **B2. Coral en contenido, por estado**: la cosa activa/primaria/viva lleva coral (spine izquierdo +
  `accentSoft`), el resto neutro. Una o dos apariciones de coral por pantalla, en lo que importa.

### Fase C — nativo (mayor blast radius, con revisión visual)
- **C1. Lista de chats → `List(selection: $selectedConfigID)` + `.listStyle(.sidebar)`**, coral vía
  `.listRowBackground`. Recupera navegación por teclado. ⚠️ hay que re-hospedar selección/context
  menu/a11y — aterrizar SOLO el chat list primero, verificar en claro+oscuro, luego replicar a
  Services. (Refuta el propio comentario que originó las listas a mano.)
- **C2. Code + Connections en `Form { Section }.formStyle(.grouped)`** — profundidad inset nativa
  (crisp en blanco, sin depender de sombras), la cara premium de Ajustes que al resto le falta.

### Fase D — cohesión final
- **D1. `ScreenHeader` único** (un solo modo de abrir pantalla) · **D2. ritmo de espaciado
  codificado** (section 24 / grupo 12 / fila 2 / hero xxl una vez).

## Verificación
Claro Y oscuro tras cada fase; `xcodebuild test` local (CI pausado). Lo visual solo se juzga en
pantalla — aterrizar por piezas y validar.
