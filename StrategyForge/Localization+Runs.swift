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

        // MARK: Team catalog (WS-B)
        "rail.teamLibrary": ("Teams library", "Biblioteca"),
        "catalog.title": ("Team library", "Biblioteca de equipos"),
        "catalog.subtitle": (
            "Import a proven agent team in one click — or paste a GitHub ref to a shared .sfstrategy. Runs on your own plan, no backend.",
            "Importa un equipo de agentes probado en un clic — o pega una ref de GitHub a un .sfstrategy compartido. Corre sobre tu plan, sin backend."),
        "catalog.paste": ("owner/repo[@ref]#path/to/team.sfstrategy",
                          "owner/repo[@ref]#ruta/al/team.sfstrategy"),
        "catalog.verified": ("Verified by Coral", "Verificado por Coral"),
        "catalog.import": ("Import", "Importar"),
        "catalog.importEdit": ("Import & edit", "Importar y editar"),
        "catalog.source": ("Source", "Fuente"),
        "catalog.preview.subtitle": ("Preview before it lands in your library.",
                                     "Vista previa antes de guardarlo en tu biblioteca."),

        // MARK: Onboarding readiness (first-run)
        "onboard.ready.title": ("Your tools are ready", "Tus herramientas están listas"),
        "onboard.ready.setup": ("Connect a tool to run", "Conecta una herramienta para ejecutar"),
        "onboard.ready.connect": ("Set up tools", "Configurar herramientas"),
        "onboard.gatekeeper": (
            "First launch: macOS may say the app is from an unidentified developer — it's notarized. Right-click → Open, or allow it in System Settings ▸ Privacy & Security.",
            "Primer arranque: macOS puede decir que la app es de un desarrollador no identificado — está notarizada. Clic derecho → Abrir, o permítela en Ajustes del Sistema ▸ Privacidad y seguridad."),

        // MARK: Updates (Settings)
        "settings.updates": ("Updates", "Actualizaciones"),
        "settings.updates.current": ("Current version", "Versión actual"),
        "settings.updates.check": ("Check for updates", "Buscar actualizaciones"),
        "settings.updates.available": ("Update available: %@ — opening the download.",
                                       "Actualización disponible: %@ — abriendo la descarga."),
        "settings.updates.upToDate": ("You're on the latest version.", "Tienes la última versión."),
        "settings.updates.caption": (
            "Coral is distributed directly (notarized), so updates are downloaded from the web, not the App Store.",
            "Coral se distribuye directamente (notarizada), así que las actualizaciones se descargan de la web, no del App Store."),
    ]
}
