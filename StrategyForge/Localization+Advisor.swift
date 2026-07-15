//
//  Localization+Advisor.swift
//  StrategyForge
//
//  Strings for the Advisor feature (decision tree + recommendation UI).
//  Kept in its own dictionary so Localization.swift stays untouched; the
//  resolver merges this table in alongside `L10n.strings`.
//

import Foundation

extension L10n {

    /// key → (English, Spanish) for every Advisor-owned string.
    static let advisorStrings: [String: (en: String, es: String)] = [

        // MARK: Rail / header
        "rail.advisor": ("Advisor", "Asesor"),
        "advisor.title": ("Advisor", "Asesor"),
        "advisor.subtitle": (
            "Describe the task you want done; get the right model, team and loop — no setup.",
            "Describe la tarea que quieres hacer; obtén el modelo, el equipo y el bucle adecuados — sin configurar nada."),

        // MARK: Prompt card
        "advisor.prompt.label": ("Your task", "Tu tarea"),
        "advisor.placeholder": (
            "e.g. “Migrate every bcrypt call to argon2 and run the tests until they pass” — or “Summarize these 40 customer interviews into five themes”.",
            "p. ej. «Migra todas las llamadas de bcrypt a argon2 y corre los tests hasta que pasen» — o «Resume estas 40 entrevistas de clientes en cinco temas»."),
        "advisor.charCount": ("%lld characters", "%lld caracteres"),
        "advisor.analyze": ("Analyze", "Analizar"),
        "advisor.thinking": ("Thinking…", "Pensando…"),
        "advisor.aiBadge": ("Shaped by on-device AI", "Diseñado por IA en el dispositivo"),
        "advisor.source.ai": ("AI", "IA"),
        "advisor.source.local": ("Local", "Local"),
        "advisor.source.ai.full": ("Recommended by Apple Intelligence (on-device)",
                                   "Recomendado por Apple Intelligence (en el dispositivo)"),
        "advisor.source.local.full": ("Recommended by the local engine (rules-based)",
                                      "Recomendado por el motor local (basado en reglas)"),
        "advisor.enableAI": ("Enable AI", "Activar IA"),
        "advisor.enableAI.full": ("Turn on Apple Intelligence for smarter picks",
                                  "Activa Apple Intelligence para recomendaciones más inteligentes"),
        "advisor.localOnly": ("Using the local engine — Apple Intelligence isn't available on this Mac.",
                              "Usando el motor local — Apple Intelligence no está disponible en este Mac."),
        "advisor.loop.whyResults": ("A loop re-runs the team until the goal is met — better coverage and fewer misses on broad searches.",
                                    "Un bucle repite el equipo hasta cumplir el objetivo — mejor cobertura y menos fallos en búsquedas amplias."),
        "advisor.tier.saver": ("Economy", "Económica"),
        "advisor.tier.saver.note": ("Cheaper & faster — good enough for most", "Más barata y rápida — suficiente para la mayoría"),
        "advisor.tier.balanced": ("Recommended", "Recomendada"),
        "advisor.tier.balanced.note": ("Best balance of quality and cost", "Mejor equilibrio calidad/coste"),
        "advisor.tier.max": ("Max quality", "Máxima calidad"),
        "advisor.tier.max.note": ("Better results, higher cost", "Mejores resultados, más coste"),
        "advisor.tier.caption": ("Options", "Opciones"),

        // MARK: Decision path
        "advisor.path.title": ("How we decided", "Cómo lo decidimos"),
        "advisor.path.result": ("Recommendation", "Recomendación"),
        "advisor.chip.yes": ("Yes", "Sí"),
        "advisor.chip.no": ("No", "No"),

        // Questions
        "advisor.q.depth": ("Does it need more than a quick answer?",
                            "¿Necesita más que una respuesta rápida?"),
        "advisor.q.speed": ("Is maximum speed at minimal cost the priority?",
                            "¿La prioridad es la máxima velocidad al mínimo coste?"),
        "advisor.q.hardest": ("Is this your hardest, most ambitious work?",
                              "¿Es tu trabajo más difícil y ambicioso?"),
        "advisor.q.team": ("Is a full team worth it here?",
                           "¿Merece la pena un equipo completo aquí?"),
        "advisor.q.loop": ("Does it repeat, or does it have a finish line?",
                           "¿Se repite o tiene una meta clara?"),

        // Answers
        "advisor.a.depth.yes": ("Yes — this is real, multi-step work",
                                "Sí — es trabajo real de varios pasos"),
        "advisor.a.depth.no": ("No — a single good reply covers it",
                               "No — una sola buena respuesta basta"),
        "advisor.a.speed.yes": ("Yes — Haiku 4.5: the fastest, cheapest tier",
                                "Sí — Haiku 4.5: el nivel más rápido y barato"),
        "advisor.a.speed.no": ("No — Sonnet 5: the balanced default",
                               "No — Sonnet 5: el equilibrio por defecto"),
        "advisor.a.hardest.yes": ("Yes — Fable 5: frontier reasoning for frontier work",
                                  "Sí — Fable 5: razonamiento de frontera para trabajo de frontera"),
        "advisor.a.hardest.no": ("No — Opus 4.8: expert depth without the flagship price",
                                 "No — Opus 4.8: profundidad experta sin el precio del buque insignia"),
        "advisor.a.team.yes": ("Yes — the task splits into parallel work",
                               "Sí — la tarea se divide en trabajo paralelo"),
        "advisor.a.team.no": ("No — a lean setup fits a fast model better",
                              "No — con un modelo rápido basta un equipo ligero"),
        "advisor.a.loop.turnBased": ("No — a simple turn-by-turn chat is enough",
                                     "No — basta un chat por turnos"),
        "advisor.a.loop.goalBased": ("Yes — it has a verifiable finish line: loop until it's met",
                                     "Sí — tiene una meta verificable: itera hasta cumplirla"),
        "advisor.a.loop.timeBased": ("Yes — it recurs on a schedule: run it on a timer",
                                     "Sí — se repite con horario: prográmalo con temporizador"),
        "advisor.a.loop.proactive": ("Yes — it reacts to events: trigger it when they happen",
                                     "Sí — reacciona a eventos: actívalo cuando ocurran"),

        // Evidence (matched-signal explanations)
        "advisor.ev.multistep": ("multi-step verbs detected (migrate, refactor, build…)",
                                 "verbos de varios pasos detectados (migrar, refactorizar, construir…)"),
        "advisor.ev.long": ("long, detailed prompt", "prompt largo y detallado"),
        "advisor.ev.scope": ("mentions the repo, tests, many files or days of work",
                             "menciona el repo, tests, muchos archivos o días de trabajo"),
        "advisor.ev.breadth": ("asks for breadth: several fronts, exhaustive, in parallel, a backlog",
                               "pide amplitud: varios frentes, exhaustiva, en paralelo, un backlog"),
        "advisor.ev.speedWords": ("quick-task words (summarize, translate, list…)",
                                  "palabras de tarea rápida (resumir, traducir, listar…)"),
        "advisor.ev.ambition": ("architecture / multi-day / deep-research scope",
                                "alcance de arquitectura / varios días / investigación profunda"),
        "advisor.ev.migration": ("a cross-cutting migration", "una migración transversal"),
        "advisor.ev.orchestration": ("orchestration of many agents", "orquestación de muchos agentes"),
        "advisor.ev.complexScope": ("complex work over a large scope",
                                    "trabajo complejo sobre un alcance grande"),
        "advisor.ev.cheapModel": ("a fast, cheap model doesn't need a fleet",
                                  "un modelo rápido y barato no necesita una flota"),
        "advisor.ev.serialDebug": ("a serial root-cause hunt — the accumulated context is the work",
                                   "una búsqueda de causa raíz en serie — el contexto acumulado es el trabajo"),
        "advisor.ev.goalWords": ("a verifiable finish line (tests, lint, “until…”)",
                                 "una meta verificable (tests, lint, «hasta que…»)"),
        "advisor.ev.timeWords": ("a recurring schedule (daily, every…)",
                                 "un horario recurrente (diario, cada…)"),
        "advisor.ev.eventWords": ("reacts to something happening (a failure, new work arriving)",
                                  "reacciona a algo que ocurre (un fallo, trabajo nuevo que llega)"),

        // MARK: Cross-provider picks
        "advisor.providers.title": ("Provider mix", "Mezcla de proveedores"),
        "advisor.providers.subtitle": (
            "Each role runs on the best model you've connected — something no single vendor's CLI can do.",
            "Cada rol corre en el mejor modelo que tengas conectado — algo que ningún CLI de un solo proveedor puede hacer."),
        "advisor.provider.reason.reasoning": ("strongest reasoning to lead",
                                              "mejor razonamiento para liderar"),
        "advisor.provider.reason.coding": ("specialist at writing code",
                                           "especialista en escribir código"),
        "advisor.provider.reason.breadth": ("widest context to read & research",
                                            "mayor contexto para leer e investigar"),
        "advisor.provider.reason.speed": ("fast & cheap for parallel work",
                                          "rápido y barato para trabajo en paralelo"),
        "advisor.provider.reason.diversity": ("a second opinion from a different model family",
                                              "un segundo par de ojos de otra familia de modelos"),
        "advisor.provider.reason.onlyOne": ("the only capable provider connected for this role",
                                            "el único proveedor capaz conectado para este rol"),

        // MARK: Model card
        "advisor.model.title": ("Recommended model", "Modelo recomendado"),
        "advisor.model.pricing": ("$%.0f in / $%.0f out per million tokens",
                                  "$%.0f entrada / $%.0f salida por millón de tokens"),

        // MARK: Strategy card
        "advisor.strategy.title": ("Team strategy", "Estrategia de equipo"),
        "advisor.rationale.solo": (
            "One agent is enough — no coordination overhead.",
            "Con un solo agente basta — sin sobrecoste de coordinación."),
        "advisor.rationale.execadv": (
            "One executor does the work; an advisor double-checks each step.",
            "Un ejecutor hace el trabajo; un asesor revisa cada paso."),
        "advisor.rationale.planner": (
            "Plan first, implement, then review — for work that must land safely.",
            "Primero planificar, luego implementar y revisar — para trabajo que debe salir bien."),
        "advisor.rationale.fanout": (
            "The task splits into parallel chunks an orchestrator can hand out.",
            "La tarea se divide en partes paralelas que un orquestador reparte."),
        "advisor.rationale.research": (
            "Several researchers explore in parallel and report back.",
            "Varios investigadores exploran en paralelo e informan de vuelta."),
        "advisor.rationale.debate": (
            "Opposing views argue it out before a decision is made.",
            "Posturas opuestas debaten antes de tomar la decisión."),
        "advisor.rationale.domain": (
            "Each specialist owns its domain; the orchestrator routes the work.",
            "Cada especialista domina su área; el orquestador enruta el trabajo."),
        "advisor.rationale.sparring": (
            "One agent builds while another tries to break it.",
            "Un agente construye mientras otro intenta romperlo."),
        "advisor.rationale.scout": (
            "A cheap scout maps the terrain first, then an implementer acts on a tight brief.",
            "Un explorador barato mapea el terreno primero y luego un implementador actúa sobre un brief preciso."),
        "advisor.rationale.triage": (
            "A cheap triager classifies each item and routes it to the right handler.",
            "Un clasificador barato tría cada elemento y lo enruta al agente adecuado."),
        "advisor.rationale.rootcause": (
            "A serial root-cause hunt: reproduce, locate, fix, then verify.",
            "Una caza de causa raíz en serie: reproducir, localizar, corregir y verificar."),
        "advisor.rationale.pipeline": (
            "Big, unfamiliar work: scout maps it, then plan → build → review in one pipeline.",
            "Trabajo grande y desconocido: el explorador lo mapea, luego planificar → construir → revisar en un solo flujo."),
        "advisor.rationale.downgraded": (
            "Scaled the team down: a quick task on a fast model doesn't need a fleet.",
            "Equipo reducido: una tarea rápida en un modelo veloz no necesita una flota."),
        "advisor.rationale.nondelegable": (
            "Nothing to hand off: a serial debugging chain stays with one capable agent.",
            "Nada que delegar: una cadena de depuración en serie se queda con un solo agente capaz."),

        // MARK: Loop card
        "advisor.loop.title": ("Loop", "Bucle"),
        "advisor.loop.goalLabel": ("Suggested goal", "Meta sugerida"),

        // MARK: Actions
        "advisor.action.chat": ("Use in a new chat", "Usar en un chat nuevo"),
        "advisor.usedInChat": ("Your task is ready in a new chat — press Send when you're ready.",
                               "Tu tarea está lista en un chat nuevo — pulsa Enviar cuando quieras."),
        // Per-prompt (follow-up) assignee suggestion chip.
        "advisor.followup.suggest": ("For this, %@ might fit better", "Para esto, %@ podría encajar mejor"),
        "advisor.followup.switch": ("Switch", "Cambiar"),
        "advisor.followup.switched": ("Switched to %@ for this chat", "Cambiado a %@ en este chat"),
        "common.dismiss": ("Dismiss", "Descartar"),
        "advisor.action.loop": ("Create loop from this", "Crear un bucle con esto"),
        "advisor.action.copy": ("Copy launch command", "Copiar comando de arranque"),
        "advisor.action.copied": ("Copied", "Copiado"),
        "advisor.action.crossProviderNote": (
            "Cross-provider teams run in a new chat — the terminal launch is Claude-only.",
            "Los equipos multi-proveedor se ejecutan en un chat — el lanzamiento en terminal es solo-Claude."),

        // MARK: Inline card (Advisor inside the chat)
        "advisor.inline.caption": ("Advisor", "Asesor"),
        "advisor.inline.applyTeam": ("Apply team", "Aplicar equipo"),
        "advisor.inline.switchTeam": ("Switch to this", "Cambiar a este"),
        "advisor.inline.youChose": ("You chose “%@” — here's what I'd recommend for this task:",
                                    "Elegiste «%@» — esto es lo que recomendaría para esta tarea:"),
        "advisor.inline.createLoop": ("Create loop", "Crear bucle"),
        "advisor.provider.connect": ("Connect to enable the full mix", "Conéctalos para habilitar la mezcla"),
        "advisor.loop.hint.title": ("This can run as a loop", "Esto puede correr como un bucle"),
        "advisor.loop.hint.goalBased": ("Repeat automatically until the goal is met (e.g. the tests pass).",
                                        "Repite solo hasta cumplir el objetivo (p. ej. que pasen los tests)."),
        "advisor.loop.hint.timeBased": ("Run it automatically on a schedule (daily, weekly…).",
                                        "Ejecútalo automáticamente según un horario (diario, semanal…)."),
        "advisor.loop.hint.proactive": ("Run it on an event — every PR, or whenever something fails.",
                                        "Ejecútalo ante un evento — cada PR, o cuando algo falle."),
        "advisor.inline.why": ("Why this?", "¿Por qué?"),
        "advisor.inline.dismiss": ("Dismiss", "Descartar"),
        "activity.compare.title": ("Your choice vs recommended", "Tu elección vs recomendado"),
        "activity.compare.selected": ("Selected", "Seleccionado"),
        "activity.compare.recommended": ("Recommended", "Recomendado"),
        "activity.compare.roles": ("%d roles", "%d roles"),
        "activity.compare.why": ("Why the recommendation: %@.", "Por qué la recomendación: %@."),
        "chat.createLoop": ("Create a loop from this chat…", "Crear un bucle desde este chat…"),
    ]
}
