//
//  ChatTests.swift
//  StrategyForgeTests
//
//  Pure tests for the Claude Code stream-json parser used by the chat.
//

import Testing
import Foundation
@testable import StrategyForge

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
