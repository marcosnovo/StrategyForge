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
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.tool("Edit")])
    }

    @Test func mixedTextAndToolInOneMessage() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Editing"},{"type":"tool_use","name":"Write"}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.assistantText("Editing"), .tool("Write")])
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
