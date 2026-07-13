//
//  Localization+Runs.swift
//  StrategyForge
//
//  Strings for the run test-bench: re-tune suggestions from a finished run and the
//  two-run comparison sheet. Kept in its own dictionary so Localization.swift stays
//  small; merged into the resolver alongside the other feature tables.
//

import Foundation

extension L10n {

    static let runStrings: [String: (en: String, es: String)] = [

        // MARK: Re-tune suggestions
        "retune.title": ("Tune this team", "Afina este equipo"),
        "retune.subtitle": ("What this run tells you about the setup — one click to adjust.",
                            "Lo que este run dice sobre la configuración — un clic para ajustar."),
        // %@ = role name
        "retune.idleAgent": ("“%@” did no work this run — consider removing it, or make its description more action-oriented so the orchestrator delegates to it.",
                             "«%@» no hizo nada en este run — considera quitarlo, o haz su descripción más orientada a la acción para que el orquestador le delegue."),
        "retune.noDelegation": ("The orchestrator did everything solo — the team never split the work. Simplify to Solo, or sharpen each role's description so delegation triggers.",
                                "El orquestador lo hizo todo solo — el equipo no repartió el trabajo. Simplifica a Solo, o afina la descripción de cada rol para que se dispare la delegación."),
        // %1$@ = model name, %2$@ = percent
        "retune.costHog": ("%1$@ used %2$@ of the tokens — try a cheaper model for the roles on it.",
                           "%1$@ consumió el %2$@ de los tokens — prueba un modelo más barato para los roles que lo usan."),
        // %@ = cost
        "retune.expensiveRun": ("This run cost %@ — for routine work, try the Economy tier.",
                                "Este run costó %@ — para trabajo rutinario, prueba el nivel Económico."),

        // MARK: Compare two runs
        "compare.title": ("Compare runs", "Comparar runs"),
        "compare.subtitle": ("Two runs of the same team, side by side.",
                             "Dos runs del mismo equipo, lado a lado."),
        "compare.lastTwo": ("Compare last two runs", "Comparar los dos últimos runs"),
        "compare.runA": ("Baseline", "Referencia"),
        "compare.runB": ("Candidate", "Candidato"),
        "compare.metric.cost": ("Cost", "Coste"),
        "compare.metric.tokens": ("Tokens", "Tokens"),
        "compare.metric.steps": ("Steps", "Pasos"),
        "compare.metric.time": ("Time", "Tiempo"),
        "compare.perAgent": ("Per agent", "Por agente"),
        "compare.cheaper": ("cheaper", "más barato"),
        "compare.dearer": ("dearer", "más caro"),
        "compare.same": ("no change", "sin cambio"),
    ]
}
