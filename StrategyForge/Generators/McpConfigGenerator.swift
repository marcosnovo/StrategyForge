//
//  McpConfigGenerator.swift
//  StrategyForge
//
//  Turns a strategy's MCP servers into the `.mcp.json` Claude Code auto-loads from
//  the project root. Shape: { "mcpServers": { name: { command, args?, env? } } }.
//  Returns nil when there are no valid servers so callers can skip writing the file.
//

import Foundation

enum McpConfigGenerator {
    /// The project-root file Claude Code reads MCP servers from.
    static let fileName = ".mcp.json"

    /// Pretty-printed `.mcp.json` for these servers, or nil if none are usable
    /// (a server needs both a name and a command).
    static func json(for servers: [McpServer]) -> String? {
        let usable = servers.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.command.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !usable.isEmpty else { return nil }

        var byName: [String: Any] = [:]
        for s in usable {
            var entry: [String: Any] = ["command": s.command]
            if !s.args.isEmpty { entry["args"] = s.args }
            if !s.env.isEmpty { entry["env"] = s.env }
            byName[s.name] = entry
        }
        let root: [String: Any] = ["mcpServers": byName]
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
