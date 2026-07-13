//
//  SkillStore.swift
//  StrategyForge
//
//  The Skills marketplace engine (v1): scans installed skills (filesystem = truth,
//  like StrategyWriter), parses SKILL.md frontmatter, fetches a skill's SKILL.md
//  from a curated entry or a pasted GitHub ref, and installs/uninstalls under
//  ~/.claude/skills (personal) or a repo's .claude/skills (project). Coral only
//  WRITES files — it never executes anything; the CLI runs skills at the user's
//  initiative. Uninstall only removes folders Coral wrote (managed signature).
//

import Foundation
import Observation

@Observable
@MainActor
final class SkillStore {
    static let shared = SkillStore()

    /// Marker written into SKILL.md so uninstall never deletes a hand-authored skill.
    static let signature = "<!-- coral-managed-skill -->"

    private(set) var installed: [AgentSkill] = []

    // MARK: - Scan (filesystem is the source of truth)

    private var personalDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true)
    }
    private func projectDir(_ repo: URL) -> URL {
        repo.appendingPathComponent(".claude/skills", isDirectory: true)
    }

    func scan(projectRepo: URL? = nil) {
        var out: [AgentSkill] = []
        out += scanDir(personalDir, scope: .personal)
        if let repo = projectRepo { out += scanDir(projectDir(repo), scope: .project(repo)) }
        installed = out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scanDir(_ dir: URL, scope: AgentSkill.Scope) -> [AgentSkill] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [AgentSkill] = []
        for folder in entries {
            let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let md = folder.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: md, encoding: .utf8) else { continue }
            let p = Self.parse(text)
            let scripts = folder.appendingPathComponent("scripts")
            let hasScripts = ((try? fm.contentsOfDirectory(atPath: scripts.path))?.isEmpty == false)
            out.append(AgentSkill(
                slug: folder.lastPathComponent,
                name: p.name.isEmpty ? folder.lastPathComponent : p.name,
                description: p.description, license: p.license, allowedTools: p.allowedTools,
                body: p.body, scope: scope, localPath: folder,
                hasScripts: hasScripts, coralManaged: text.contains(Self.signature), source: .local))
        }
        return out
    }

    // MARK: - SKILL.md frontmatter parser (defensive: only `name` is required)

    static func parse(_ md: String) -> (name: String, description: String, license: String?, allowedTools: [String]?, body: String) {
        var name = "", description = "", license: String?, tools: [String]?
        var body = md
        let lines = md.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(of: "---") {
            for raw in lines[1..<end] {
                guard let colon = raw.firstIndex(of: ":") else { continue }
                let key = raw[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                var val = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                switch key {
                case "name": name = val
                case "description": description = val
                case "license": license = val
                case "allowed-tools", "allowedtools", "allowed_tools":
                    let cleaned = val.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                    tools = cleaned.split(whereSeparator: { $0 == "," }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }.filter { !$0.isEmpty }
                default: break
                }
            }
            body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Drop our own signature line from the rendered body.
        body = body.replacingOccurrences(of: signature, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, description, license, tools, body)
    }

    // MARK: - Fetch a preview (SKILL.md only, for v1)

    enum FetchError: LocalizedError {
        case badRef, network(String), empty
        var errorDescription: String? {
            switch self {
            case .badRef: return "That doesn't look like owner/repo[@ref][#path]."
            case .network(let m): return m
            case .empty: return "No SKILL.md found there."
            }
        }
    }

    /// Fetch + parse a curated skill's SKILL.md into a not-yet-installed preview.
    func preview(_ c: CuratedSkill) async throws -> AgentSkill {
        guard let url = c.skillMdURL else { throw FetchError.badRef }
        let text = try await fetchText(url)
        let p = Self.parse(text)
        return AgentSkill(slug: c.slug, name: p.name.isEmpty ? c.name : p.name,
                          description: p.description.isEmpty ? c.description : p.description,
                          license: p.license, allowedTools: p.allowedTools, body: p.body,
                          scope: .personal, localPath: nil, hasScripts: false, coralManaged: true,
                          source: .github(owner: c.owner, repo: c.repo, ref: c.ref, path: c.path))
    }

    /// Fetch from a pasted "owner/repo[@ref][#path]" reference.
    func preview(githubRef ref: String) async throws -> AgentSkill {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://github.com/", with: "")
        var rest = trimmed, path = "", gitRef = "main"
        if let hash = rest.firstIndex(of: "#") { path = String(rest[rest.index(after: hash)...]); rest = String(rest[..<hash]) }
        if let at = rest.firstIndex(of: "@") { gitRef = String(rest[rest.index(after: at)...]); rest = String(rest[..<at]) }
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw FetchError.badRef }
        let owner = parts[0], repo = parts[1]
        if parts.count > 2, path.isEmpty { path = parts[2...].joined(separator: "/") }
        let mdPath = path.isEmpty ? "SKILL.md" : "\(path)/SKILL.md"
        guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(gitRef)/\(mdPath)") else { throw FetchError.badRef }
        let text = try await fetchText(url)
        let p = Self.parse(text)
        let slug = path.split(separator: "/").last.map(String.init) ?? repo
        return AgentSkill(slug: slug, name: p.name.isEmpty ? slug : p.name, description: p.description,
                          license: p.license, allowedTools: p.allowedTools, body: p.body,
                          scope: .personal, localPath: nil, hasScripts: false, coralManaged: true,
                          source: .github(owner: owner, repo: repo, ref: gitRef, path: path))
    }

    private func fetchText(_ url: URL) async throws -> String {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 { throw FetchError.empty }
            guard let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw FetchError.empty }
            return s
        } catch let e as FetchError { throw e }
        catch { throw FetchError.network(error.localizedDescription) }
    }

    // MARK: - Install / uninstall (Coral only writes files)

    /// Write the previewed skill's SKILL.md into the chosen scope, with the managed
    /// signature so it can later be safely removed. Returns the folder path.
    @discardableResult
    func install(_ preview: AgentSkill, into scope: AgentSkill.Scope) throws -> URL {
        let root: URL = { switch scope { case .personal: return personalDir; case .project(let r): return projectDir(r) } }()
        let folder = root.appendingPathComponent(preview.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Re-serialize a minimal SKILL.md (frontmatter + body) with our signature.
        var front = "---\nname: \(preview.name)\ndescription: \(preview.description)\n"
        if let lic = preview.license { front += "license: \(lic)\n" }
        if let tools = preview.allowedTools, !tools.isEmpty { front += "allowed-tools: \(tools.joined(separator: ", "))\n" }
        front += "---\n\n"
        let contents = front + preview.body + "\n\n\(Self.signature)\n"
        try contents.write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        scan(projectRepo: { if case .project(let r) = scope { return r } else { return nil } }())
        return folder
    }

    /// Remove a Coral-installed skill (guarded by the managed signature).
    func uninstall(_ skill: AgentSkill) throws {
        guard skill.coralManaged, let path = skill.localPath else { return }
        try FileManager.default.removeItem(at: path)
        installed.removeAll { $0.id == skill.id }
    }

    // MARK: - Curated marketplace (bundled; a registry API can replace this later)

    let curated: [CuratedSkill] = [
        .init(slug: "pdf", name: "PDF toolkit", description: "Read, fill and generate PDF files reliably.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "document-skills/pdf"),
        .init(slug: "docx", name: "Word documents", description: "Create and edit .docx documents with proper structure.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "document-skills/docx"),
        .init(slug: "xlsx", name: "Spreadsheets", description: "Build and analyze Excel spreadsheets and formulas.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "document-skills/xlsx"),
        .init(slug: "pptx", name: "Presentations", description: "Generate polished PowerPoint decks.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "document-skills/pptx"),
        .init(slug: "artifacts-builder", name: "Artifacts builder", description: "Best practices for building web artifacts.",
              category: "Web", owner: "anthropics", repo: "skills", ref: "main", path: "artifacts-builder"),
    ]
}
