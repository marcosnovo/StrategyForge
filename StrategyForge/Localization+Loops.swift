//
//  Localization+Loops.swift
//  StrategyForge
//
//  Strings for the Loop Builder. Kept in a feature dictionary so
//  Localization.swift stays untouched; the resolver consults this table too.
//

import Foundation

extension L10n {

    /// key → (English, Spanish) for every Loop Builder string.
    static let loopStrings: [String: (en: String, es: String)] = [

        // MARK: Rail / list
        "rail.loops": ("Loops", "Bucles"),
        "loop.create": ("New loop", "Nuevo bucle"),
        "loop.untitled": ("Untitled loop", "Bucle sin nombre"),
        "loop.list.turns": ("×%lld turns", "×%lld turnos"),
        "loop.delete": ("Delete this loop", "Eliminar este bucle"),
        "loop.delete.confirm": ("Delete this loop? This can't be undone.",
                                "¿Eliminar este bucle? No se puede deshacer."),
        "loop.empty.title": ("No loops yet", "Aún no hay bucles"),
        "loop.empty.desc": ("A loop is a task Claude repeats on its own: it works, an independent verifier grades the result, and it iterates until the goal is met — with a turn limit as emergency brake.",
                            "Un bucle es una tarea que Claude repite por su cuenta: trabaja, un verificador independiente califica el resultado e itera hasta cumplir el objetivo — con un límite de turnos como freno de emergencia."),
        "loop.empty.create": ("Create a loop", "Crear un bucle"),
        "loop.lastRun": ("Last run", "Última ejecución"),

        // Scheduling (background LaunchAgent)
        "loop.schedule": ("Run on a schedule", "Ejecutar según horario"),
        "loop.schedule.every": ("Runs every %lld min in the background — keeps going after Coral is closed.",
                                "Se ejecuta cada %lld min en segundo plano — sigue tras cerrar Coral."),
        "loop.schedule.on": ("Scheduled — running in the background.", "Programado — ejecutándose en segundo plano."),
        "loop.schedule.enabled": ("Scheduled to run every %lld min.", "Programado para ejecutarse cada %lld min."),
        "loop.schedule.disabled": ("Schedule turned off.", "Horario desactivado."),
        "loop.schedule.lastError": ("The last background run reported errors — the sign-in may have expired.",
                                    "La última ejecución en segundo plano dio errores — puede que la sesión haya caducado."),
        "loop.schedule.viewLog": ("View log", "Ver registro"),
        "loop.schedule.verify": ("Verify sign-in", "Verificar sesión"),
        "loop.schedule.verifying": ("Checking…", "Comprobando…"),
        "loop.schedule.signedIn": ("Sign-in OK", "Sesión OK"),
        "loop.schedule.signInExpired": ("Sign-in failed — reconnect", "Sesión caducada — reconecta"),

        // Checkpoints (non-destructive rewind of a run)
        "loop.checkpoints": ("Checkpoints", "Puntos de control"),
        "loop.checkpoint.iteration": ("Iteration %lld", "Iteración %lld"),
        "loop.checkpoint.restore": ("Restore", "Restaurar"),
        "loop.checkpoint.restore.confirm": ("Restore the project files to this checkpoint? Uncommitted work after it will be overwritten.",
                                            "¿Restaurar los archivos del proyecto a este punto? El trabajo sin confirmar posterior se sobrescribirá."),
        "loop.checkpoint.restored": ("Restored to iteration %lld.", "Restaurado a la iteración %lld."),
        "loop.checkpoint.restoreFailed": ("Couldn't restore the checkpoint.", "No se pudo restaurar el punto de control."),

        // MARK: Run notifications / banners
        "banner.loopsCorrupt": ("Your saved loops couldn't be read. A backup was kept as “%@” in Application Support/Coral.",
                                "No se pudieron leer tus bucles guardados. Se conservó una copia como «%@» en Application Support/Coral."),
        "banner.loopsSaveFailed": ("Couldn't save your loops: %@", "No se pudieron guardar tus bucles: %@"),
        "loop.runDone": ("Loop “%@” met its goal.", "El bucle «%@» cumplió su objetivo."),
        "loop.runFailed": ("Loop “%@” stopped without meeting its goal — open Loops for details.",
                           "El bucle «%@» se detuvo sin cumplir su objetivo — abre Bucles para ver los detalles."),
        "loop.runDoneUnverified": ("Loop “%@” finished one pass (no verifier).",
                                   "El bucle «%@» terminó una pasada (sin verificador)."),
        "loop.createdFromAdvice": ("Loop created — check the goal, pick a folder, and run it.",
                                   "Bucle creado — revisa el objetivo, elige una carpeta y ejecútalo."),

        // MARK: Loop kinds
        "loop.kind.turnBased": ("Turn-based", "Por turnos"),
        "loop.kind.turnBased.blurb": ("You decide each round: run it, check it, then say “again” or “stop”.",
                                      "Tú decides cada ronda: ejecuta, revisa y di «otra vez» o «parar»."),
        "loop.kind.turnBased.suits": ("Exploratory work where you decide the next step each round.",
                                      "Trabajo exploratorio donde tú decides el siguiente paso en cada ronda."),
        "loop.kind.turnBased.starts": ("You — you prompt it each round.",
                                       "Tú — le pides algo en cada ronda."),
        "loop.kind.turnBased.until": ("You stop, or the turn limit is reached.",
                                      "Tú paras, o se alcanza el límite de turnos."),
        "loop.kind.goalBased": ("Goal loop", "Por objetivo"),
        "loop.kind.goalBased.blurb": ("You set the goal; an independent verifier checks every attempt and gates the exit.",
                                      "Tú fijas la meta; un verificador independiente comprueba cada intento y controla la salida."),
        "loop.kind.goalBased.suits": ("Tests-pass or bug-cleared tasks with a checkable finish line.",
                                      "Tareas tipo «los tests pasan» o «bug resuelto», con una meta comprobable."),
        "loop.kind.goalBased.starts": ("A goal you define up front.",
                                       "Un objetivo que defines de antemano."),
        "loop.kind.goalBased.until": ("An independent verifier confirms the goal — or the turn limit hits.",
                                      "Un verificador independiente confirma el objetivo — o se agotan los turnos."),
        "loop.kind.timeBased": ("Scheduled", "Programado"),
        "loop.kind.timeBased.blurb": ("Fires on a timer — no human, no goal gate: check, react, wait, repeat.",
                                      "Se dispara con un temporizador — sin humano ni meta: revisa, reacciona, espera, repite."),
        "loop.kind.timeBased.suits": ("Recurring check-ins — a daily summary, a routine health check.",
                                      "Tareas recurrentes — un resumen diario, una revisión rutinaria de estado."),
        "loop.kind.timeBased.starts": ("A timer — every set interval.",
                                       "Un temporizador — cada intervalo fijado."),
        "loop.kind.timeBased.until": ("You stop it — otherwise it keeps running on schedule.",
                                      "Tú lo paras — si no, sigue ejecutándose según el horario."),
        "loop.kind.proactive": ("Proactive", "Proactivo"),
        "loop.kind.proactive.blurb": ("Reacts to outside events, routing each to parallel agents that review the result.",
                                      "Reacciona a eventos externos, enrutando cada uno a agentes paralelos que revisan el resultado."),
        "loop.kind.proactive.suits": ("Reacting to outside events — a build breaks, new work arrives.",
                                      "Reaccionar a eventos externos — algo se rompe, llega trabajo nuevo."),
        "loop.kind.proactive.starts": ("An outside event fires it.",
                                       "Lo dispara un evento externo."),
        "loop.kind.proactive.until": ("You stop it — otherwise it watches continuously.",
                                      "Tú lo paras — si no, vigila de forma continua."),

        // MARK: Flow diagram / explainer
        "loop.flow.repeat": ("repeat", "repite"),
        "loop.explain.starts": ("Starts with", "Empieza con"),
        "loop.explain.until": ("Repeats until", "Repite hasta"),
        "loop.explain.bestFor": ("Best for", "Ideal para"),

        // MARK: Diagram branch labels
        "loop.flow.nextRound": ("next round", "otra ronda"),
        "loop.flow.stop": ("stop", "parar"),
        "loop.flow.pass": ("Pass", "Pasa"),
        "loop.flow.fail": ("Fail", "Falla"),
        "loop.flow.everyMin": ("every %lld min", "cada %lld min"),

        // MARK: Legend eyebrows (shared, mono-caps) + honest cadence footer
        "loop.legend.start": ("START", "INICIO"),
        "loop.legend.trigger": ("TRIGGER", "DISPARO"),
        "loop.legend.rule": ("RULE", "REGLA"),
        "loop.legend.stop": ("STOP", "PARADA"),
        "loop.cadence.turnBased": ("You drive — one round at a time.", "Tú marcas el ritmo — una ronda cada vez."),
        "loop.cadence.goalBased": ("Up to %lld turns, then the brake.", "Hasta %lld turnos, luego el freno."),
        "loop.cadence.timeBased": ("Runs every %lld min.", "Se ejecuta cada %lld min."),
        "loop.cadence.proactive": ("Watches continuously.", "Vigila de forma continua."),

        // MARK: Turn-based legend
        "loop.kind.turnBased.legend.start": ("You — one prompt per round.", "Tú — un prompt por ronda."),
        "loop.kind.turnBased.legend.trigger": ("Your next prompt.", "Tu siguiente prompt."),
        "loop.kind.turnBased.legend.rule": ("You decide each round: go again or stop.", "Tú decides cada ronda: seguir o parar."),
        "loop.kind.turnBased.legend.stop": ("You stop it, or the turn limit hits.", "Tú lo paras, o se alcanza el límite de turnos."),

        // MARK: Goal-based legend
        "loop.kind.goalBased.legend.start": ("A goal you define up front.", "Un objetivo que defines de antemano."),
        "loop.kind.goalBased.legend.trigger": ("Each attempt runs, then is judged.", "Cada intento se ejecuta y luego se juzga."),
        "loop.kind.goalBased.legend.rule": ("An independent verifier gates the exit: Fail → retry, Pass → done.", "Un verificador independiente controla la salida: Falla → reintenta, Pasa → hecho."),
        "loop.kind.goalBased.legend.stop": ("The verifier confirms the goal — or the turn limit hits.", "El verificador confirma el objetivo — o se agotan los turnos."),

        // MARK: Time-based legend
        "loop.kind.timeBased.legend.start": ("A timer, on a fixed interval.", "Un temporizador, en un intervalo fijo."),
        "loop.kind.timeBased.legend.trigger": ("The interval fires it — no human, no goal gate.", "El intervalo lo dispara — sin humano, sin meta."),
        "loop.kind.timeBased.legend.rule": ("Check, react, wait, repeat on the clock.", "Revisa, reacciona, espera y repite según el reloj."),
        "loop.kind.timeBased.legend.stop": ("You stop it — otherwise it runs on schedule.", "Tú lo paras — si no, sigue según el horario."),

        // MARK: Proactive legend
        "loop.kind.proactive.legend.start": ("An outside event arrives.", "Llega un evento externo."),
        "loop.kind.proactive.legend.trigger": ("Any watched event fires it — no one is online.", "Cualquier evento vigilado lo dispara — nadie está en línea."),
        "loop.kind.proactive.legend.rule": ("A router fans work out to parallel agents, then reviews.", "Un enrutador reparte el trabajo a agentes en paralelo y luego revisa."),
        "loop.kind.proactive.legend.stop": ("You stop it — otherwise it watches continuously.", "Tú lo paras — si no, vigila de forma continua."),

        // MARK: Diagram stages
        "loop.stage.prompt": ("Prompt", "Prompt"),
        "loop.stage.work": ("Work", "Trabajo"),
        "loop.stage.check": ("Check", "Revisión"),
        "loop.stage.reply": ("Reply", "Respuesta"),
        "loop.stage.goal": ("Goal", "Objetivo"),
        "loop.stage.try": ("Try", "Intento"),
        "loop.stage.judge": ("Judge", "Veredicto"),
        "loop.stage.done": ("Done", "Hecho"),
        "loop.stage.interval": ("Interval", "Intervalo"),
        "loop.stage.react": ("React", "Reacción"),
        "loop.stage.wait": ("Wait", "Espera"),
        "loop.stage.event": ("Event", "Evento"),
        "loop.stage.route": ("Route", "Ruta"),
        "loop.stage.review": ("Review", "Revisión"),

        // MARK: Editor — header + kind card
        "loop.editor.name.placeholder": ("Loop name", "Nombre del bucle"),
        "loop.editor.kind.title": ("Loop type", "Tipo de bucle"),
        "loop.editor.kind.subtitle": ("How the loop fires and who steers it.",
                                      "Cómo se dispara el bucle y quién lo dirige."),

        // MARK: Editor — goal card
        "loop.editor.goal.title": ("Goal — your task", "Objetivo — tu tarea"),
        "loop.editor.goal.subtitle": ("This is your prompt, turned into the loop's “done when”. Edit it so a check can confirm it — the loop repeats until it's true, then stops.",
                                      "Esto es tu prompt, convertido en el «terminado cuando» del bucle. Edítalo para que algo pueda comprobarlo — el bucle repite hasta que sea cierto y para."),
        "loop.editor.goal.label": ("done when (verifiable)", "terminado cuando (verificable)"),
        "loop.editor.goal.placeholder": ("e.g. all tests in tests/auth pass and lint is clean",
                                         "p. ej. todos los tests de tests/auth pasan y el lint está limpio"),
        "loop.editor.goal.good": ("\"all tests in tests/auth pass and the checks are clean\" — a machine can verify it.",
                                  "«todos los tests de tests/auth pasan y las comprobaciones están limpias» — una máquina puede verificarlo."),
        "loop.editor.goal.bad": ("\"make auth better\" — no way to know when to stop.",
                                 "«mejora la autenticación» — imposible saber cuándo parar."),
        "loop.editor.guardrails": ("Guardrails", "Límites de seguridad"),
        "loop.editor.neverTouch.label": ("never touch", "no tocar nunca"),
        "loop.editor.neverTouch.placeholder": ("One path or area per line, e.g. migrations/",
                                               "Una ruta o área por línea, p. ej. migrations/"),
        "loop.editor.stopIf.label": ("also stop if", "parar también si"),
        "loop.editor.stopIf.placeholder": ("Extra stop conditions, one per line",
                                           "Condiciones de parada extra, una por línea"),
        "loop.editor.maxTurns": ("Max %lld turns", "Máx. %lld turnos"),
        "loop.editor.maxTurns.brake": ("The emergency brake: a hard stop even if the goal isn't met.",
                                       "El freno de emergencia: parada en seco aunque el objetivo no se haya cumplido."),
        "loop.editor.interval": ("interval", "intervalo"),
        "loop.editor.minutes": ("%lld min", "%lld min"),

        // Effort — the "how hard it thinks" dial, written into loop.sh as --effort.
        "loop.editor.effort": ("Effort", "Esfuerzo"),
        "loop.editor.effort.caption": ("How hard the worker thinks each turn — written into loop.sh as --effort. Higher costs more; a better model usually beats a higher dial.",
                                       "Cuánto piensa el trabajador en cada turno — se escribe en loop.sh como --effort. Más esfuerzo cuesta más; un mejor modelo suele ganarle a subir el dial."),

        // Spend cap (goal loops) — the article's second abort: "a loop with no dollar cap is a bill".
        "loop.editor.budget": ("Spend cap", "Tope de gasto"),
        "loop.editor.budget.why": ("Stop the loop once its reported cost passes this amount — a second brake beside the turn limit. Goal loops only.",
                                   "Detiene el bucle cuando su coste declarado supera esta cantidad — un segundo freno junto al límite de turnos. Solo bucles por objetivo."),
        "loop.editor.budget.amount": ("Cap (USD)", "Tope (USD)"),

        // MARK: Editor — team card
        "loop.editor.team.title": ("Team of the loop", "Equipo del bucle"),
        "loop.editor.team.subtitle": ("Who does the work, who grades it, and what the loop remembers.",
                                      "Quién hace el trabajo, quién lo califica y qué recuerda el bucle."),
        "loop.editor.worker": ("worker", "trabajador"),
        "loop.editor.verifier": ("Independent verifier", "Verificador independiente"),
        "loop.editor.verifier.why": ("The maker never grades its own work — a separate agent judges each iteration against the goal.",
                                     "Quien hace el trabajo nunca califica su propio resultado — un agente aparte juzga cada iteración contra el objetivo."),
        "loop.editor.verifier.model": ("verifier model", "modelo del verificador"),
        "loop.editor.memory": ("Memory (STATE.md)", "Memoria (STATE.md)"),
        "loop.editor.memory.why": ("A notes file the loop reads first and updates last, so run N+1 resumes instead of restarting.",
                                   "Un archivo de notas que el bucle lee al empezar y actualiza al terminar, para que la ejecución N+1 retome en vez de empezar de cero."),
        "loop.editor.worktree": ("Isolate in a git worktree", "Aislar en un worktree de git"),
        "loop.editor.worktree.why": ("Run each loop on its own branch in a separate worktree, so parallel loops never clash. On a verified PASS it merges back and cleans up; otherwise the branch is left for you to review.",
                                     "Ejecuta cada bucle en su propia rama, en un worktree aparte, para que los bucles en paralelo no choquen. Con un PASS verificado fusiona y limpia; si no, deja la rama para que la revises."),

        // The "reviewer ≠ author" quality seal (IndependentVerifierSeal).
        "seal.verifier.title": ("Independent check", "Comprobación independiente"),
        "seal.verifier.body": ("The verifier runs read-only — it can read files and run tests, but can't edit the code it grades. So the judge can't quietly \"fix\" what it's judging.",
                               "El verificador se ejecuta en solo lectura — puede leer archivos y correr tests, pero no editar el código que califica. Así el juez no puede \"arreglar\" en silencio lo que juzga."),
        "seal.verifier.compact": ("Read-only judge", "Juez de solo lectura"),

        "loop.editor.kind.details": ("How this type works", "Cómo funciona este tipo"),
        "loop.editor.changeType": ("Change type", "Cambiar tipo"),
        "loop.editor.customize": ("Customize (team, guardrails, limits)",
                                  "Personalizar (equipo, límites, guardarraíles)"),

        // MARK: Editor — diagram card
        "loop.editor.diagram.title": ("The cycle", "El ciclo"),
        "loop.editor.diagram.subtitle": ("One pass, left to right: the coral stage triggers it, the green stage is the exit, and the dashed arc repeats.",
                                         "Una pasada, de izquierda a derecha: la etapa coral lo dispara, la verde es la salida y el arco punteado repite."),

        // MARK: Editor — bottom bar
        "loop.editor.needRepo": ("Choose a target folder first — that's where the loop files are written.",
                                 "Elige primero una carpeta destino: ahí se escriben los archivos del bucle."),
        "loop.editor.chooseRepo": ("Choose folder…", "Elegir carpeta…"),
        "loop.editor.changeFolder": ("Change", "Cambiar"),
        "loop.editor.chooseRepo.help": ("The project folder where LOOP.md, loop.sh and the verifier are written.",
                                        "La carpeta del proyecto donde se escriben LOOP.md, loop.sh y el verificador."),
        "loop.editor.preview": ("Preview", "Vista previa"),
        "loop.editor.generate": ("Generate files", "Generar archivos"),
        "loop.editor.generate.help": ("Write the loop's files into the chosen folder.",
                                      "Escribe los archivos del bucle en la carpeta elegida."),
        "loop.editor.generated": ("Wrote %lld files to %@.", "Se escribieron %lld archivos en %@."),
        "loop.editor.generateFailed": ("Couldn't write the files: %@", "No se pudieron escribir los archivos: %@"),
        "loop.editor.copyLaunch": ("Copy the launch command", "Copiar el comando de arranque"),
        "loop.editor.launch.caption": ("Optional: run this in your project folder to start the loop from Terminal. The Run button above does the same thing from here.",
                                       "Opcional: ejecútalo en la carpeta de tu proyecto para arrancar el bucle desde la Terminal. El botón Ejecutar de arriba hace lo mismo desde aquí."),
        "loop.editor.reveal.help": ("Show this folder in Finder", "Mostrar esta carpeta en el Finder"),
        "loop.preview.title": ("Files this loop will write", "Archivos que escribirá este bucle"),

        // MARK: Validation issues
        "loop.issue.name": ("Give the loop a name.", "Ponle un nombre al bucle."),
        "loop.issue.goal": ("Write a verifiable \"done when\" condition.",
                            "Escribe una condición de «terminado cuando» verificable."),
        "loop.issue.noVerifier": ("A goal loop without an independent verifier grades its own work — enable the verifier.",
                                  "Un bucle por objetivo sin verificador independiente califica su propio trabajo — activa el verificador."),
        "loop.issue.vagueGoal": ("This \"done when\" may not be machine-checkable — name a test, build, or check the verifier can actually run.",
                                 "Este «terminado cuando» quizá no sea comprobable por una máquina — nombra un test, build o comprobación que el verificador pueda ejecutar de verdad."),

        // MARK: Health (cost per accepted change)
        "loop.health.title": ("Is this loop working?", "¿Funciona este bucle?"),
        "loop.health.subtitle": ("The metric that matters isn't turns or tokens — it's cost per accepted change. Below a 50% accept rate, you're doing the review the loop was meant to remove.",
                                 "La métrica que importa no son turnos ni tokens — es el coste por cambio aceptado. Por debajo del 50% de aceptación, estás haciendo la revisión que el bucle debía quitarte."),
        "loop.health.accepted": ("Accepted runs", "Ejecuciones aceptadas"),
        "loop.health.perAccepted": ("Cost per accepted change", "Coste por cambio aceptado"),
        "loop.health.warn": ("Fewer than half of the runs passed the verifier. Tighten the goal, the guardrails, or the model before running it again.",
                             "Menos de la mitad de las ejecuciones pasaron el verificador. Ajusta el objetivo, las barreras o el modelo antes de volver a ejecutarlo."),

        // MARK: "Is a loop worth it?" — the four conditions
        "loop.conditions.title": ("Is a loop worth it here?", "¿Merece la pena un bucle aquí?"),
        "loop.conditions.repeats": ("The task repeats — at least weekly. Below that, the setup never pays for itself.",
                                    "La tarea se repite — al menos cada semana. Por debajo de eso, el montaje nunca se amortiza."),
        "loop.conditions.autoFail": ("Something can fail the work automatically — a test, type check, lint, or build.",
                                     "Algo puede rechazar el trabajo automáticamente — un test, type check, lint o build."),
        "loop.conditions.budget": ("Your budget can absorb the waste — loops re-read context, retry, and explore.",
                                   "Tu presupuesto absorbe el desperdicio — los bucles releen contexto, reintentan y exploran."),
        "loop.conditions.tools": ("The agent has senior-engineer tools — logs, a repro environment, and the ability to run what it writes.",
                                  "El agente tiene herramientas de ingeniero senior — logs, un entorno de reproducción y poder ejecutar lo que escribe."),
        "loop.conditions.footnote": ("Good first loops are the boring ones: CI triage, dependency bumps, lint-and-fix. Save the interesting ones (rewrites, auth, payments) for when a human still weighs in.",
                                     "Los mejores primeros bucles son los aburridos: triage de CI, subir dependencias, lint-and-fix. Deja los interesantes (reescrituras, auth, pagos) para cuando aún decida un humano."),
    ]
}
