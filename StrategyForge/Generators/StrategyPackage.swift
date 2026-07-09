//
//  StrategyPackage.swift
//  StrategyForge
//
//  A portable, shareable single-strategy document (`.sfstrategy`). This is the
//  export/import unit for custom strategies and the seed of a future library.
//
//  Safe by construction: a Strategy contains ONLY the topology (roles, models,
//  prompts, tools, counts). Repo paths and security-scoped bookmarks live on
//  Configuration, never on Strategy — so they can't leak into a shared package.
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

    /// Encode a strategy to a pretty-printed, shareable document.
    static func export(_ strategy: Strategy) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Document(schemaVersion: currentVersion, strategy: strategy))
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

    /// A filesystem-safe file name for a strategy export.
    static func fileName(for strategy: Strategy) -> String {
        let slug = strategy.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "\(slug.isEmpty ? "strategy" : slug).\(fileExtension)"
    }
}
