//
//  StrategyPackage.swift
//  StrategyForge
//
//  A portable, shareable single-strategy document (`.sfstrategy`). This is the
//  export/import unit for custom strategies and the seed of a future library.
//
//  Repo paths and security-scoped bookmarks live on Configuration, never on Strategy,
//  so they can't leak. But a Strategy DOES carry MCP server `env` maps, which can hold
//  API keys / tokens — so every share path here REDACTS those env values (keeping the
//  keys) before encoding. Nothing else in a Strategy is secret.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// The document type for exported strategies. (Declared in code; a matching
    /// Info.plist exported-type declaration can be added later for Finder/Quick Look.)
    static let sfStrategy = UTType(exportedAs: "com.marcosnovo.StrategyForge.strategy",
                                   conformingTo: .json)
}

enum StrategyPackage {
    static let currentVersion = 1
    static let fileExtension = "sfstrategy"

    struct Document: Codable {
        var schemaVersion: Int
        var strategy: Strategy
    }

    /// Encode a strategy to a pretty-printed, shareable document — with MCP env secrets
    /// redacted (see `redactingSecrets`).
    static func export(_ strategy: Strategy) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(schemaVersion: currentVersion, strategy: redactingSecrets(strategy)))
    }

    /// A copy safe to SHARE: MCP server `env` VALUES (which can hold API keys / tokens)
    /// are blanked, keeping the keys so an importer knows which vars to fill in. Nothing
    /// else in a Strategy is secret.
    static func redactingSecrets(_ strategy: Strategy) -> Strategy {
        guard strategy.mcpServers.contains(where: { !$0.env.isEmpty }) else { return strategy }
        var s = strategy
        s.mcpServers = s.mcpServers.map { server in
            var m = server
            m.env = m.env.mapValues { _ in "" }
            return m
        }
        return s
    }

    /// True when a strategy carries MCP env values that a share would blank — so the UI
    /// can warn the user before they export/copy it.
    static func hasRedactableSecrets(_ strategy: Strategy) -> Bool {
        strategy.mcpServers.contains { $0.env.values.contains { !$0.isEmpty } }
    }

    /// Decode a strategy document. Ids are regenerated so an imported strategy can
    /// never collide with existing ones in the app.
    static func `import`(_ data: Data) throws -> Strategy {
        let doc = try JSONDecoder().decode(Document.self, from: data)
        var strategy = doc.strategy
        strategy.id = UUID()
        strategy.roles = strategy.roles.map { role in
            var r = role
            r.id = UUID()
            return r
        }
        return strategy
    }

    // MARK: - Copyable text form (paste-to-share, no file / no backend)

    /// Prefix identifying a StrategyForge share string.
    static let textPrefix = "sfstrategy;1;"

    /// A single-line, copy-pasteable share string: the prefix + base64 of the export.
    static func exportText(_ strategy: Strategy) throws -> String {
        textPrefix + (try export(strategy)).base64EncodedString()
    }

    /// Decode a share string (with or without the prefix). Ids are regenerated.
    static func importText(_ text: String) throws -> Strategy {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let b64 = trimmed.hasPrefix(textPrefix) ? String(trimmed.dropFirst(textPrefix.count)) : trimmed
        guard let data = Data(base64Encoded: b64) else {
            throw NSError(domain: "StrategyPackage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid Coral share string."])
        }
        return try `import`(data)
    }

    /// A filesystem-safe file name for a strategy export.
    static func fileName(for strategy: Strategy) -> String {
        let slug = strategy.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(slug.isEmpty ? "strategy" : slug).\(fileExtension)"
    }
}
