//
//  RepoMention.swift
//  StrategyForge
//
//  Detects when a chat message is about working on CODE / a repo — the moment Coral should
//  offer "attach a folder" so the agents can actually read and edit the code (Code mode),
//  instead of leaving that discovery to the header. Pure + testable.
//

import Foundation

enum RepoMention {
    /// Cues that the user wants to work in a codebase (English + Spanish), plus common
    /// git/GitHub signals. Padded matching keeps short cues from firing on substrings.
    private static let cues: [String] = [
        " repo", "repository", "codebase", "code base", "pull request", " a pr", "github.com",
        "git clone", ".git", "the code", "this project's code", "compile", "build error",
        "failing test", "unit test", "refactor", "the bug in", "fix the bug",
        // español
        "repositorio", "código", "codigo", "compilar", "error de compil", "test que falla",
        "pruebas unitarias", "refactor", "el bug", "arreglar el bug", "solicitud de incorporación",
    ]

    /// True when the text reads like a request to work on code in a repo.
    static func mentionsCode(_ text: String) -> Bool {
        let t = " " + text.lowercased() + " "
        return cues.contains { t.contains($0) }
    }
}
