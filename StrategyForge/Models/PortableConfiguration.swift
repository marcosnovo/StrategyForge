//
//  PortableConfiguration.swift
//  StrategyForge
//
//  The portable, shareable/syncable projection of a Configuration: everything
//  EXCEPT device-local state. A Configuration mixes a portable Strategy with a
//  macOS-only security-scoped `repoBookmark` (and a POSIX `repoPath`) that are
//  meaningless — and trust-corrupting — on another machine. This projection is
//  the ONLY shape that ever leaves the device (CloudKit sync, .sfstrategy export),
//  so the bookmark can never travel by construction.
//

import Foundation

struct PortableConfiguration: Codable, Identifiable, Hashable {
    /// Bumped when the portable shape changes; carried alongside the local store
    /// version so sync records stay forward-compatible.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var name: String
    var strategy: Strategy
    /// Last local edit time, used for last-writer-wins conflict resolution on sync.
    var updatedAt: Date

    init(id: UUID,
         name: String,
         strategy: Strategy,
         updatedAt: Date,
         schemaVersion: Int = currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.strategy = strategy
        self.updatedAt = updatedAt
    }
}

extension Configuration {
    /// The portable projection of this configuration (drops repo path + bookmark).
    var portable: PortableConfiguration {
        PortableConfiguration(id: id, name: name, strategy: strategy, updatedAt: updatedAt)
    }

    /// Apply an incoming portable projection while preserving this device's repo
    /// binding (repoPath / repoBookmark are never overwritten by sync).
    mutating func applyPortable(_ p: PortableConfiguration) {
        name = p.name
        strategy = p.strategy
        updatedAt = p.updatedAt
    }

    /// Build a fresh local configuration from a portable projection (e.g. a config
    /// synced from another Mac that this device hasn't seen yet). No repo binding.
    init(portable p: PortableConfiguration) {
        self.init(id: p.id, name: p.name, strategy: p.strategy, updatedAt: p.updatedAt)
    }
}

/// Pure last-writer-wins merge of remote portable configurations into a local set.
/// Kept free of disk/observation so it is directly unit-testable. Device-local
/// repo bindings are always preserved; remote-only configs are appended.
enum ConfigMerger {
    /// Outcome of a merge: the reconciled set (including any preserved conflict copies)
    /// and how many divergent local edits were kept rather than silently overwritten.
    struct Result {
        var configurations: [Configuration]
        var conflictCount: Int
    }

    /// Merge remote portable configs into a local set. Last-writer-wins by `updatedAt`,
    /// but when BOTH sides changed since the last sync (`baseline[id]` = the `updatedAt`
    /// each config had at the last successful sync) AND their portable content differs,
    /// the losing LOCAL edit is preserved as a renamed "(conflict)" copy under a fresh
    /// id — so a concurrent edit on another Mac never silently discards local work.
    /// With an empty baseline this reduces to plain last-writer-wins (no conflict copies).
    static func merge(local: [Configuration],
                      remote: [PortableConfiguration],
                      baseline: [UUID: Date] = [:],
                      conflictSuffix: String = " (conflict)") -> Result {
        var result = local
        var conflicts = 0
        for r in remote {
            guard let idx = result.firstIndex(where: { $0.id == r.id }) else {
                result.append(Configuration(portable: r))     // remote-only → adopt it
                continue
            }
            let localConfig = result[idx]
            guard r.updatedAt > localConfig.updatedAt else { continue }  // local wins/equal
            // Remote wins. Was the local copy independently edited since the last sync,
            // with genuinely different portable content? Then it's a real conflict.
            let localDiverged = baseline[r.id].map { localConfig.updatedAt > $0 } ?? false
            let contentDiffers = localConfig.name != r.name || localConfig.strategy != r.strategy
            if localDiverged && contentDiffers {
                var clone = localConfig                        // keeps repoPath / bookmark
                clone.id = UUID()
                clone.name = localConfig.name + conflictSuffix
                result.append(clone)
                conflicts += 1
            }
            result[idx].applyPortable(r)                       // keeps repoPath / bookmark
        }
        return Result(configurations: result, conflictCount: conflicts)
    }
}
