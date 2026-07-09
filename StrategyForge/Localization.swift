//
//  Localization.swift
//  StrategyForge
//
//  Lightweight, model-backed localization with LIVE runtime switching.
//
//  Why not LocalizedStringKey / .strings? `LocalizedStringKey` resolves against
//  Bundle.main and ignores `\.environment(\.locale)`, so a runtime picker can't
//  reliably re-translate SwiftUI Text without a bundle swap. Instead, every
//  user-facing string is routed through `AppModel.t(_:)`. Because `AppModel` is
//  `@Observable` and injected via `.environment`, changing the language updates
//  every view that reads a string — instantly, with no relaunch.
//

import Foundation

/// The language the user picked. `.system` follows the OS language.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, en, es
    var id: String { rawValue }
}

enum L10n {

    /// key → (English, Spanish). English is also the fallback.
    static let strings: [String: (en: String, es: String)] = [

        // MARK: Common
        "common.cancel": ("Cancel", "Cancelar"),
        "common.done": ("Done", "Hecho"),
        "common.required": ("Required", "Obligatorio"),
        "common.choose": ("Choose…", "Elegir…"),

        // MARK: App / sidebar
        "app.purpose": (
            "Chat with a team of Claude agents you design — over a folder of code, documents or notes. Ask questions, review files, or run a task.",
            "Chatea con un equipo de agentes de Claude que tú diseñas — sobre una carpeta de código, documentos o notas. Pregunta, revisa archivos o lanza una tarea."),
        "sidebar.section": ("Configurations", "Configuraciones"),
        "sidebar.empty": ("No chats yet. Click + to start one.", "Aún no hay chats. Pulsa + para empezar uno."),
        "sidebar.new": ("New chat", "Nuevo chat"),
        "sidebar.chats": ("Chats", "Chats"),
        "inspector.config": ("Setup", "Configuración"),
        "sidebar.toggle": ("Show/hide sidebar", "Mostrar/ocultar barra lateral"),
        "inspector.toggle": ("Chat settings (strategy & files)", "Ajustes del chat (estrategia y archivos)"),
        "sidebar.settings": ("Settings", "Ajustes"),
        "sidebar.delete": ("Delete", "Eliminar"),
        "sidebar.deleteTitle": ("Delete this chat?", "¿Eliminar este chat?"),
        "sidebar.deleteMsg": ("This removes the chat and its history from this list. Files already written to your repo are not deleted.",
                              "Elimina el chat y su historial de esta lista. Los archivos ya escritos en tu repo no se borran."),

        // MARK: Onboarding
        "onboard.title": ("Welcome to StrategyForge", "Bienvenido a StrategyForge"),
        "onboard.intro": (
            "StrategyForge lets you chat with a team of Claude agents you design — over a folder of code, documents or notes. Ask questions, review files, or run a task.",
            "StrategyForge te deja chatear con un equipo de agentes de Claude que tú diseñas — sobre una carpeta de código, documentos o notas. Pregunta, revisa archivos o lanza una tarea."),
        "onboard.step1.title": ("1. Design your agent team", "1. Diseña tu equipo de agentes"),
        "onboard.step1.desc": ("Pick a strategy — how the agents work together — and which Claude model each role uses. This is what Claude Code alone can't do.",
                               "Elige una estrategia — cómo colaboran los agentes — y qué modelo de Claude usa cada rol. Esto es lo que Claude Code por sí solo no permite."),
        "onboard.step2.title": ("2. Point it at a folder", "2. Apúntalo a una carpeta"),
        "onboard.step2.desc": ("Any folder — a code repo, a set of documents, or notes. Claude works there.",
                               "Cualquier carpeta — un repo de código, un conjunto de documentos o notas. Claude trabaja ahí."),
        "onboard.step3.title": ("3. Chat", "3. Chatea"),
        "onboard.step3.desc": ("Ask a question, attach a file to review, or run a task. The team responds — and can edit files if you allow it.",
                               "Haz una pregunta, adjunta un archivo para revisar o lanza una tarea. El equipo responde — y puede editar archivos si lo permites."),
        "onboard.note": (
            "Runs Claude Code on your Mac with your normal plan (no API key). You choose how much it can do — from read-only to full autonomy.",
            "Ejecuta Claude Code en tu Mac con tu plan habitual (sin clave de API). Tú eliges cuánto puede hacer — de solo lectura a autonomía total."),
        "onboard.cta": ("Start my first chat", "Empezar mi primer chat"),
        "onboard.skip": ("Skip", "Omitir"),

        // MARK: Empty states
        "empty.editor.title": ("Start a chat with your own agent team", "Empieza un chat con tu equipo de agentes"),
        "empty.editor.desc": (
            "Design how a team of Claude agents works together, point it at a folder — code, documents or notes — and chat: ask questions, review files, or run a task.",
            "Diseña cómo trabaja en equipo un grupo de agentes de Claude, apúntalo a una carpeta — código, documentos o notas — y chatea: pregunta, revisa archivos o lanza una tarea."),
        "empty.preview.title": ("Nothing to preview yet", "Nada que previsualizar aún"),
        "empty.preview.desc": ("Select or create a configuration to preview the files it will write.",
                               "Selecciona o crea una configuración para previsualizar los archivos que escribirá."),

        // MARK: Editor
        "editor.t.name": ("Name this setup", "Nombra esta configuración"),
        "editor.advanced": ("Advanced — customize roles & models", "Avanzado — personaliza roles y modelos"),
        "editor.advanced.hint": ("The defaults work well. Open this only if you want to change models, counts, tools or prompts.",
                                 "Los valores por defecto funcionan bien. Ábrelo solo si quieres cambiar modelos, cantidades, herramientas o prompts."),
        "editor.t.strategy": ("Choose a strategy", "Elige una estrategia"),
        "editor.t.folder": ("Choose your project folder", "Elige la carpeta de tu proyecto"),
        "editor.repo.example": ("Must be a folder on your Mac — for example ~/Projects/my-app.",
                                "Debe ser una carpeta de tu Mac — por ejemplo ~/Proyectos/mi-app."),
        "editor.repo.willWrite": (
            "When you generate, StrategyForge writes .claude/agents/ and CLAUDE.md here automatically. Nothing to add to Xcode — Claude Code reads them from the folder (the .claude folder is hidden in Xcode, that's normal).",
            "Al generar, StrategyForge escribe aquí .claude/agents/ y CLAUDE.md automáticamente. No hay que añadir nada a Xcode — Claude Code los lee de la carpeta (la carpeta .claude no aparece en Xcode, es normal)."),
        "editor.repo.helpButton": ("Which folder?", "¿Qué carpeta?"),
        "editor.repo.helpTitle": ("Which folder should I choose?", "¿Qué carpeta elijo?"),
        "editor.repo.helpBody": (
            """
            • It must be a folder on your Mac (local).

            • Choose the root of the coding project you want to work on with Claude Code — the same folder you'd open in Terminal and run `claude` in.

            • Working in Xcode? Choose the folder that contains your .xcodeproj (the project root). Already use Claude Code? It's the same folder where you run `claude`.

            • StrategyForge writes only two things inside it: a `.claude/agents/` folder (one file per agent) and a `CLAUDE.md` file. It never changes or deletes your code.

            • No project yet? Create an empty folder anywhere and pick that — you can try it there.
            """,
            """
            • Debe ser una carpeta de tu Mac (local).

            • Elige la raíz del proyecto de código con el que quieras trabajar en Claude Code — la misma carpeta que abrirías en la Terminal para ejecutar `claude`.

            • ¿Trabajas en Xcode? Elige la carpeta que contiene tu .xcodeproj (la raíz del proyecto). ¿Ya usas Claude Code? Es la misma carpeta donde ejecutas `claude`.

            • StrategyForge escribe ahí solo dos cosas: una carpeta `.claude/agents/` (un archivo por agente) y un archivo `CLAUDE.md`. Nunca cambia ni borra tu código.

            • ¿Aún no tienes un proyecto? Crea una carpeta vacía en cualquier sitio y elígela — puedes probarlo ahí.
            """),
        "editor.t.roles": ("Assign models to roles", "Asigna modelos a los roles"),
        "editor.diagramTitle": ("Team diagram", "Diagrama del equipo"),
        "editor.name.placeholder": ("e.g. Backend refactor team", "p. ej. Equipo de refactor backend"),
        "editor.strategy.help": ("A strategy is the shape of your agent team — how the work is split up.",
                                 "Una estrategia es la forma del equipo: cómo se reparte el trabajo."),
        "editor.roles.help": (
            "Each row is one Claude assistant. The orchestrator is your main Claude Code session; the others are subagents it delegates to. The defaults work well — you can leave them as they are.",
            "Cada fila es un asistente de Claude. El orquestador es tu sesión principal de Claude Code; los demás son subagentes a los que delega. Los valores por defecto funcionan bien: puedes dejarlos tal cual."),
        "editor.diagram.note": ("Single level of delegation: subagents report back to the orchestrator and never talk to each other.",
                                "Un solo nivel de delegación: los subagentes reportan al orquestador y nunca hablan entre sí."),
        "editor.repo.subtitle": ("Pick the folder of the coding project you want to use with Claude Code — the same folder you'd open in Terminal. StrategyForge saves the team's setup inside it and doesn't touch anything else.",
                                 "Elige la carpeta del proyecto de código que quieras usar con Claude Code — la misma que abrirías en la Terminal. StrategyForge guarda ahí la configuración del equipo y no toca nada más."),
        "editor.repo.empty": ("No folder chosen — pick your project root", "Sin carpeta — elige la raíz de tu proyecto"),
        "editor.save": ("Save", "Guardar"),
        "editor.save.help": ("Keep this setup in the sidebar. This does not write any files.",
                             "Guarda esta configuración en la barra lateral. No escribe ningún archivo."),
        "editor.valid": ("Everything looks good — ready to generate.", "Todo correcto: listo para generar."),

        // MARK: Cost estimate
        "cost.perRun": ("≈ %@ / run", "≈ %@ / ejecución"),
        "cost.tier.low": ("Low cost", "Coste bajo"),
        "cost.tier.medium": ("Medium cost", "Coste medio"),
        "cost.tier.high": ("High cost", "Coste alto"),
        "cost.title": ("Estimated cost", "Coste estimado"),
        "cost.byModel": ("By model", "Por modelo"),
        "cost.disclaimer": (
            "Rough estimate for one medium task, using approximate token prices ($/M in+out). Real cost depends on your task, effort and plan — Solo and read-only teams are cheapest; big teams and top-tier models cost more.",
            "Estimación aproximada para una tarea media, con precios de tokens aproximados ($/M entrada+salida). El coste real depende de tu tarea, el esfuerzo y tu plan — En solitario y los equipos de solo lectura son lo más barato; los equipos grandes y los modelos top cuestan más."),

        // MARK: Preview panel
        "preview.title": ("Preview", "Vista previa"),
        "action.preview": ("Preview files", "Ver archivos"),
        "action.terminal": ("Terminal", "Terminal"),
        "action.commit": ("Generate, commit & push", "Generar, commit y push"),
        "action.commit.help": ("Write the files, then run git add + commit + push in Terminal — versions the config and sends it to your remote (e.g. GitHub).",
                               "Escribe los archivos y ejecuta git add + commit + push en Terminal — versiona la config y la envía a tu remoto (p. ej. GitHub)."),
        "preview.sheetTitle": ("Files & launch command", "Archivos y comando de lanzamiento"),
        "preview.filesHeader": ("Files to be created", "Archivos que se crearán"),
        "preview.filesCaptionNoRepo": ("Choose a target folder to see exactly where these go.",
                                       "Elige una carpeta destino para ver dónde van exactamente."),
        "preview.filesCaption": ("Preview of what will be written into %@.", "Vista previa de lo que se escribirá en %@."),
        "preview.launch": ("Launch command", "Comando de lanzamiento"),
        "preview.launch.caption": ("After generating, run this in your project folder to start Claude Code with the orchestrator's model.",
                                   "Tras generar, ejecútalo en la carpeta de tu proyecto para iniciar Claude Code con el modelo del orquestador."),
        "preview.copy.help": ("Copy launch command", "Copiar comando de lanzamiento"),
        "preview.dismiss": ("Dismiss", "Descartar"),
        "preview.generate": ("Generate files", "Generar archivos"),
        "preview.generate.help": ("Write the config files into your target folder.",
                                  "Escribe los archivos de configuración en tu carpeta destino."),
        "preview.generateTerminal": ("Generate & open Terminal", "Generar y abrir Terminal"),
        "preview.generateTerminal.help": ("Write the files, then open Terminal at the folder with the launch command copied, ready to paste.",
                                          "Escribe los archivos y abre Terminal en la carpeta con el comando copiado, listo para pegar."),
        "preview.needRepo": ("Choose a target folder first — that's where these files are written.",
                             "Elige primero una carpeta destino: ahí se escriben estos archivos."),
        "preview.needRepo.button": ("Choose folder…", "Elegir carpeta…"),
        "preview.fixErrors": ("Fix the highlighted issues in the editor before generating.",
                              "Corrige los problemas marcados en el editor antes de generar."),
        "preview.overwriteTitle": ("Overwrite existing files?", "¿Sobrescribir archivos existentes?"),
        "preview.overwriteMsg": ("These files already exist and will be overwritten:\n%@\n\nCLAUDE.md is merged, not overwritten.",
                                 "Estos archivos ya existen y se sobrescribirán:\n%@\n\nCLAUDE.md se combina, no se sobrescribe."),
        "preview.overwrite": ("Overwrite", "Sobrescribir"),

        // MARK: Banners
        "banner.needRepo": ("Choose a target folder first (step 3 in the editor).",
                            "Elige primero una carpeta destino (paso 3 del editor)."),
        "banner.needValid": ("Fix the validation errors before generating.",
                             "Corrige los errores de validación antes de generar."),
        "banner.wrote": ("Wrote %lld files to “%@”. Next: run the launch command in that folder.",
                         "Se escribieron %lld archivos en «%@». Ahora: ejecuta el comando de lanzamiento en esa carpeta."),
        "banner.writeFailed": ("Couldn’t write files: %@", "No se pudieron escribir los archivos: %@"),
        "banner.saved": ("Configuration saved.", "Configuración guardada."),
        "banner.saveFailed": ("Couldn’t save: %@", "No se pudo guardar: %@"),
        "banner.copied": ("Launch command copied.", "Comando de lanzamiento copiado."),
        "banner.terminalOK": ("Files written. Launch command copied — paste it in Terminal.",
                              "Archivos escritos. Comando copiado: pégalo en Terminal."),
        "banner.terminalRunning": ("Files written — the command is now running in Terminal.",
                                   "Archivos escritos — el comando se está ejecutando en Terminal."),
        "banner.terminalCopied": ("Files written. Launch command copied to the clipboard.",
                                  "Archivos escritos. Comando copiado al portapapeles."),
        "banner.terminalFailed": ("Files written, but Terminal could not be opened. The command is on the clipboard.",
                                  "Archivos escritos, pero no se pudo abrir Terminal. El comando está en el portapapeles."),

        // MARK: Settings
        "settings.repos": ("Repositories", "Repositorios"),
        "settings.defaultFolder": ("Default folder", "Carpeta por defecto"),
        "settings.defaultFolder.caption": ("Pre-selected when you pick a target folder for a configuration.",
                                           "Se preselecciona al elegir la carpeta destino de una configuración."),
        "settings.notSet": ("Not set", "Sin definir"),
        "settings.claudeSection": ("Claude Code", "Claude Code"),
        "settings.binary": ("`claude` command", "Comando `claude`"),
        "settings.binary.caption": ("Leave as `claude` unless Claude Code was installed in a custom location.",
                                    "Déjalo como `claude` salvo que Claude Code esté en una ruta personalizada."),
        "settings.languageSection": ("Language", "Idioma"),
        "settings.language": ("App language", "Idioma de la app"),
        "settings.language.system": ("System", "Sistema"),

        // MARK: Roles
        "role.systemPrompt": ("Instructions…", "Instrucciones…"),
        "role.description": ("When to use…", "Cuándo usarlo…"),
        "role.toolsAll": ("All", "Todas"),
        "role.toolsCount": ("%lld selected", "%lld"),
        "role.inheritAll": ("Use all tools (recommended)", "Usar todas las herramientas (recomendado)"),
        "role.tools.help": ("Restrict which tools this subagent can use. Empty means it can use all of them.",
                            "Restringe qué herramientas puede usar este subagente. Vacío = puede usar todas."),
        "role.orchestratorNote": ("This model is the launch model (documented in CLAUDE.md), not a per-file setting.",
                                  "Este modelo es el de lanzamiento (documentado en CLAUDE.md), no un ajuste por archivo."),
        "role.count.orchestratorHelp": ("The orchestrator is always a single instance.",
                                        "El orquestador es siempre una única instancia."),
        "role.namePlaceholder": ("name", "nombre"),
        "sheet.systemPrompt.subtitle": ("What this assistant should do. This becomes the body of its .md file.",
                                        "Lo que debe hacer este asistente. Es el cuerpo de su archivo .md."),
        "sheet.description.subtitle": ("When the orchestrator should hand work to this assistant. Be specific and action-oriented — this is what triggers delegation.",
                                       "Cuándo el orquestador debe pasarle trabajo a este asistente. Sé específico y orientado a la acción: esto es lo que dispara la delegación."),

        "field.model": ("Model", "Modelo"),
        "field.instances": ("Instances", "Instancias"),
        "field.tools": ("Tools", "Herramientas"),
        "field.name": ("Name", "Nombre"),

        // MARK: Role kinds (UI badges)
        "role.kind.orchestrator": ("Orchestrator", "Orquestador"),
        "role.kind.worker": ("Worker", "Trabajador"),
        "role.kind.advisor": ("Advisor", "Asesor"),
        "role.kind.reviewer": ("Reviewer", "Revisor"),
        "role.kind.planner": ("Planner", "Planificador"),
        "role.kind.researcher": ("Researcher", "Investigador"),
        "role.kind.specialist": ("Specialist", "Especialista"),

        // MARK: Strategy names + descriptions
        "strat.fanout.name": ("Orchestrator + Workers (Fan-out)", "Orquestador + Trabajadores (reparto)"),
        "strat.fanout.desc": ("One orchestrator plans and splits the task into parallel slices; N identical workers each take a slice and report back.",
                              "Un orquestador planifica y divide la tarea en partes paralelas; N trabajadores idénticos toman una parte cada uno y reportan."),
        "strat.execadv.name": ("Executor + Advisor", "Ejecutor + Asesor"),
        "strat.execadv.desc": ("The executor (main session) does the work every turn and, when it needs high-level guidance, consults a read-only advisor.",
                               "El ejecutor (sesión principal) hace el trabajo en cada turno y, cuando necesita orientación de alto nivel, consulta a un asesor de solo lectura."),
        "strat.planner.name": ("Planner → Implementers → Reviewer", "Planificador → Implementadores → Revisor"),
        "strat.planner.desc": ("The orchestrator plans, delegates implementation to N implementers, then invokes a read-only reviewer on the result.",
                               "El orquestador planifica, delega la implementación en N implementadores y luego invoca a un revisor de solo lectura sobre el resultado."),
        "strat.domain.name": ("Domain Specialists", "Especialistas por dominio"),
        "strat.domain.desc": ("The orchestrator routes work to fixed specialists — e.g. backend, frontend, security, or research, writing, data.",
                              "El orquestador reparte el trabajo a especialistas fijos — p. ej. backend, frontend, seguridad, o investigación, redacción, datos."),
        "strat.research.name": ("Research Fan-out", "Investigación en paralelo"),
        "strat.research.desc": ("The orchestrator dispatches N read-only researchers to explore different areas — of a codebase or a document set — in parallel and summarize.",
                                "El orquestador despacha N investigadores de solo lectura para explorar en paralelo distintas áreas — de un código o un conjunto de documentos — y resumir."),
        "strat.debate.name": ("Debate / Consensus (mediated)", "Debate / Consenso (mediado)"),
        "strat.debate.desc": ("A moderator orchestrator collects arguments from N agents holding different positions and synthesizes a consensus over rounds.",
                              "Un orquestador moderador recoge argumentos de N agentes con posturas distintas y sintetiza un consenso en varias rondas."),
        "strat.sparring.name": ("Sparring (builder vs breaker)", "Sparring (constructor vs rompedor)"),
        "strat.sparring.desc": ("A builder implements; an adversarial breaker writes failing tests to expose weaknesses. The orchestrator mediates and decides over rounds until the code holds.",
                                "Un constructor implementa; un rompedor adversario escribe tests que fallan para exponer debilidades. El orquestador media y decide en rondas hasta que el código aguanta."),
        "strat.solo.name": ("Solo (baseline)", "En solitario (base)"),
        "strat.solo.desc": ("A single agent with no subagents — a baseline to compare cost and quality against multi-agent strategies.",
                            "Un único agente sin subagentes: una base para comparar coste y calidad frente a estrategias multiagente."),

        // MARK: Beginner — good-for / not-for + badge
        "strat.badge.beginner": ("Beginner-friendly", "Fácil para empezar"),
        "strat.goodfor": ("Good for", "Ideal para"),
        "strat.notfor": ("Not for", "No ideal para"),
        "strat.fanout.good": ("one big job you can split into independent chunks done at the same time.", "un trabajo grande que puedes dividir en partes independientes hechas a la vez."),
        "strat.fanout.not": ("small tasks, or work where each step depends on the last.", "tareas pequeñas o trabajo donde cada paso depende del anterior."),
        "strat.execadv.good": ("everyday work where you occasionally want a second opinion. A safe first choice.", "trabajo diario en el que a veces quieres una segunda opinión. Una primera opción segura."),
        "strat.execadv.not": ("large jobs you want done in parallel.", "trabajos grandes que quieres hacer en paralelo."),
        "strat.planner.good": ("multi-part work worth planning first, doing, then double-checking.", "trabajo de varias partes que merece planificar, hacer y luego revisar."),
        "strat.planner.not": ("quick one-off changes.", "cambios rápidos y puntuales."),
        "strat.domain.good": ("work with clear areas — e.g. backend/frontend/security, or research/writing/data.", "trabajo con áreas claras — p. ej. backend/frontend/seguridad, o investigación/redacción/datos."),
        "strat.domain.not": ("small jobs where one assistant is plenty.", "trabajos pequeños donde basta un asistente."),
        "strat.research.good": ("understanding or exploring a codebase or a set of documents without changing anything.", "entender o explorar un código o un conjunto de documentos sin cambiar nada."),
        "strat.research.not": ("actually making changes.", "hacer cambios de verdad."),
        "strat.debate.good": ("a hard decision where you want several viewpoints weighed. Advanced.", "una decisión difícil donde quieres sopesar varias opiniones. Avanzado."),
        "strat.debate.not": ("routine work — it's slower and costs more.", "trabajo rutinario — es más lento y cuesta más."),
        "strat.sparring.good": ("making important work more robust by stress-testing it with a tough critic. Advanced.", "hacer más robusto un trabajo importante poniéndolo a prueba con un crítico duro. Avanzado."),
        "strat.sparring.not": ("simple or throwaway work.", "trabajo simple o desechable."),
        "strat.solo.good": ("small tasks or trying the app out. One assistant — simplest and cheapest.", "tareas pequeñas o probar la app. Un asistente — lo más simple y barato."),
        "strat.solo.not": ("large jobs that benefit from a team.", "trabajos grandes que se benefician de un equipo."),

        // MARK: Glossary (plain-language analogies)
        "glossary.strategy": ("Strategy = the shape of your team. It decides how many Claude assistants you get and how they split the work.",
                              "Estrategia = la forma de tu equipo. Decide cuántos asistentes de Claude tienes y cómo se reparten el trabajo."),
        "glossary.orchestrator": ("Orchestrator = the team lead. The main Claude you talk to: it plans, hands pieces to the helpers, and puts their results together.",
                                  "Orquestador = el jefe de equipo. El Claude principal con el que hablas: planifica, reparte tareas a los ayudantes y junta sus resultados."),
        "glossary.worker": ("Helpers (subagents) = assistants the team lead hands work to. Each does one piece and reports back — they don't talk to each other or to you directly.",
                            "Ayudantes (subagentes) = asistentes a los que el jefe pasa trabajo. Cada uno hace una parte y reporta — no hablan entre sí ni contigo directamente."),
        "glossary.model": ("Model = which \"brain\" an assistant uses. Bigger = smarter but pricier; smaller = faster and cheaper. The defaults are a good balance.",
                           "Modelo = qué \"cerebro\" usa un asistente. Más grande = más listo pero más caro; más pequeño = más rápido y barato. Los valores por defecto son un buen equilibrio."),

        // MARK: "What will happen" summary
        "summary.willHappen": ("This creates a team of %lld Claude assistants for “%@” and writes %lld setup files. It doesn't run anything or cost anything — you launch Claude yourself afterward.",
                               "Esto crea un equipo de %lld asistentes de Claude para «%@» y escribe %lld archivos de configuración. No ejecuta nada ni cuesta nada: tú lanzas Claude después."),
        "summary.willHappen.solo": ("This sets up a single Claude assistant for “%@” and writes %lld setup files. It doesn't run anything or cost anything — you launch Claude yourself afterward.",
                                    "Esto configura un único asistente de Claude para «%@» y escribe %lld archivos. No ejecuta nada ni cuesta nada: tú lanzas Claude después."),

        // MARK: Help-me-choose wizard
        "wizard.open": ("Help me choose", "Ayúdame a elegir"),
        "wizard.title": ("Let's find the right setup", "Encontremos la configuración adecuada"),
        "wizard.subtitle": ("Answer one or two quick questions. You can change everything later.", "Responde una o dos preguntas rápidas. Podrás cambiarlo todo después."),
        "wizard.q1": ("What do you want to do right now?", "¿Qué quieres hacer ahora mismo?"),
        "wizard.q1.build": ("Build or fix something in my project", "Crear o arreglar algo en mi proyecto"),
        "wizard.q1.understand": ("Understand code I don't know yet", "Entender código que aún no conozco"),
        "wizard.q1.bulk": ("Make lots of similar changes at once", "Hacer muchos cambios parecidos a la vez"),
        "wizard.q1.play": ("Just experiment and see how it works", "Solo experimentar y ver cómo funciona"),
        "wizard.q2": ("How careful should the team be?", "¿Cuánto cuidado debe tener el equipo?"),
        "wizard.q2.simple": ("Keep it simple — one assistant, with advice when needed", "Sencillo — un asistente, con consejo cuando haga falta"),
        "wizard.q2.careful": ("Plan it first, then double-check the result", "Planificar primero y luego revisar el resultado"),
        "wizard.result": ("We suggest", "Te sugerimos"),
        "wizard.why": ("Why", "Por qué"),
        "wizard.apply": ("Use this strategy", "Usar esta estrategia"),
        "wizard.back": ("Back", "Atrás"),

        // MARK: "What now?" post-generate
        "whatnow.title": ("Done! Your team's files are written.", "¡Listo! Los archivos de tu equipo están escritos."),
        "whatnow.lead": ("Here's how to start it:", "Así lo arrancas:"),
        "whatnow.step1": ("Open Terminal in your project and start Claude Code.", "Abre la Terminal en tu proyecto e inicia Claude Code."),
        "whatnow.step1.button": ("Open Terminal & start", "Abrir Terminal e iniciar"),
        "whatnow.step2": ("Or copy the launch command and run it yourself:", "O copia el comando de lanzamiento y ejecútalo tú:"),
        "whatnow.explain.toggle": ("What just happened?", "¿Qué acaba de pasar?"),
        "whatnow.explain.body": ("StrategyForge added two things to your folder: a .claude/agents folder describing each teammate, and a CLAUDE.md with the instructions. Claude Code reads these automatically. Nothing runs on its own — you're always in control.",
                                 "StrategyForge añadió dos cosas a tu carpeta: una carpeta .claude/agents que describe a cada compañero y un CLAUDE.md con las instrucciones. Claude Code las lee automáticamente. Nada se ejecuta solo: siempre tienes el control."),
        "whatnow.showFiles": ("Show me the files", "Ver los archivos"),

        // MARK: One-click / sample folder
        "setup.oneClick": ("Set up my team", "Configura mi equipo"),
        "setup.oneClick.sub": ("We'll pick a proven setup and the right models for you. You can change anything later.", "Elegimos una configuración probada y los modelos adecuados por ti. Podrás cambiarlo todo después."),
        "setup.defaultName": ("My first team", "Mi primer equipo"),
        "setup.sample": ("Try it in a sample folder", "Probar en una carpeta de ejemplo"),
        "setup.sample.sub": ("Creates a safe practice project — nothing of yours is touched.", "Crea un proyecto de práctica seguro — no se toca nada tuyo."),

        // MARK: Download single .md (for the Claude app / chat)
        "action.download": ("Download as one .md (for the Claude app)", "Descargar como un .md (para la app de Claude)"),
        "action.download.help": ("Save the whole strategy as a single Markdown file. Drag it into a Claude chat and Claude will act as this team — no Terminal or repo needed.",
                                 "Guarda toda la estrategia en un único archivo Markdown. Arrástralo a un chat de Claude y Claude actuará como este equipo — sin Terminal ni repo."),
        "action.copyPrompt": ("Copy starter prompt", "Copiar prompt de inicio"),
        "banner.downloaded": ("Saved the strategy as a single .md — drag it into a Claude chat.", "Estrategia guardada como un único .md — arrástralo a un chat de Claude."),
        "banner.promptCopied": ("Starter prompt copied — paste it into Claude.", "Prompt de inicio copiado — pégalo en Claude."),
        "editor.strategy.choose": ("Choose a shape", "Elige una forma"),

        // MARK: Strategy "best for" — task tags (all) + copy for the 3 new strategies
        "picker.bestfor": ("Best for", "Ideal para"),
        "picker.bucket.write": ("Write & create", "Escribir y crear"),
        "picker.bucket.understand": ("Understand & explain", "Entender y explicar"),
        "picker.bucket.code": ("Code & build", "Programar y construir"),
        "picker.bucket.faster": ("Work faster", "Trabajar más rápido"),
        "picker.bucket.decide": ("Decide well", "Decidir mejor"),
        "picker.bucket.pressure": ("Pressure-test", "Poner a prueba"),
        "picker.recommended": ("Recommended", "Recomendada"),
        "picker.otherStrategies": ("Other strategies", "Otras estrategias"),
        "strat.fanout.tag": ("Parallel work", "En paralelo"),
        "strat.execadv.tag": ("Guided work", "Con guía"),
        "strat.scout.tag": ("Explore first", "Explora antes"),
        "strat.triage.tag": ("Route by cost", "Enruta por coste"),
        "strat.planner.tag": ("Plan & deliver", "Planifica y entrega"),
        "strat.rootcause.tag": ("Diagnose", "Diagnosticar"),
        "strat.domain.tag": ("By specialty", "Por especialidad"),
        "strat.research.tag": ("Explore", "Explorar"),
        "strat.debate.tag": ("Decision", "Decisión"),
        "strat.sparring.tag": ("Stress-test", "Poner a prueba"),
        "strat.solo.tag": ("Quick task", "Tarea rápida"),

        "strat.scout.name": ("Scout → Act (cost-gated)", "Explorador → Acción (por coste)"),
        "strat.scout.desc": ("A cheap scout maps the terrain first; then an implementer acts on a precise brief — so expensive tokens go to the change, not exploration.",
                             "Un explorador barato mapea el terreno primero; luego un implementador actúa sobre un brief preciso — así los tokens caros van al cambio, no a explorar."),
        "strat.scout.good": ("Work in unfamiliar material, where exploring cheaply first saves tokens.",
                             "Trabajo en material desconocido, donde explorar barato primero ahorra tokens."),
        "strat.scout.not": ("Tiny changes in code you already know well.",
                            "Cambios pequeños en código que ya conoces bien."),
        "strat.triage.name": ("Triage Router (cost-tiered)", "Enrutador por triaje (por coste)"),
        "strat.triage.desc": ("A cheap triager classifies each request; work is routed proportionally — routine to a mid worker, only genuinely hard work to a top specialist.",
                              "Un triador barato clasifica cada petición; el trabajo se enruta proporcionalmente — lo rutinario a un trabajador medio, solo lo difícil a un especialista top."),
        "strat.triage.good": ("Mixed queues where cost should scale with each request's difficulty.",
                              "Colas mixtas donde el coste debe escalar con la dificultad de cada tarea."),
        "strat.triage.not": ("A single, well-defined task.",
                             "Una única tarea bien definida."),
        "strat.rootcause.name": ("Root-Cause Debugging", "Depuración de causa raíz"),
        "strat.rootcause.desc": ("Reproduce and gather evidence, rank hypotheses, apply the minimal fix for the real cause, then confirm — never mask the symptom.",
                                 "Reproduce y reúne evidencia, ordena hipótesis, aplica el arreglo mínimo de la causa real y confirma — nunca enmascara el síntoma."),
        "strat.rootcause.good": ("Stubborn problems you must trace to the real root cause, not the symptom.",
                                 "Problemas persistentes que hay que rastrear hasta la causa raíz, no el síntoma."),
        "strat.rootcause.not": ("Quick changes or producing something new.",
                                "Cambios rápidos o producir algo nuevo."),

        // MARK: Import / export / retention / lint
        "config.copySuffix": ("copy", "copia"),
        "config.duplicate": ("Duplicate", "Duplicar"),
        "config.regenerate": ("Re-generate files", "Regenerar archivos"),
        "config.lastGenerated": ("Generated %@", "Generado %@"),
        "config.neverGenerated": ("Not generated yet", "Sin generar todavía"),
        "import.repo": ("Import from a repo…", "Importar de un repo…"),
        "import.pickMessage": ("Choose a repo that already has a .claude/ setup to import it as an editable strategy.",
                               "Elige un repo que ya tenga una configuración .claude/ para importarla como estrategia editable."),
        "import.notFound": ("No .claude/agents or CLAUDE.md found in that folder.", "No se encontró .claude/agents ni CLAUDE.md en esa carpeta."),
        "import.done": ("Imported a strategy with %lld subagents.", "Importada una estrategia con %lld subagentes."),
        "doc.export": ("Export strategy (.sfstrategy)…", "Exportar estrategia (.sfstrategy)…"),
        "doc.import": ("Import strategy (.sfstrategy)…", "Importar estrategia (.sfstrategy)…"),
        "doc.exported": ("Strategy exported.", "Estrategia exportada."),
        "doc.imported": ("Strategy imported.", "Estrategia importada."),
        "doc.importFailed": ("Couldn’t import that file: %@", "No se pudo importar ese archivo: %@"),
        "lint.title": ("Checks", "Comprobaciones"),
        "lint.fixAll": ("Fix automatically", "Arreglar automáticamente"),
        "lint.fixedAll": ("Applied automatic fixes.", "Se aplicaron los arreglos automáticos."),
        "picker.header": ("Strategy", "Estrategia"),

        // MARK: Chat (headless Claude Code)
        "chat.open": ("Work here (chat)", "Trabajar aquí (chat)"),
        "chat.title": ("Chat", "Chat"),
        "chat.subtitle": ("Claude works in %@ using this strategy.", "Claude trabaja en %@ con esta estrategia."),
        "chat.placeholder": ("Ask anything, or attach a file to review…", "Pregunta lo que sea, o adjunta un archivo para revisar…"),
        "chat.send": ("Send", "Enviar"),
        "chat.stop": ("Stop", "Parar"),
        "chat.thinking": ("Working…", "Trabajando…"),
        "chat.using": ("Using: %@", "Usando: %@"),
        "chat.empty": ("Ask a question, review a document, or start a task. Claude works here with the team you designed, in the folder you chose.",
                       "Haz una pregunta, revisa un documento o empieza una tarea. Claude trabaja aquí con el equipo que diseñaste, en la carpeta que elegiste."),
        "chat.needRepo": ("Choose a folder in Chat settings.", "Elige una carpeta en Ajustes del chat."),
        "chat.scratch": ("Scratch folder (no project)", "Carpeta temporal (sin proyecto)"),
        "chat.untitled": ("New chat", "Nuevo chat"),
        "chat.settings": ("Chat settings", "Ajustes del chat"),
        "chat.noMessages": ("No messages yet", "Aún sin mensajes"),
        "chat.noRepo": ("No folder yet", "Sin carpeta todavía"),
        "chat.copy": ("Copy", "Copiar"),
        "chat.tokens": ("%@ tokens", "%@ tokens"),
        "chat.tokens.help": ("Approximate tokens used in this chat", "Tokens aproximados usados en este chat"),
        "chat.changedFiles": ("%lld files changed", "%lld archivos modificados"),
        "chat.reveal": ("Reveal in Finder", "Mostrar en Finder"),
        "chat.download": ("Download", "Descargar"),
        "chat.team.ready": ("YOUR TEAM IS READY", "TU EQUIPO ESTÁ LISTO"),
        "chat.team.count": ("Orchestrator + %lld teammates", "Orquestador + %lld compañeros"),
        "chat.team.solo": ("A single agent handles everything", "Un solo agente lo hace todo"),
        "chat.delegating": ("Orchestrator → %@", "Orquestador → %@"),
        "chat.denied": ("Needed permission for: %@", "Necesitó permiso para: %@"),
        "chat.allowRetry": ("Allow all & retry", "Permitir y reintentar"),
        "chat.attach": ("Attach files for Claude to review", "Adjuntar archivos para que Claude los revise"),
        "chat.suggest1": ("Review the files here and give me feedback", "Revisa los archivos de aquí y dame feedback"),
        "chat.suggest2": ("Summarize this into key points", "Resume esto en puntos clave"),
        "chat.suggest3": ("Explain how this works, step by step", "Explica cómo funciona esto, paso a paso"),
        "chat.activity": ("Activity", "Actividad"),
        "chat.activity.help": ("Show what the agents are doing", "Ver qué están haciendo los agentes"),

        // MARK: Agent activity panel
        "activity.title": ("AGENT ACTIVITY", "ACTIVIDAD DE AGENTES"),
        "activity.running": ("Working", "Trabajando"),
        "activity.orchestrator": ("Orchestrator", "Orquestador"),
        "activity.viaOrchestrator": ("via orchestrator", "vía orquestador"),
        "activity.tasks": ("TASKS", "TAREAS"),
        "activity.steps": ("TIMELINE", "CRONOLOGÍA"),
        "activity.empty": ("Steps will appear here as the agents work.", "Los pasos aparecerán aquí según trabajen los agentes."),
        "activity.team": ("TEAM", "EQUIPO"),
        "activity.agentDetail": ("Agent activity", "Actividad del agente"),
        "activity.active": ("active", "activo"),
        "activity.done": ("done", "hecho"),
        "activity.soloNote": ("The orchestrator is handling this itself — it delegates to teammates only when the task needs it.",
                              "El orquestador lo está haciendo por sí mismo — delega en compañeros solo cuando la tarea lo requiere."),
        // Humanized step phrases (%@ = target)
        "act.reading": ("Reading %@", "Leyendo %@"),
        "act.editing": ("Editing %@", "Editando %@"),
        "act.writing": ("Writing %@", "Escribiendo %@"),
        "act.running": ("Running %@", "Ejecutando %@"),
        "act.searching": ("Searching %@", "Buscando %@"),
        "act.fetching": ("Fetching %@", "Consultando %@"),
        "act.planning": ("Planning tasks", "Planificando tareas"),
        "act.using": ("Using %@", "Usando %@"),
        "act.delegated": ("Delegated to %@", "Delegó en %@"),

        // MARK: Document preview
        "filepreview.title": ("Files produced", "Archivos generados"),
        "filepreview.none": ("Select a file to preview.", "Selecciona un archivo para previsualizar."),
        "filepreview.open": ("Open", "Abrir"),
        "filepreview.save": ("Save a copy…", "Guardar una copia…"),
        "autonomy.acceptEdits": ("Accept edits", "Aceptar ediciones"),
        "autonomy.full": ("Full autonomy", "Autonomía total"),
        "autonomy.plan": ("Plan only (read-only)", "Solo planificar (solo lectura)"),
        "settings.autonomy": ("Chat autonomy", "Autonomía del chat"),
        "settings.autonomy.section": ("Chat", "Chat"),
        "settings.autonomy.caption": ("How much the chat may do without asking. In chat there's no way to approve prompts, so pick up front. “Accept edits” lets it write/edit files; “Full autonomy” also runs shell commands (mkdir, git…); “Plan only” never modifies anything.",
                                      "Cuánto puede hacer el chat sin preguntar. En el chat no hay forma de aprobar permisos, así que se elige de antemano. “Aceptar ediciones” le permite escribir/editar archivos; “Autonomía total” también ejecuta comandos (mkdir, git…); “Solo planificar” no modifica nada."),
        "chat.runFailed": ("Couldn't run Claude Code. Check the binary path in Settings, that it's a git repo, and that the app runs without App Sandbox.",
                           "No se pudo ejecutar Claude Code. Revisa la ruta del binario en Ajustes, que sea un repo git, y que la app corra sin App Sandbox."),

        // MARK: Task → Strategy (on-device generation)
        "task2strat.open": ("Generate from a task…", "Generar desde una tarea…"),
        "task2strat.title": ("Describe your task", "Describe tu tarea"),
        "task2strat.subtitle": ("We'll suggest a team shape and models for it. On-device — nothing leaves your Mac.",
                                "Te sugerimos una forma de equipo y modelos. En el dispositivo — nada sale de tu Mac."),
        "task2strat.placeholder": ("e.g. Add dark mode across the app and update the tests",
                                   "p. ej. Añadir modo oscuro en toda la app y actualizar los tests"),
        "task2strat.generate": ("Suggest a strategy", "Sugerir una estrategia"),
        "task2strat.generating": ("Thinking…", "Pensando…"),
        "task2strat.use": ("Use this strategy", "Usar esta estrategia"),
        "task2strat.why": ("Why this fits", "Por qué encaja"),
        "task2strat.aiOff": ("Apple Intelligence is off — using built-in matching. Turn it on in System Settings for smarter suggestions.",
                             "Apple Intelligence está desactivado — usando emparejamiento integrado. Actívalo en Ajustes del sistema para sugerencias más inteligentes."),

        // MARK: Model capability tiers + model-vs-effort
        "model.tier.specialist": ("Specialist", "Especialista"),
        "model.tier.specialist.blurb": ("Call it when everyone else is stuck — spots what others miss. Save it for the hardest work.",
                                        "Úsalo cuando los demás se atascan — ve lo que otros no. Resérvalo para lo más difícil."),
        "model.tier.expert": ("Expert", "Experto"),
        "model.tier.expert.blurb": ("Deep experience; brings knowledge that isn't in your code. Great for hard bugs and design.",
                                    "Gran experiencia; aporta conocimiento que no está en tu código. Ideal para bugs difíciles y diseño."),
        "model.tier.generalist": ("Generalist", "Generalista"),
        "model.tier.generalist.blurb": ("Strong all-rounder; a great default for most coding.",
                                        "Todoterreno sólido; un buen valor por defecto para programar."),
        "model.tier.fast": ("Fast & cheap", "Rápido y barato"),
        "model.tier.fast.blurb": ("Best for routine, well-described work. No effort setting.",
                                  "Ideal para trabajo rutinario y bien descrito. Sin ajuste de esfuerzo."),
        "effort.low": ("Low", "Bajo"),
        "effort.medium": ("Default", "Normal"),
        "effort.high": ("High", "Alto"),
        "cost.effort": ("Effort (estimate only)", "Esfuerzo (solo estimación)"),
        "cost.effort.note": ("Higher effort means Claude reads, verifies and thinks more — more tokens. This only changes the estimate, not the files StrategyForge writes.",
                             "Más esfuerzo = Claude lee, verifica y piensa más — más tokens. Solo cambia la estimación, no los archivos que escribe StrategyForge."),
        "glossary.modelEffort": ("Model = which “brain” answers, i.e. how much it knows. Effort = how hard that brain works on one request: how much it reads, verifies and thinks. StrategyForge sets the model; effort is a runtime control you choose inside Claude Code — this app never writes it to any file.",
                                 "Modelo = qué “cerebro” responde, es decir cuánto sabe. Esfuerzo = cuánto se esfuerza ese cerebro en una petición: cuánto lee, verifica y piensa. StrategyForge fija el modelo; el esfuerzo se elige dentro de Claude Code al usarlo — esta app nunca lo escribe en ningún archivo."),

        // MARK: Account & sync
        "account.title": ("Account & sync", "Cuenta y sincronización"),
        "account.subtitle": ("Optional. Sign in to keep your strategy library across your Macs. The app works fully without an account — signing in never touches your projects.",
                             "Opcional. Inicia sesión para mantener tu biblioteca de estrategias en todos tus Mac. La app funciona sin cuenta — iniciar sesión nunca toca tus proyectos."),
        "account.signInApple": ("Sign in with Apple", "Iniciar sesión con Apple"),
        "account.signInGoogle": ("Sign in with Google", "Iniciar sesión con Google"),
        "account.signedInAs": ("Signed in as %@", "Sesión iniciada como %@"),
        "account.signOut": ("Sign out", "Cerrar sesión"),
        "account.googleNote": ("Google sign-in gives you an identity, but iCloud sync needs Sign in with Apple.",
                               "Con Google tienes identidad, pero la sincronización con iCloud requiere Iniciar sesión con Apple."),
        "account.googleUnconfigured": ("Google sign-in isn't set up yet (no client ID).", "Google aún no está configurado (falta el client ID)."),
        "account.syncNow": ("Sync now", "Sincronizar ahora"),
        "account.syncScope": ("Only your configurations sync (name + strategy). Repo folders stay on this Mac.",
                              "Solo se sincronizan tus configuraciones (nombre + estrategia). Las carpetas de proyecto se quedan en este Mac."),
        "sync.unavailable": ("iCloud isn't available. Sign into iCloud in System Settings to sync.", "iCloud no está disponible. Inicia sesión en iCloud en Ajustes del sistema para sincronizar."),
        "sync.done": ("Synced %lld configurations.", "Sincronizadas %lld configuraciones."),
        "sync.failed": ("Sync failed: %@", "Falló la sincronización: %@"),

        // MARK: Diagram labels
        "diag.fanout": ("Fan out", "Reparte"),
        "diag.toolcall": ("Tool call", "Llamada"),
        "diag.route": ("Route", "Enruta"),
        "diag.ask": ("Ask", "Pregunta"),
        "diag.delegate": ("Delegate", "Delega"),
        "diag.mainloop": ("Main loop", "Bucle principal"),
        "diag.workerloop": ("Worker loop", "Bucle de trabajo"),
        "diag.plan": ("Plan", "Planifica"),
        "diag.everyturn": ("Runs every turn", "En cada turno"),
        "diag.mediate": ("Mediate", "Media"),
        "diag.everything": ("Does everything", "Hace todo"),
        "diag.ondemand": ("On-demand", "Bajo demanda"),
        "diag.aftercoding": ("After coding", "Tras programar"),
        "diag.explore": ("Explore", "Explora"),
        "diag.argue": ("Argue", "Argumenta"),
        "diag.sendAdvice": ("Sends advice", "Envía consejo"),
        "diag.sendReview": ("Sends review", "Envía revisión"),
        "diag.sendSummary": ("Sends summary", "Envía resumen"),
        "diag.sendArgument": ("Sends argument", "Envía argumento"),
        "diag.reports": ("Reports back", "Reporta"),
        // Legend
        "diag.legend.delegate": ("delegates", "delega"),
        "diag.legend.report": ("reports back", "reporta"),
        "diag.legend.nolateral": ("subagents never talk to each other", "los subagentes no hablan entre sí"),
    ]

    /// Resolve a key for a language code ("en" or "es"), falling back to English
    /// then to the key itself (so missing keys are visible during development).
    static func string(_ key: String, langCode: String) -> String {
        guard let entry = strings[key] else { return key }
        return langCode == "es" ? entry.es : entry.en
    }
}
