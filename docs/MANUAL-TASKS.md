# Coral — tareas manuales del fundador

Todo lo que **no puedo hacer yo** (necesita tu Mac, tus cuentas, tus decisiones o tu
verificación visual), con pasos exactos y separados. Marca cada casilla al terminar.

Índice:
1. [Captura real de tokens de Codex (#10)](#1-captura-real-de-tokens-de-codex-10)
2. [Pipeline de release (#2)](#2-pipeline-de-release-2)
3. [Política de privacidad con lexvibe (#11)](#3-política-de-privacidad-con-lexvibe-11)
4. [Verificación de CloudKit (#6 / #7)](#4-verificación-de-cloudkit-6--7)
5. [Decisiones de negocio (#3 / #44 / #42)](#5-decisiones-de-negocio-3--44--42)
6. [Verificación visual (#38 / #37 / #16 / #14 / #39 / #40)](#6-verificación-visual)

---

## 1. Captura real de tokens de Codex (#10)

**Contexto:** hoy el coste cross-provider de Codex/Gemini es una **estimación** (marcada
"~"). Para el conteo EXACTO de Codex necesito ver el formato real de sus datos de uso.
Tu intento no dio salida porque `2>/dev/null` se tragó el error y puede que `--json` no
sea el flag correcto en tu versión.

**No importa en qué carpeta** lo ejecutes (el flag `--skip-git-repo-check` lo permite).
Haz esto **en orden** y pégame la salida de los pasos 2 y 4:

**Paso 1 — mira si `--json` existe en tu versión:**
```
codex exec --help
```
Busca en la salida un flag tipo `--json`, `--output-format` o `--experimental-json`.

**Paso 2 — pruébalo SIN silenciar errores** (así vemos qué pasa de verdad):
```
codex exec --skip-git-repo-check --json "di hola"
```
Si da error, pégame el error. Si el flag correcto era otro (del paso 1), úsalo.

**Paso 3 — la vía que SÍ funciona seguro (recomendada):** Codex ya escribe un registro de
cada ejecución en `~/.codex/sessions/`. Esos ficheros contienen el conteo real de tokens
(la app ya los lee para el % de plan). Ejecuta una vez algo normal:
```
codex exec --skip-git-repo-check "di hola"
```

**Paso 4 — mándame las últimas líneas del registro más reciente** (aquí está el esquema
exacto que necesito):
```
find ~/.codex/sessions -name 'rollout-*.jsonl' -print0 | xargs -0 ls -t | head -1 | xargs tail -20
```
Pégame esa salida. Con ella cableo el conteo **real** de Codex (buscando el evento
`token_count` → `payload.info.total_token_usage.total_tokens`) en vez de la estimación.

- [ ] Hecho — salida pegada en el chat.

> Gemini: su CLI no publica uso de tokens, así que se queda en estimación "~" (esperado).

---

## 2. Pipeline de release (#2)

El detalle largo está en [`docs/RELEASE.md`](RELEASE.md). Checklist ordenado:

**Paso 1 — requisitos previos:**
- [ ] Tener **Apple Developer Program** activo ($99/año).
- [ ] Anotar tu **Team ID** (10 chars) desde <https://developer.apple.com/account> → Membership.

**Paso 2 — certificado de firma (una vez):**
- [ ] Xcode → Settings → Accounts → Manage Certificates → `+` → **"Developer ID Application"**.
- [ ] En Keychain Access, selecciona el cert **+ su clave privada** → click derecho →
  "Export 2 items…" → guarda `DeveloperID.p12` con una contraseña (apúntala).
- [ ] Codifícalo: `base64 -i DeveloperID.p12 | pbcopy`

**Paso 3 — clave de notarización (una vez):**
- [ ] <https://appstoreconnect.apple.com/access/integrations/api> → **Team Keys** →
  genera una con rol **"Developer"**. Descarga el `AuthKey_XXXXXX.p8` (solo se descarga una vez).
- [ ] Anota **Key ID** e **Issuer ID** (ambos en esa página).
- [ ] Codifícala: `base64 -i AuthKey_XXXXXX.p8 | pbcopy`

**Paso 4 — añade los 6 secrets en GitHub** (Settings → Secrets and variables → Actions →
New repository secret). Nombres EXACTOS:
- [ ] `DEVELOPER_ID_CERT_P12_BASE64` — base64 del paso 2
- [ ] `DEVELOPER_ID_CERT_PASSWORD` — contraseña del .p12
- [ ] `DEVELOPMENT_TEAM` — tu Team ID de 10 chars
- [ ] `NOTARY_KEY_ID` — Key ID del paso 3
- [ ] `NOTARY_ISSUER_ID` — Issuer ID del paso 3
- [ ] `NOTARY_KEY_P8_BASE64` — base64 del paso 3

**Paso 5 — dry-run:**
- [ ] GitHub → Actions → **release** → Run workflow → versión `0.0.1-test`.
- [ ] Espera (la notarización tarda varios minutos, es normal). Se crea un Release **borrador** con el DMG.
- [ ] Descarga el DMG, ábrelo en un Mac que no haya visto la app y confirma que Gatekeeper
  lo abre sin "desarrollador no identificado". Borra luego el Release + tag de prueba.

**Paso 6 — release real:**
- [ ] `git tag v1.0.0 && git push origin v1.0.0` → revisa las notas del borrador → **Publish**.

---

## 3. Política de privacidad con lexvibe (#11)

**Sobre tu pregunta "¿has probado a través del MCP de lexvibe?":** no — el MCP de lexvibe
**no está conectado** a esta sesión, así que no puedo generarla yo. Lo que sí te dejo aquí
son **todos los hechos reales de tratamiento de datos** (extraídos del código) para que se
los des a lexvibe y quede bien clara. Están verificados contra el código:

**Qué datos maneja Coral y dónde van:**

| Dato | Dónde se guarda | ¿Sale del Mac? |
|---|---|---|
| Tus chats, equipos, transcripts, actividad | Local: `~/Library/Application Support/…` (`data.json` + sidecars) | No (salvo sync iCloud, abajo) |
| Config portable de equipos (nombre + estrategia, **sin** rutas ni bookmarks) | **CloudKit** (tu iCloud privado) si activas sync | Sí, pero solo a **tu** iCloud — nunca a servidores de Coral |
| Logins de proveedores (Claude/Codex/Gemini) | Los CLIs los guardan en sus propias carpetas (`~/.claude`, `~/.codex`, `~/.gemini`); Coral no los copia | No |
| API keys / tokens que introduzcas | **Keychain de macOS** (`WhenUnlocked`) | No |
| Conteo de tokens / coste | Se lee de los **registros locales** de cada CLI | No |
| % de plan de Claude | Del login de Claude Code + un **endpoint no documentado de Anthropic** (llamada directa Mac→Anthropic) | Va a Anthropic, no a Coral |
| Crash/hang (MetricKit) | Log local exportable (`diagnostics.log`) | No — nunca se sube |
| Telemetría de eventos (runs, coste, shares) | Archivo local, **desactivada por defecto** | No |

**Frases clave que la app YA muestra** (para que la política sea coherente con la app):
- Usage: *"nada se envía a servidores de Coral"* (`usage.sourceDisclosure`).
- Diagnóstico: *"los informes de fallos se quedan en este Mac"* (`settings.diagnostics.caption`).
- Telemetría: *"solo en un archivo local… desactivado por defecto"* (`settings.telemetry.caption`).

**Puntos que la política DEBE cubrir (riesgo real):**
- [ ] El **endpoint no documentado de Anthropic** para el % de plan (zona gris de ToS): declarar
  que Coral hace una llamada directa a Anthropic con el token del login del usuario, y que
  puede dejar de funcionar.
- [ ] **CloudKit**: los datos van al iCloud privado del usuario, Coral no tiene backend ni acceso.
- [ ] **App Sandbox desactivado** (la app lanza los CLIs): explicar por qué necesita ese permiso.
- [ ] Que Coral **no revende tokens** ni enruta prompts por un servidor.

**Pasos:**
- [ ] Pasar esta tabla + los 4 puntos a lexvibe (golexvibe.com) y generar la política.
- [ ] Publicar la URL.
- [ ] Pégamela y la enlazo desde el README y (si quieres) desde Settings.

---

## 4. Verificación de CloudKit (#6 / #7)

Requiere **2 Macs** con tu iCloud y sync activado. (Lo harás al final de todas las fases.)

**#6 — Tombstones de borrado no resucitan:**
- [ ] Mac A: crea un chat, sincroniza. Mac B: sincroniza → aparece.
- [ ] Mac A: borra el chat, sincroniza. Mac B: sincroniza → **no debe reaparecer**.
- [ ] (Bonus #31) Edita el mismo chat en A y B sin sincronizar entre medias, luego sincroniza
  ambos → debe quedar una copia **"(conflicto)"**, sin perder ninguna edición.

**#7 — Secretos MCP no viajan:**
- [ ] Crea un equipo con un servidor MCP que tenga una env secreta (p.ej. una API key).
- [ ] Exporta el equipo (`.sfstrategy` / compartir) → abre el texto → la env secreta debe salir **vacía/redactada**.
- [ ] Tras sincronizar, revisa que el registro de CloudKit tampoco lleva el secreto.

---

## 5. Decisiones de negocio (#3 / #44 / #42)

Solo tú puedes decidir esto; cuando elijas, dímelo y lo implemento.

**#3 — Posicionamiento v1:**
- [ ] ¿Qué se muestra como "beta" (cross-provider / scheduling / auto-PR)? Condiciona README/landing/rail.

**#44 — Precio** (propuesta de los agentes: **beta gratis → Founder's Lifetime ~$79**, luego
Pro $8–12/mes o ~$79–96/año):
- [ ] Confirmar modelo + precio. El paywall técnico es v1.1.

**#42 — Orden del panel de actividad:**
- [ ] El comentario del código dice que el orden actual **lo pediste tú explícitamente**.
  Confirma si quieres izar timeline/tasks cuando está corriendo, o dejarlo como está.

---

## 6. Verificación visual

Cosas que implementé pero **tienes que mirar tú** (dijiste "los probaré luego"). Marca si OK
o dime qué ajustar. Todos son fáciles de revertir.

**#38 — Vidrio Liquid Glass** (cambié `glassPanel` al vidrio nativo):
- [ ] Revisa hojas, tarjetas de onboarding, tarjeta del advisor, secciones del editor de loops
  en **modo claro Y oscuro**. Si algo "flota" raro o se ve doble-vidrio, dímelo (revierto 1 función).

**#37 — Contraste** (corales más oscuros + verde success más oscuro):
- [ ] Botones/burbujas coral con texto blanco legible; verde de "conectado"/success legible en claro.

**#16 — Dynamic Type / suelo 10pt:**
- [ ] NavRail: los textos pequeños ahora a 10pt mínimo (antes 7–9pt).
- [ ] Ajustes del sistema → Texto más grande: NavRail debe **crecer** con él.

**#14 — Avatar estático:**
- [ ] Las burbujas de chat en reposo ya no animan a 30 fps; solo animan mientras streamea.

**#39 — Preview de ficheros:**
- [ ] Equipo con >6 roles: el selector de ficheros del preview es un **menú** (no segmentado ilegible).

**#40 — VoiceOver:**
- [ ] Filas de chat: VoiceOver dice seleccionado + "trabajando/en ejecución".
- [ ] Dots de veredicto de loop: PASS = círculo verde, FAIL = **cuadrado** rojo (distinguible sin color).

**Sellos nuevos (del artículo):**
- [ ] Editor de loop con verificador activado: aparece el sello **"Comprobación independiente"**.
- [ ] Rol (subagente) → toggle **"Memoria persistente"**; al generar, se crea `.claude/memory/<agente>.md`.

**#41 — Undo de borrado:**
- [ ] Borra un chat → aparece banner **"Chat eliminado" + "Deshacer"** ~10s. Pulsa Deshacer → el chat
  vuelve con su historial. Si esperas 10s, se borra de verdad.

**Feature nueva — Evals** (del artículo de Karpathy):
- [ ] En el editor de un **Equipo**, baja hasta la tarjeta **"Evals"**. Pulsa **"Generar escenarios"**
  (necesita el proveedor del equipo conectado) → aparece un suite de ~12 escenarios.
- [ ] Pulsa **"Ejecutar evals"** → cada escenario se puntúa con el juez independiente; sale el **%**,
  el badge **Listo / Por debajo del umbral**, y por escenario PASS (círculo verde) / FAIL (cuadrado
  rojo + razón). El suite viaja con el equipo (sync/export).
