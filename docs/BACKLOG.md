# Coral — Backlog priorizado

Origen: revisión integral multi-agente del 2026-07-17 (ver
[`REVIEW-2026-07-17.md`](REVIEW-2026-07-17.md)). Todos los ítems fueron verificados en el
código por los directores antes de entrar aquí; el racional explica **por qué no se hizo
ya** en la ronda de fixes. Esfuerzo: S (<2h) · M (medio día) · L (1–3 días) · XL (semana+).

> Regla de la casa (CLAUDE.md): `Models/LoopPlan.swift`, `Services/LoopScheduler.swift`,
> `Services/LoopRunner.swift` y `Generators/LoopFileGenerator.swift` solo se tocan con
> revisión humana del diff. Esos ítems están agrupados en el "PR de la zona de Loops".

## P0 — Bloquean la v1

| # | Ítem | Área | Esf. | Racional / por qué esperar |
|---|------|------|------|----------------------------|
| 1 | **Verificador de loops en modo solo-lectura** — `LoopRunner:268` crea el runner del verificador sin `permissionMode` (default `acceptEdits`): el juez puede editar el repo que juzga y su PASS dispara merge automático. | Loops | S | Fichero vetado: primera parada de la sesión en Mac, con revisión humana. Rompe la garantía central del feature. |
| 2 | **Pipeline de release**: `release.yml` con tag → archive → firma Developer ID → `notarytool --wait` → staple → DMG → GitHub Release; bump de `MARKETING_VERSION` desde el tag; probar el ciclo completo con UpdateChecker. | Release | M | Requiere certificados en secrets y un Mac; sin esto no hay binario que Gatekeeper acepte y el canal de updates apunta al vacío. |
| 3 | **Decisión de posicionamiento v1** y recorte de superficie: flags "beta" para cross-provider/scheduling/auto-PR; retirar el botón Google sign-in placeholder; README/landing/rail coherentes con la decisión. | Producto | L | Decisión de negocio del fundador; condiciona README, landing, rail y QA. |

## P1 — Antes del primer beta externo

| # | Ítem | Área | Esf. | Racional |
|---|------|------|------|----------|
| 4 | **PR de la zona de Loops** (vetada, un solo diff revisable): quoting de `repoPath` en `cronLine()`/`proactiveScript()` (inyección/rotura en crontab), judge tolerante a fallos bajo `set -e` (hoy un rate-limit mata el loop entero), trap del worktree que excluye `err.log`/untracked del merge, logs de LaunchAgents fuera de `/tmp` (legibles por todos) a `~/Library/Logs/Coral/`, reescritura del plist al cambiar kind/intervalo + badge "programado" en LoopSelectorColumn. Con tests de propiedad en LoopGeneratorTests en el mismo diff. | Loops | M | Política de CLAUDE.md: revisión humana + suite en verde. |
| 5 | **Carrera stop→send** en ChatViewModel: epílogo del run viejo sin guard de cancelación puede descartar en silencio la respuesta del run nuevo (índices desplazados). Fix: contador de generación (epoch) + test con runner fake. | Arquitectura | M | El fix ingenuo cambia comportamiento visible del stop; necesita el seam de testabilidad (ítem 12) para fijarlo con test. |
| 6 | **Tombstones de borrado en CloudKit**: `ConfigSyncStore.delete(ids:)` no tiene llamadores — los chats borrados resucitan al sincronizar en todos los Macs. | Persistencia | M | Cambia el protocolo de merge y requiere probar contra CloudKit real. |
| 7 | **Redactar `mcpServers.env`** en exports `.sfstrategy`/share-string y en el push a CloudKit (+ `encryptedValues`); avisar en la UI de export; corregir el comentario "Safe by construction" de StrategyPackage. | Persistencia/Generadores | M | Decisión de producto (redactar vs excluir vs Keychain por referencia) + UI. Riesgo real de publicar API keys al compartir. |
| 8 | **Procesos huérfanos al salir**: registro global de Process vivos + `applicationShouldTerminate`; romper la captura fuerte de `self` en los runTasks (los `deinit` que "limpian" son inalcanzables mid-run). | Servicios | M | Toca el ciclo de vida de la app entera; solo validable ejecutándola. |
| 9 | **Merge (no overwrite) de `.mcp.json`** existente en StrategyWriter; mientras tanto, listarlo como conflicto en el diálogo de confirmación. | Generadores | M | Parsear JSON ajeno exige fixtures y tests en Mac. |
| 10 | **Tokens/coste reales en Codex y Gemini** (parsear `codex exec --json`; estimación marcada "~" si no hay dato) — hoy el moat cross-provider reporta $0. | Producto/Servicios | M | Requiere los CLIs reales instalados para capturar fixtures. |
| 11 | **Política de privacidad** publicada + disclosure en Usage del uso del token OAuth de Claude Code (endpoint no documentado; riesgo ToS). | Producto | S | Redacción y URL del fundador; bloquea waitlist/beta. |
| 12 | **Seams de testabilidad**: `init(storeDirectory:)` en AppModel/LoopStore, protocolo `ChatTurnRunner` (fake por eventos), `FilePanelPresenting`; primera tanda de tests (round-trip persistencia+sidecars, corrupto→backup, carrera stop→send, cola de mensajes). | Arquitectura/Calidad | L | Prerequisito de los tests de regresión de casi todos los P1; hacerlo con la suite corriendo. |
| 13 | **CodeGit**: `git status --porcelain -z` / `core.quotePath=false` (hoy rutas no-ASCII salen mutiladas y stage/revert operan sobre paths inexistentes) + extraer `parseChangedFiles` puro + fixtures (rename, espacios, binario) + integración worktree con repos git temporales. | Servicios/Calidad | M | El fix de parsing y sus tests deben aterrizar juntos; el ciclo worktree decide si un loop se fusiona o se pierde. |
| 14 | **Avatar del chat como frame estático** (animar solo streaming; parámetro `animating:` en Particle3DSpinner) — hoy cada burbuja redibuja un canvas a 30 fps para siempre. | Diseño UI | M | Cambio de render en el corazón del producto; necesita verificación visual y perfilado. |
| 15 | **Reescribir README** como fuente veraz: 13 estrategias, módulo Coral, "genera archivos Y ejecuta chats/loops localmente", flujo chat-first, estructura de carpetas real, requisito de macOS decidido. | IA/Producto | M | Depende de las decisiones de posicionamiento y target para no reescribirlo dos veces. |
| 16 | **Dynamic Type**: prohibir <10pt, añadir peldaños a la escala de Theme y migrar los 222 `.font(.system(size:))` empezando por NavRail (7–9pt), ChatView y AgentActivityPanel. | Diseño UI | L | Masivo y con impacto de layout; exige ver la app renderizada. |
| 17 | **Taxonomía de dos sustantivos** (chat/equipo) en las 5 tablas de strings + miniglosario es-ES (run→ejecución, merge→fusionar). | IA | M | Decisión de vocabulario + pasada editorial completa; a medias empeora. |
| 18 | **Sidecars de transcript**: decode tolerante de ChatMessage, backup del sidecar ilegible (patrón de `load()`), propagar errores de `writeTranscript`/`appendActivity` a banner/DiagnosticsLog — hoy un historial ilegible se vacía y la siguiente escritura lo destruye. | Persistencia | S | Toca el camino caliente de streaming; merece round-trip tests en Mac. |

## P2 — v1.x

| # | Ítem | Área | Esf. | Racional |
|---|------|------|------|----------|
| 19 | Diff contra disco + confirmación antes de reescribir `loop.sh`/`LOOP.md` (capa vista/LoopWriter, sin tocar LoopFileGenerator). | Loops/UX | M | UI nueva en zona sensible; mejor con el verificador corriendo. |
| 20 | Puerta de primer nivel al flujo de generación (botón "Generar ficheros" en el header del chat, o generar desde Team). | UX | L | Depende de la decisión de posicionamiento. |
| 21 | Decode lossy por elemento en data.json/loops.json (una Configuration corrupta no debe vaciar la librería) + backup ante schemaVersion futuro (downgrade). | Persistencia | M | Con backup ya existente el riesgo actual es "rescate manual", no pérdida definitiva. |
| 22 | save() detached: serializar escrituras concurrentes + flush síncrono en `willTerminate` (hoy Cmd-Q rápido puede perder ~3s de metadatos). | Persistencia | S | Validar matando la app en Mac. |
| 23 | Bookmarks stale: regenerar y persistir al resolver (helper compartido para AppModel:1616 y LoopStore:189, hoy duplicados). | Arquitectura | S | Solo observable con security scope real en macOS. |
| 24 | `JSONFileStore<T>` genérico + `RepoBookmarkService` + stores por environment (no `.shared`) + parser GitHubRef único — el andamiaje está copiado ×4 y cada fix hay que aplicarlo N veces. | Arquitectura | M | Refactor ancho: con suite verde y de una vez. |
| 25 | SkillStore.install: descargar a temp + swap con `replaceItemAt` (hoy borra la versión instalada ANTES de descargar la nueva). | Persistencia | M | Red + FS: test de integración en Mac. |
| 26 | Watchdog de inactividad en ClaudeRunner.stream (loops desatendidos congelados en un turno colgado). | Servicios | M | Un timeout mal elegido mata syntheses legítimas (ya pasó con el cap de 5 min). |
| 27 | Validación de destino en generate()/commitAndRun: aviso si no-git, bloqueo de `$HOME` (crearía subagentes globales), quitar el `try?` silencioso. | Generadores | M | Decisiones de UX (avisar vs bloquear) + strings localizados. |
| 28 | Colisión de nombres expandidos ("worker"×3 + "worker-1" literal escriben el mismo fichero) en `Strategy.validate()`. | Generadores | M | Requiere replicar la expansión en validate() + tests. |
| 29 | Neutralizar marcadores CORAL:END inyectados en `section()` + filtrar roles inválidos de la tabla de CLAUDE.md (hoy documenta subagentes que no se generaron). | Generadores | S | Mismo PR de Mac que añade los tests de upgrade legacy/poda/CRLF. |
| 30 | Batería de tests que faltan: upgrade STRATEGYFORGE→CORAL, poda managed, PersistedLoops (hacerlo `internal`), sanitizeClaudeAuth/LineBuffer/PermissionResponder, UpdateChecker.release(from:), regresiones de Loops (set -e, sourceChatID) + revisión humana de los commits 97e3174/867c959. | Calidad | M | Solo tiene sentido escribirlos donde pueden ejecutarse. |
| 31 | Sync LWW: detectar conflicto real (lastSyncedAt) y conservar copia "(conflicto)" en vez de descartar; a futuro change tags + `.ifServerRecordUnchanged` (resuelve también el índice queryable de recordName). | Persistencia | L | Limitación v1 declarada; el paso serio es CloudKit real. |
| 32 | ProviderInstaller: pin de versión npm por release (supply chain), timeout de login 150s→reiniciable, heurística de Gemini como best-effort, escapado del AppleScript. | Servicios | M | Cada punto necesita prueba manual contra los CLIs reales. |
| 33 | Crash reporting local (MetricKit → DiagnosticsLog) + declarar la postura de privacidad de Analytics en Settings/README. | Calidad | M | MXMetricManager solo entrega datos en dispositivo real. |
| 34 | VMs con settings vivos (closures/ProviderRegistry) — el fix de esta ronda cubre `locateClaude`; cambios desde Settings (keys, autonomía) siguen sin llegar a chats abiertos. | Arquitectura | M | Solución completa del parche mínimo aplicado. |
| 35 | Extracción incremental de AppModel (ChatListStore, TeamLibrary, UsageStore, ProviderRegistry, BannerCenter, L10nService) + trocear ChatView/AgentActivityPanel + unificar el CRUD de roles vía `strategyCopy()`. | Arquitectura | XL | Nunca a ciegas: por fases, con la suite en verde en cada una. |
| 36 | Labs fuera del target de release (IdentityLab, SphereLogoLab, WowLab, ParticleLabView, CoralAssembleOverlay) extrayendo antes `WowSphereResolve` a producción; borrar los 7 spinners sin uso. | Diseño UI | M | Toca membresías del pbxproj: exige build de verificación. |
| 37 | Contraste: oscurecer el extremo claro de primaryFill/userBubbleFill y el verde del banner en light (regla "onAccent ≥ 4.5:1" documentada en Theme). | Diseño UI | S | El ajuste de color hay que verlo renderizado en light/dark. |
| 38 | Unificar el lenguaje de vidrio (`.glassEffect` vs `glassPanel()` vs `translucentColumn()`) tras validar el target 26.0. | Diseño UI | M | Migración visual no verificable sin compilar. |
| 39 | Preview de ficheros: sustituir el Picker segmentado por lista/Menu cuando hay >6 ficheros (con 10–20 instancias es ilegible). | UX | S | UI nueva que hay que ver con equipos grandes. |
| 40 | VoiceOver: `.isSelected` en filas del rail + `accessibilityValue` "en ejecución" + dots de veredicto diferenciados por forma. | Diseño UI | S | Solo verificable con VoiceOver real. |
| 41 | Soft-delete/undo para chats (retener sidecars ~30 días o "Deshacer" 10s en el banner) y confirmación que comunique el coste real. | UX/Persistencia | M | Cambia el ciclo de vida de persistencia; tests nuevos. |
| 42 | Reordenar AgentActivityPanel cuando `isRunning` (izar timeline/tasks). **Ojo:** el comentario "Order per request" indica que el orden actual fue petición explícita del usuario — confirmar antes. | IA | M | Requiere decisión del fundador. |
| 43 | Emitir `appLaunched`/`teamCreated` + pills de coste con "tarifas de <fecha>" + log de modelos fuera de la tabla de precios; tabla remota de precios en v1.1. | Producto | S | Bajo valor hasta que exista canal de recolección y decisión de pricing. |
| 44 | Modelo de monetización decidido y comunicado (recomendación: beta gratis + licencia Pro) con pregunta de pricing en el waitlist. | Producto | L | Decisión de negocio; el paywall técnico es v1.1. |

## P3 — Algún día / oportunista

| # | Ítem | Área | Esf. |
|---|------|------|------|
| 45 | Spinners: Canvas estático bajo Reduce Motion (patrón AuroraBackground) en los 8 spinners — primera tarea de una sesión en Mac; confirmado pero son 8 cuerpos SwiftUI a refactorizar sin compilador. | Diseño UI | S |
| 46 | WhatNowSheet sin regenerar (extraer `openTerminal(for:)`); readiness "comprobando…" en onboarding; devolver la cola al composer en `stop()`; no crear el chat hasta confirmar TaskToStrategySheet. | UX | S |
| 47 | Limpieza de tokens: `Theme.prMerged` con par light/dark, `reefInk` compartido, `CoralGeometry` único (la geometría del logo está ×3), borrar `railBg` sin usos, claves de localización muertas (`chat.loop.create`, `sidebar.section`, `app.purpose`…). | Diseño UI/IA | M |
| 48 | Etiquetas ".sfstrategy" → "Exportar equipo"; evaluar alias `.coralteam` retrocompatible. | IA | M |
| 49 | WorkingLogo: dos tamaños canónicos; por debajo de ~16pt usar ProgressView nativo. | Diseño UI | S |
| 50 | Chrome de ventana: derivar insets de `standardWindowButton` en runtime, revisar "Reducir transparencia", documentar el contrato en Theme. | Diseño UI | L |
| 51 | Keychain: `WhenUnlocked` + `SecItemUpdate` (vs delete+add); propagar errores de setCodable a DiagnosticsLog. | Servicios | S |
| 52 | HTTPCache: purga por antigüedad/tamaño + error tipado (hoy fabrica URLError.Code inválidos). | Servicios | S |
| 53 | `LineAccumulator` → reutilizar `LineBuffer` de ClaudeRunner (patrón O(n²) duplicado); con suite en verde. | Servicios | S |
| 54 | Quoting del binary en LaunchCommandGenerator; decidir si `.mcp.json` se stagea en gitCommitCommand (documentar la exclusión si lleva env). | Generadores | S |
| 55 | `continuedFrom` colgante al borrar el chat origen; refrescar `sourceChatName` al renombrar. | Persistencia | S |
| 56 | Validar tools importados contra `Constants.availableTools` (warning) y quotear entradas con `:`/`#`. | Generadores | S |
| 57 | `strategyKey()` → campo `templateKey` en Strategy asignado por StrategyLibrary (el matching por substring del nombre inglés es frágil). | Arquitectura | M |
| 58 | Mover `titlesMatch` de StrategyDiagramView a un helper de dominio (Services→Views invertido). | Arquitectura | S |
| 59 | UITests: smoke mínimo real (ventana + rail con launch-argument para saltar onboarding) como job nightly, o borrar el target. | Calidad | M |
| 60 | UpdateChecker: firma EdDSA del artefacto cuando haya auto-update; mientras, hash en las notas del release. | Servicios | L |
| 61 | Arquitectura de localización escalable (xcstrings o formato por idioma) antes de plantear un tercer idioma. | IA | L |
| 62 | AttachmentConverter: mover el trabajo bloqueante a Task.detached/cola dedicada (la parte del deadlock de stderr ya se corrigió). | Servicios | S |
