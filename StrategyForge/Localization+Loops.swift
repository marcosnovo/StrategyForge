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
        "loop.kind.turnBased.blurb": ("You steer each round: prompt, it works, a check reports back.",
                                      "Tú diriges cada ronda: pides, trabaja y una revisión te informa."),
        "loop.kind.turnBased.suits": ("Suits exploratory work where you decide the next step.",
                                      "Ideal para trabajo exploratorio donde tú decides el siguiente paso."),
        "loop.kind.goalBased": ("Goal loop", "Por objetivo"),
        "loop.kind.goalBased.blurb": ("You state what done means; an independent grader loops until it's met or the turn limit hits.",
                                      "Tú defines qué significa terminado; un evaluador independiente itera hasta cumplirlo o agotar los turnos."),
        "loop.kind.goalBased.suits": ("Suits tests-pass or bug-cleared tasks with a checkable finish line.",
                                      "Ideal para tareas tipo «los tests pasan» o «bug resuelto», con una meta comprobable."),
        "loop.kind.timeBased": ("Scheduled", "Programado"),
        "loop.kind.timeBased.blurb": ("Fires on a schedule: checks, reacts if needed, and waits for the next interval.",
                                      "Se dispara según un horario: comprueba, reacciona si hace falta y espera al siguiente intervalo."),
        "loop.kind.timeBased.suits": ("Good for recurring check-ins — a daily summary, a routine health check of your project.",
                                      "Ideal para tareas recurrentes — un resumen diario, una revisión rutinaria del estado de tu proyecto."),
        "loop.kind.proactive": ("Proactive", "Proactivo"),
        "loop.kind.proactive.blurb": ("Fires on events with no human online; every result gets reviewed.",
                                      "Se dispara con eventos sin nadie conectado; cada resultado se revisa."),
        "loop.kind.proactive.suits": ("Good for reacting to outside events — like when a build breaks or new work arrives.",
                                      "Ideal para reaccionar a eventos externos — como cuando algo se rompe o llega trabajo nuevo."),

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
        "loop.editor.goal.title": ("Goal", "Objetivo"),
        "loop.editor.goal.subtitle": ("The loop stops when this condition can be verified — not before, not on a hunch.",
                                      "El bucle se detiene cuando esta condición se puede verificar — ni antes, ni por intuición."),
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

        // MARK: Editor — diagram card
        "loop.editor.diagram.title": ("The cycle", "El ciclo"),
        "loop.editor.diagram.subtitle": ("What one pass of this loop looks like. The green stage is the exit.",
                                         "Así es una pasada de este bucle. La etapa verde es la salida."),

        // MARK: Editor — bottom bar
        "loop.editor.needRepo": ("Choose a target folder first — that's where the loop files are written.",
                                 "Elige primero una carpeta destino: ahí se escriben los archivos del bucle."),
        "loop.editor.chooseRepo": ("Choose folder…", "Elegir carpeta…"),
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
    ]
}
