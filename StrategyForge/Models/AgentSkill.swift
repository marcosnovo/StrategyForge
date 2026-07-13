//
//  AgentSkill.swift
//  StrategyForge
//
//  An Agent Skill: a folder under ~/.claude/skills/<slug>/ (personal) or a repo's
//  .claude/skills/<slug>/ (project) containing SKILL.md (name + description
//  frontmatter + a markdown playbook). The CLI auto-discovers and pulls it into
//  context on demand. Coral treats the filesystem as the source of truth — this is
//  the lean in-memory representation of what it parsed. Skill ≠ MCP ≠ subagent:
//  MCP = tools/hands, subagent = a teammate, Skill = a playbook a teammate reads.
//

import Foundation

struct AgentSkill: Identifiable, Hashable {
    /// slug (folder name); unique per scope.
    var id: String { "\(scope.key)/\(slug)" }
    var slug: String
    var name: String
    var description: String
    var license: String?
    var allowedTools: [String]?
    /// The SKILL.md markdown body (frontmatter stripped) — rendered in the detail.
    var body: String
    var scope: Scope
    /// The skill folder on disk (personal or project). nil for a not-yet-installed
    /// discover result.
    var localPath: URL?
    var hasScripts: Bool
    /// True when Coral wrote it (bears our managed signature) → safe to remove.
    var coralManaged: Bool
    var source: Source

    enum Scope: Hashable {
        case personal
        case project(URL)
        var key: String {
            switch self {
            case .personal: return "personal"
            case .project(let url): return "project:\(url.lastPathComponent)"
            }
        }
    }

    enum Source: Hashable {
        case local
        case curated(String)
        case github(owner: String, repo: String, ref: String, path: String)
    }

    /// A skill can run code if it ships scripts or asks for write/exec tools — the
    /// trust gate keys off this.
    var canRunCode: Bool {
        if hasScripts { return true }
        let exec: Set<String> = ["Bash", "Write", "Edit", "MultiEdit", "NotebookEdit"]
        return (allowedTools ?? []).contains { exec.contains($0) }
    }

    /// Coarse type for filtering: a "code" skill ships/runs scripts; a "knowledge"
    /// skill is a pure playbook.
    enum Kind: String, CaseIterable { case knowledge, code }
    var kind: Kind { canRunCode ? .code : .knowledge }
}

/// A discoverable skill in the curated marketplace (before install).
struct CuratedSkill: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let description: String
    let category: String
    let owner: String
    let repo: String
    let ref: String
    let path: String           // repo-relative folder holding SKILL.md
    var verified: Bool = true  // curated = vetted by Coral
    /// GitHub stars of the source repo (community discovery) — an honest popularity
    /// proxy; nil for the official/curated entries. NOT downloads (those don't exist).
    var stars: Int? = nil

    /// Raw URL of the skill's SKILL.md.
    var skillMdURL: URL? {
        let p = path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md"
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(ref)/\(p)")
    }
    var repoURL: URL? { URL(string: "https://github.com/\(owner)/\(repo)") }
}
