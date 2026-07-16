//
//  Localization+Progress.swift
//  StrategyForge
//
//  Strings for the loop-progress visual language (LoopProgressView, LoopRunPanel,
//  LoopRunController status lines). Kept in their own table so the main string
//  catalog stays untouched. NOTE: `L10n.string(_:langCode:)` must consult this
//  table as a fallback (`strings[key] ?? progressStrings[key]`) for these keys
//  to resolve — see the integration note in the loop-runner work summary.
//

import Foundation

extension L10n {

    /// key → (English, Spanish) for the loop runner + progress visuals.
    static let progressStrings: [String: (en: String, es: String)] = [

        // MARK: Stage strip (Act → Verify → Done)
        "progress.stage.act": ("Act", "Actuar"),
        "progress.stage.verify": ("Verify", "Verificar"),
        "progress.stage.done": ("Done", "Hecho"),

        // MARK: One-line run status
        "progress.status.working": ("Working on the goal…", "Trabajando en el objetivo…"),
        "progress.status.verifying": ("Verifying against the goal…", "Verificando contra el objetivo…"),
        "progress.status.pass": ("Goal met — verified.", "Objetivo cumplido — verificado."),
        "progress.status.retry": ("Not there yet — starting another turn.", "Aún no — empezando otro turno."),
        "progress.status.outOfTurns": ("Ran out of turns before meeting the goal.", "Se acabaron los turnos antes de cumplir el objetivo."),
        "progress.status.overBudget": ("Stopped at the spend cap before meeting the goal.", "Se detuvo en el tope de gasto antes de cumplir el objetivo."),
        "progress.status.error": ("The run hit an error.", "La ejecución encontró un error."),
        "progress.status.doneUnverified": ("One pass finished (no verifier).", "Una pasada terminada (sin verificador)."),

        // MARK: Run panel
        "progress.run.title": ("Run this loop", "Ejecutar este bucle"),
        "progress.run.info": ("Runs Claude Code locally in your project folder: each turn does one step toward the goal, then an independent verifier judges the result. It stops on PASS or when it runs out of turns.",
                              "Ejecuta Claude Code en local en tu carpeta de proyecto: cada turno da un paso hacia el objetivo y luego un verificador independiente juzga el resultado. Se detiene con LOGRADO o al agotar los turnos."),
        "progress.run.button": ("Run loop", "Ejecutar bucle"),
        "progress.run.stop": ("Stop", "Detener"),
        "progress.run.again": ("Run again", "Ejecutar de nuevo"),
        "progress.run.chooseFolder": ("Choose a folder to run in", "Elige una carpeta donde ejecutar"),
        "progress.run.folder.hint": ("The loop reads and writes files here.",
                                     "El bucle lee y escribe archivos aquí."),
        "progress.run.workspace": ("Runs in a private workspace", "Se ejecuta en un espacio privado"),
        "progress.run.workspace.hint": ("No project needed. Pick a folder only if the loop should work inside your own code.",
                                        "No necesita proyecto. Elige una carpeta solo si el bucle debe trabajar dentro de tu propio código."),
        "progress.run.pickProject": ("Pick a project folder", "Elegir carpeta de proyecto"),
        "loop.iterations": ("Iterations", "Iteraciones"),
        "loop.iteration.n": ("Iteration %lld", "Iteración %lld"),
        "loop.finished.pass": ("Goal met — the loop passed.", "Objetivo cumplido — el bucle pasó."),
        "loop.finished.fail": ("Stopped without meeting the goal.", "Se detuvo sin cumplir el objetivo."),
        "loop.finished.unverified": ("Done (one pass, no verifier).", "Hecho (una pasada, sin verificador)."),
        "loop.finished.whatNow.folder": ("The loop edited files in your project folder — open it to review the changes (they're not committed unless worktree mode did it).",
                                         "El bucle editó archivos en tu carpeta de proyecto — ábrela para revisar los cambios (no están commiteados salvo que el modo worktree lo hiciera)."),
        "loop.finished.whatNow.workspace": ("The loop worked in its private workspace — open it to see what it produced.",
                                            "El bucle trabajó en su espacio privado — ábrelo para ver lo que produjo."),
        "loop.finished.reveal": ("Open folder", "Abrir carpeta"),
        "progress.run.needsRepo": ("Pick a project folder first — the loop needs somewhere to work.",
                                   "Elige primero una carpeta de proyecto — el bucle necesita dónde trabajar."),
        "progress.run.needsGoal": ("Write a goal first — the loop needs a “done when”.",
                                   "Escribe primero un objetivo — el bucle necesita un «terminado cuando»."),
        "progress.run.singlePass": ("Only goal-based loops iterate on their own — this kind runs a single pass.",
                                    "Solo los bucles por objetivo iteran por sí solos — este tipo hace una sola pasada."),
        "progress.run.tokens": ("%@ tokens", "%@ tokens"),
        "progress.run.elapsed": ("elapsed", "transcurrido"),

        // MARK: Verdict badge
        "progress.verdict.pass": ("PASS ✓", "LOGRADO ✓"),
        "progress.verdict.fail": ("STOPPED ✗", "DETENIDO ✗"),
    ]
}
