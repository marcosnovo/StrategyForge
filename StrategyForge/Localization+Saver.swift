//
//  Localization+Saver.swift
//  StrategyForge
//
//  Strings for the Token Saver (TokenSaverEngine tips, TokenSaverBanner,
//  ContextWeightPill, TokenSaverGuideView). Kept in their own table so
//  Localization.swift stays untouched; the resolver merges this dictionary
//  behind `L10n.string`.
//

import Foundation

extension L10n {

    /// key → (English, Spanish) for the Token Saver tips + guide.
    static let saverStrings: [String: (en: String, es: String)] = [

        // MARK: Tips — summarize & start fresh
        "saver.tip.summarizeRestart.title": ("This chat is getting heavy", "Este chat ya pesa mucho"),
        "saver.tip.summarizeRestart.body": ("Every message re-reads the whole history — a 30-message session can burn ~230k tokens. Summarize what matters and continue fresh.",
                                            "Cada mensaje relee todo el historial — una sesión de 30 mensajes puede quemar ~230k tokens. Resume lo importante y sigue en limpio."),
        "saver.tip.summarizeRestart.action": ("Summarize & restart", "Resumir y empezar de nuevo"),

        // MARK: Tips — convert / crop attachments
        "saver.tip.convertAttachment.title": ("Attachments cost real tokens", "Los adjuntos cuestan tokens de verdad"),
        "saver.tip.convertAttachment.body": ("A PDF costs 1.5–3k tokens per page and an uncropped screenshot ~1.3k. Plain text or Markdown is 10–20× cheaper — convert or crop before sending.",
                                             "Un PDF cuesta 1,5–3k tokens por página y una captura sin recortar ~1,3k. El texto plano o Markdown es 10–20× más barato — convierte o recorta antes de enviar."),
        "saver.tip.convertAttachment.action": ("Convert to text", "Convertir a texto"),

        // MARK: Tips — point at the exact section
        "saver.tip.pointAtSection.title": ("Point at the exact part", "Señala la parte exacta"),
        "saver.tip.pointAtSection.body": ("A vague “redo it” regenerates everything — and re-reads everything. Name the section and ask for only that change.",
                                          "Un «hazlo otra vez» vago lo regenera todo — y lo relee todo. Nombra la sección y pide solo ese cambio."),

        // MARK: Tips — batch small prompts
        "saver.tip.batchPrompts.title": ("Batch small asks into one message", "Agrupa las tareas pequeñas en un mensaje"),
        "saver.tip.batchPrompts.body": ("Each tiny prompt reloads the whole context. One message with 2–3 numbered tasks costs a single reload.",
                                        "Cada mini-prompt recarga todo el contexto. Un mensaje con 2–3 tareas numeradas cuesta una sola recarga."),

        // MARK: Tips — model overkill
        "saver.tip.modelOverkill.title": ("This looks light for your top model", "Esto parece poco para tu modelo grande"),
        "saver.tip.modelOverkill.body": ("Short, simple tasks run great on Sonnet or Haiku for a fraction of the cost. Switch the orchestrator in Team — two clicks.",
                                         "Las tareas cortas y simples van de sobra con Sonnet o Haiku por una fracción del coste. Cambia el orquestador en Equipo — dos clics."),

        // MARK: Tips — new topic, new chat
        "saver.tip.newTopicNewChat.title": ("New topic? Start a new chat", "¿Tema nuevo? Abre un chat nuevo"),
        "saver.tip.newTopicNewChat.body": ("Old context does nothing for a new question — but you re-pay for it on every message. A fresh chat starts light.",
                                           "El contexto viejo no ayuda a la pregunta nueva — pero lo vuelves a pagar en cada mensaje. Un chat nuevo empieza ligero."),
        "saver.tip.newTopicNewChat.action": ("New chat", "Nuevo chat"),

        // MARK: Banner chrome
        "saver.dismiss": ("Dismiss tip", "Descartar consejo"),

        // MARK: Context weight pill
        "saver.weight.light": ("Light context", "Contexto ligero"),
        "saver.weight.medium": ("Context getting heavy", "El contexto va cargándose"),
        "saver.weight.heavy": ("Heavy context", "Contexto pesado"),
        "saver.weight.help": ("Claude re-reads the entire conversation on every message, so cost grows with chat length. Green < 50k tokens, amber < 150k, red beyond.",
                              "Claude relee toda la conversación en cada mensaje, así que el coste crece con la longitud del chat. Verde < 50k tokens, ámbar < 150k, rojo a partir de ahí."),

        // MARK: CLAUDE.md static check
        "saver.claudemd.warning": ("CLAUDE.md is over ~300 lines — it's re-read on every session, and long files degrade instruction-following. Trim it or move occasional workflows to Skills.",
                                   "CLAUDE.md supera las ~300 líneas — se relee en cada sesión y los archivos largos degradan el seguimiento de instrucciones. Recórtalo o mueve los flujos ocasionales a Skills."),

        // MARK: Guide — header + groups
        "saver.guide.title": ("Spend tokens on what matters", "Gasta los tokens en lo que importa"),
        "saver.guide.subtitle": ("Ten habits that cut cost without cutting quality.", "Diez hábitos que recortan el coste sin recortar la calidad."),
        "saver.guide.group.upload": ("Before you upload", "Antes de subir nada"),
        "saver.guide.group.chat": ("While you chat", "Mientras chateas"),
        "saver.guide.group.setup": ("Set up once", "Configúralo una vez"),

        // MARK: Guide — before you upload
        "saver.guide.habit.convert.title": ("Convert files to Markdown", "Convierte los archivos a Markdown"),
        "saver.guide.habit.convert.body": ("A PDF costs 1.5–3k tokens per page; the same content as plain text or Markdown is 10–20× cheaper.",
                                           "Un PDF cuesta 1,5–3k tokens por página; el mismo contenido en texto plano o Markdown es 10–20× más barato."),
        "saver.guide.habit.crop.title": ("Crop screenshots tight", "Recorta bien las capturas"),
        "saver.guide.habit.crop.body": ("An uncropped screenshot is ~1.3k tokens. Crop to the exact area you're asking about.",
                                        "Una captura sin recortar son ~1,3k tokens. Recorta justo la zona sobre la que preguntas."),

        // MARK: Guide — while you chat
        "saver.guide.habit.planCheap.title": ("Plan cheap, build expensive", "Planifica barato, construye caro"),
        "saver.guide.habit.planCheap.body": ("Sketch the approach with a cheap model, then hand the agreed plan to the big one. Exploration is where tokens die.",
                                             "Esboza el enfoque con un modelo barato y pásale el plan cerrado al grande. La exploración es donde mueren los tokens."),
        "saver.guide.habit.batch.title": ("One message, several tasks", "Un mensaje, varias tareas"),
        "saver.guide.habit.batch.body": ("Each prompt reloads the whole conversation. Batch small related asks into a single numbered message.",
                                         "Cada prompt recarga toda la conversación. Agrupa las tareas pequeñas relacionadas en un solo mensaje numerado."),
        "saver.guide.habit.point.title": ("Point, don't regenerate", "Señala, no regeneres"),
        "saver.guide.habit.point.body": ("Never ask to “redo it”. Name the exact section and the exact change — you pay for only that part.",
                                         "Nunca pidas «hazlo otra vez». Nombra la sección exacta y el cambio exacto — pagas solo esa parte."),
        "saver.guide.habit.newChat.title": ("New topic = new chat", "Tema nuevo = chat nuevo"),
        "saver.guide.habit.newChat.body": ("Dead-weight context doesn't help the new question, but you re-pay for it on every message.",
                                           "El contexto muerto no ayuda a la pregunta nueva, pero lo vuelves a pagar en cada mensaje."),
        "saver.guide.habit.summarize.title": ("Summarize every 15–20 messages", "Resume cada 15–20 mensajes"),
        "saver.guide.habit.summarize.body": ("Long chats are token furnaces: a 30-message session can re-read ~230k tokens. Ask for a summary and continue fresh.",
                                             "Los chats largos son hornos de tokens: una sesión de 30 mensajes puede releer ~230k tokens. Pide un resumen y sigue en limpio."),

        // MARK: Guide — set up once
        "saver.guide.habit.rightModel.title": ("The right model for the task", "El modelo justo para la tarea"),
        "saver.guide.habit.rightModel.body": ("Haiku and Sonnet handle simple, well-defined tasks at a fraction of the cost. Save Opus and Fable for the hard work.",
                                              "Haiku y Sonnet resuelven tareas simples y bien definidas por una fracción del coste. Reserva Opus y Fable para lo difícil."),
        "saver.guide.habit.claudemd.title": ("Keep CLAUDE.md under ~300 lines", "Mantén CLAUDE.md por debajo de ~300 líneas"),
        "saver.guide.habit.claudemd.body": ("It's read on every session — bloat costs tokens forever and degrades instruction-following. Move occasional workflows to Skills.",
                                            "Se lee en cada sesión — el exceso cuesta tokens para siempre y degrada el seguimiento de instrucciones. Mueve los flujos ocasionales a Skills."),
        "saver.guide.habit.stateFile.title": ("Carry context in a STATE.md", "Lleva el contexto en un STATE.md"),
        "saver.guide.habit.stateFile.body": ("Keep session notes in a small file the agent reads, instead of re-explaining the project in every chat.",
                                             "Guarda notas de sesión en un archivo pequeño que el agente lee, en vez de re-explicar el proyecto en cada chat."),
    ]
}
