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
        let entries = usableEntries(servers)
        guard !entries.isEmpty else { return nil }
        return encode(["mcpServers": entries])
    }

    /// Merge our servers INTO an existing `.mcp.json`, preserving the user's own
    /// `mcpServers` entries (and any other top-level keys); ours win only on a name
    /// collision. Returns nil when there's nothing to write — OR when an existing file is
    /// present but unparseable, so a hand-authored file is never clobbered.
    static func mergedJSON(existing: String?, for servers: [McpServer]) -> String? {
        let ours = usableEntries(servers)
        var root: [String: Any] = [:]
        var theirs: [String: Any] = [:]
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = existing.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil   // present but unparseable → don't overwrite the user's file
            }
            root = obj
            theirs = (obj["mcpServers"] as? [String: Any]) ?? [:]
        }
        guard !ours.isEmpty || !theirs.isEmpty else { return nil }
        var merged = theirs
        for (name, entry) in ours { merged[name] = entry }   // ours override on collision
        root["mcpServers"] = merged
        return encode(root)
    }

    /// `[name: { command, args?, env? }]` for the servers that have a name + command.
    private static func usableEntries(_ servers: [McpServer]) -> [String: Any] {
        var byName: [String: Any] = [:]
        for s in servers where !s.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !s.command.trimmingCharacters(in: .whitespaces).isEmpty {
            var entry: [String: Any] = ["command": s.command]
            if !s.args.isEmpty { entry["args"] = s.args }
            if !s.env.isEmpty { entry["env"] = s.env }
            byName[s.name] = entry
        }
        return byName
    }

    private static func encode(_ root: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Gemini CLI

    /// Gemini CLI reads MCP servers from `.gemini/settings.json`, using the SAME
    /// `mcpServers` shape as Claude's `.mcp.json`, so we can reuse the merge logic — it
    /// preserves the user's other settings keys and only adds/overrides our servers.
    static let geminiFileName = ".gemini/settings.json"
    static func geminiSettingsJSON(existing: String?, for servers: [McpServer]) -> String? {
        mergedJSON(existing: existing, for: servers)
    }

    // MARK: - Codex CLI

    /// Codex reads MCP servers from a TOML config as `[mcp_servers.NAME]` blocks. We emit a
    /// project-scoped `.codex/config.toml` as a portable artifact (Codex may also read the
    /// global `~/.codex/config.toml`). No merge — TOML has no stdlib parser here — so the
    /// caller writes this only when no file exists, to never clobber a hand-authored one.
    static let codexFileName = ".codex/config.toml"
    static func codexTOML(for servers: [McpServer]) -> String? {
        let usable = servers.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.command.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !usable.isEmpty else { return nil }
        var out = ""
        for s in usable.sorted(by: { $0.name < $1.name }) {
            let key = tomlKey(s.name)
            out += "[mcp_servers.\(key)]\n"
            out += "command = \(tomlString(s.command))\n"
            if !s.args.isEmpty {
                out += "args = [\(s.args.map(tomlString).joined(separator: ", "))]\n"
            }
            if !s.env.isEmpty {
                out += "\n[mcp_servers.\(key).env]\n"
                for (k, v) in s.env.sorted(by: { $0.key < $1.key }) {
                    out += "\(tomlKey(k)) = \(tomlString(v))\n"
                }
            }
            out += "\n"
        }
        return out
    }

    /// A TOML basic string (double-quoted, backslash/quote escaped).
    private static func tomlString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    /// A bare TOML key when it's [A-Za-z0-9_-], else a quoted key.
    private static func tomlKey(_ s: String) -> String {
        let bare = !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return bare ? s : tomlString(s)
    }
}
