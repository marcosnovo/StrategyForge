//
//  McpMultiProviderTests.swift
//  StrategyForgeTests
//
//  MCP is a shared standard but each CLI reads a different file/format. These verify the
//  Gemini (`.gemini/settings.json`, same mcpServers shape, merged) and Codex
//  (`.codex/config.toml`, TOML `[mcp_servers.NAME]`) generators produce correct output.
//

import Testing
@testable import Coral

struct McpMultiProviderTests {

    private func server(_ name: String, _ cmd: String,
                        args: [String] = [], env: [String: String] = [:]) -> McpServer {
        McpServer(name: name, command: cmd, args: args, env: env)
    }

    @Test func codexTOMLHasBlocksArgsAndEnv() throws {
        let toml = try #require(McpConfigGenerator.codexTOML(
            for: [server("github", "npx", args: ["-y", "gh-mcp"], env: ["TOKEN": "x"])]))
        #expect(toml.contains("[mcp_servers.github]"))
        #expect(toml.contains("command = \"npx\""))
        #expect(toml.contains("args = [\"-y\", \"gh-mcp\"]"))
        #expect(toml.contains("[mcp_servers.github.env]"))
        #expect(toml.contains("TOKEN = \"x\""))
    }

    @Test func codexTOMLQuotesNonBareKeysAndEscapes() throws {
        let toml = try #require(McpConfigGenerator.codexTOML(for: [server("wei rd", "a\"b")]))
        #expect(toml.contains("[mcp_servers.\"wei rd\"]"))
        #expect(toml.contains("command = \"a\\\"b\""))
    }

    @Test func codexTOMLNilWhenNoUsableServers() {
        #expect(McpConfigGenerator.codexTOML(for: []) == nil)
        #expect(McpConfigGenerator.codexTOML(for: [server("", "")]) == nil)
    }

    @Test func geminiMergesPreservingOtherSettings() throws {
        let existing = #"{ "theme": "dark", "mcpServers": { "old": { "command": "x" } } }"#
        let json = try #require(McpConfigGenerator.geminiSettingsJSON(existing: existing,
                                                                      for: [server("new", "cmd")]))
        #expect(json.contains("\"theme\""))   // unrelated setting preserved
        #expect(json.contains("\"old\""))      // user's server preserved
        #expect(json.contains("\"new\""))      // ours added
    }
}
