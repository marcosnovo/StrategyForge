//
//  GeneratedFile.swift
//  StrategyForge
//
//  A file the app intends to produce, as pure data. Generators return these so
//  the UI can preview exact contents before anything touches disk.
//

import Foundation

/// One file to be written, with its path relative to the repo root and its
/// exact contents.
struct GeneratedFile: Identifiable, Hashable {
    /// Path relative to the repo root, e.g. `.claude/agents/worker-1.md`.
    let relativePath: String
    /// Exact file contents.
    let contents: String

    var id: String { relativePath }

    /// The last path component, for tab labels (e.g. `worker-1.md`).
    var displayName: String {
        (relativePath as NSString).lastPathComponent
    }
}
