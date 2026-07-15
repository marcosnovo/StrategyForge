//
//  ChatTests.swift
//  StrategyForgeTests
//
//  Pure tests for the Claude Code stream-json parser used by the chat.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct ChatTitleTests {
    @Test func stripsSpanishFiller() {
        #expect(AppModel.inferredTitle(from: "Quiero mejorar el diseño") == "Mejorar el diseño")
        #expect(AppModel.inferredTitle(from: "Necesito que revises el login") == "Revises el login")
        #expect(AppModel.inferredTitle(from: "me gustaría que añadas un modo oscuro") == "Añadas un modo oscuro")
    }

    @Test func stripsEnglishFiller() {
        #expect(AppModel.inferredTitle(from: "Can you add a dark mode toggle") == "Add a dark mode toggle")
    }

    @Test func cutsOnWordBoundary() {
        let t = AppModel.inferredTitle(from: "Refactor the entire networking layer and its retry policies today", maxChars: 30)
        #expect(t.count <= 31)          // ≤ maxChars + the ellipsis
        #expect(t.hasSuffix("…"))
        #expect(!t.contains("  "))
    }

    @Test func keepsPlainTopicUnchanged() {
        #expect(AppModel.inferredTitle(from: "Fix the crash on launch") == "Fix the crash on launch")
    }

    @Test func categorizesByTopic() {
        #expect(AppModel.topicCategoryKey(for: "Investigues lo mejor posible el motor") == "topic.research")
        #expect(AppModel.topicCategoryKey(for: "Revisees este documento con cuidado") == "topic.review")
        #expect(AppModel.topicCategoryKey(for: "Mejorar mucho el diseño de la pantalla") == "topic.design")
        #expect(AppModel.topicCategoryKey(for: "Arregla el crash al abrir") == "topic.bugfix")
        #expect(AppModel.topicCategoryKey(for: "Añade una nueva pantalla de ajustes") == "topic.feature")
    }

    @Test func leadingVerbBeatsIncidentalKeywords() {
        // A document review that mentions "errores" must stay Review, not Bug fix.
        #expect(AppModel.topicCategoryKey(for: "Revisa este documento y dime si hay errores") == "topic.review")
        #expect(AppModel.topicCategoryKey(for: "Investiga por qué falla el módulo de red") == "topic.research")
        // But a real fix request is still a Bug fix.
        #expect(AppModel.topicCategoryKey(for: "Arregla el crash al abrir la app") == "topic.bugfix")
    }

    @Test func categoryFallsBackToCleanedPhrase() {
        // No category keyword → nil, so the caller uses the cleaned phrase instead.
        #expect(AppModel.topicCategoryKey(for: "Quiero hablar sobre el proyecto") == nil)
    }
}

struct ClaudeStreamParserTests {

    @Test func parsesAssistantText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello there"}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.assistantText("Hello there")])
    }

    @Test func parsesToolUse() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b/App.swift"}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.tool(name: "Read", detail: "App.swift")])
    }

    @Test func mixedTextAndToolInOneMessage() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Editing"},{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.assistantText("Editing"), .tool(name: "Bash", detail: "npm test")])
    }

    @Test func bashToolUseEmitsCommandStarted() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Bash","input":{"command":"npm test"}}]}}"#
        let events = ClaudeStreamParser.events(from: line)
        #expect(events.contains(.tool(name: "Bash", detail: "npm test")))
        #expect(events.contains(.commandStarted(id: "tu_1", command: "npm test")))
    }

    @Test func toolResultEmitsCommandOutput() {
        let line = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":[{"type":"text","text":"3 passed"}]}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.commandOutput(id: "tu_1", output: "3 passed")])
    }

    @Test func parsesTodos() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"Audit HUD","status":"in_progress"}]}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.todos([AgentTodo(content: "Audit HUD", status: "in_progress")])])
    }

    @Test func usageSumsAllInputTokenKinds() {
        let line = #"{"type":"result","subtype":"success","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":3,"cache_read_input_tokens":2},"total_cost_usd":0.01}"#
        let events = ClaudeStreamParser.events(from: line)
        #expect(events.contains(.usage(tokens: 20, costUSD: 0.01)))
        #expect(events.contains(.finished))
    }

    @Test func diffParserTagsAddsRemovesAndNumbers() {
        let diff = """
        diff --git a/App.swift b/App.swift
        index 111..222 100644
        --- a/App.swift
        +++ b/App.swift
        @@ -1,3 +1,4 @@
         let a = 1
        -let b = 2
        +let b = 3
        +let c = 4
        """
        let lines = CodeGit.parse(diff)
        // Header noise dropped; one hunk header kept.
        #expect(lines.contains { $0.kind == .hunk })
        let adds = lines.filter { $0.kind == .add }
        let dels = lines.filter { $0.kind == .del }
        #expect(adds.count == 2)
        #expect(dels.count == 1)
        // Context line keeps both old and new numbers starting at 1.
        let firstContext = lines.first { $0.kind == .context }
        #expect(firstContext?.oldNumber == 1)
        #expect(firstContext?.newNumber == 1)
    }

    @Test func resultSuccessFinishes() {
        let line = #"{"type":"result","subtype":"success","result":"done"}"#
        #expect(ClaudeStreamParser.events(from: line) == [.finished])
    }

    @Test func resultErrorFails() {
        let line = #"{"type":"result","subtype":"error_max_turns"}"#
        #expect(ClaudeStreamParser.events(from: line) == [.failed("error_max_turns")])
    }

    @Test func ignoresSystemAndGarbageLines() {
        #expect(ClaudeStreamParser.events(from: #"{"type":"system","subtype":"init"}"#).isEmpty)
        #expect(ClaudeStreamParser.events(from: "not json").isEmpty)
        #expect(ClaudeStreamParser.events(from: "").isEmpty)
    }
}
