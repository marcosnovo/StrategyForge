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

    /// Fetch + parse a curated skill into a not-yet-installed preview.
    func preview(_ c: CuratedSkill) async throws -> AgentSkill {
        try await previewGitHub(owner: c.owner, repo: c.repo, ref: c.ref, path: c.path,
                                slug: c.slug, fallbackName: c.name, fallbackDesc: c.description)
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
        let slug = path.split(separator: "/").last.map(String.init) ?? repo
        return try await previewGitHub(owner: owner, repo: repo, ref: gitRef, path: path,
                                       slug: slug, fallbackName: slug, fallbackDesc: "")
    }

    /// List the skill's folder on GitHub, read its SKILL.md, and detect scripts —
    /// enough to preview + gate trust before downloading the whole thing.
    private func previewGitHub(owner: String, repo: String, ref: String, path: String,
                               slug: String, fallbackName: String, fallbackDesc: String) async throws -> AgentSkill {
        let entries = try await ghList(owner: owner, repo: repo, ref: ref, path: path)
        guard let md = entries.first(where: { $0.name.lowercased() == "skill.md" }), let dl = md.downloadURL
        else { throw FetchError.empty }
        let text = try await fetchText(dl)
        let p = Self.parse(text)
        let hasScripts = entries.contains { $0.type == "dir" && $0.name.lowercased() == "scripts" }
        return AgentSkill(slug: slug, name: p.name.isEmpty ? fallbackName : p.name,
                          description: p.description.isEmpty ? fallbackDesc : p.description,
                          license: p.license, allowedTools: p.allowedTools, body: p.body,
                          scope: .personal, localPath: nil, hasScripts: hasScripts, coralManaged: true,
                          source: .github(owner: owner, repo: repo, ref: ref, path: path))
    }

    // MARK: - GitHub contents API (full-folder fetch)

    private struct GHEntry { let name: String; let path: String; let type: String; let downloadURL: URL? }

    private func ghList(owner: String, repo: String, ref: String, path: String) async throws -> [GHEntry] {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let seg = clean.isEmpty ? "" : "/\(clean)"
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents\(seg)?ref=\(ref)")
        else { throw FetchError.badRef }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse {
            if h.statusCode == 404 { throw FetchError.empty }
            if h.statusCode == 403 { throw FetchError.network("GitHub rate limit reached — try again later.") }
        }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw FetchError.empty }
        return arr.map { GHEntry(name: $0["name"] as? String ?? "", path: $0["path"] as? String ?? "",
                                 type: $0["type"] as? String ?? "file",
                                 downloadURL: ($0["download_url"] as? String).flatMap(URL.init)) }
    }

    private func downloadTree(owner: String, repo: String, ref: String, remotePath: String, into localDir: URL) async throws {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        for e in try await ghList(owner: owner, repo: repo, ref: ref, path: remotePath) {
            let dest = localDir.appendingPathComponent(e.name)
            if e.type == "dir" {
                try await downloadTree(owner: owner, repo: repo, ref: ref, remotePath: e.path, into: dest)
            } else if let dl = e.downloadURL {
                let (data, _) = try await URLSession.shared.data(from: dl)
                try data.write(to: dest)
            }
        }
    }

    private func fetchText(_ url: URL) async throws -> String {
        do {
            var req = URLRequest(url: url); req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 { throw FetchError.empty }
            guard let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw FetchError.empty }
            return s
        } catch let e as FetchError { throw e }
        catch { throw FetchError.network(error.localizedDescription) }
    }

    // MARK: - Install / uninstall (Coral only writes files, never executes)

    /// Download the WHOLE skill folder (SKILL.md + scripts/references/assets) into the
    /// chosen scope, stamp SKILL.md with the managed signature, and mark scripts
    /// executable. Returns the folder path. Refuses to overwrite a hand-authored one.
    @discardableResult
    func install(_ preview: AgentSkill, into scope: AgentSkill.Scope) async throws -> URL {
        let root: URL = { switch scope { case .personal: return personalDir; case .project(let r): return projectDir(r) } }()
        let folder = root.appendingPathComponent(preview.slug, isDirectory: true)
        let fm = FileManager.default
        // Clean reinstall only over a Coral-managed folder; never clobber hand-authored.
        if fm.fileExists(atPath: folder.path) {
            let existing = (try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
            guard existing.contains(Self.signature) else { throw FetchError.network("A skill named “\(preview.slug)” already exists here (not installed by Coral).") }
            try? fm.removeItem(at: folder)
        }
        if case .github(let o, let r, let ref, let path) = preview.source {
            try await downloadTree(owner: o, repo: r, ref: ref, remotePath: path, into: folder)
            // Stamp SKILL.md so uninstall is safe.
            let md = folder.appendingPathComponent("SKILL.md")
            if var t = try? String(contentsOf: md, encoding: .utf8), !t.contains(Self.signature) {
                t += "\n\n\(Self.signature)\n"; try? t.write(to: md, atomically: true, encoding: .utf8)
            }
            // Scripts arrive without their +x bit — restore it so the CLI can run them.
            let scripts = folder.appendingPathComponent("scripts")
            if let files = try? fm.subpathsOfDirectory(atPath: scripts.path) {
                for f in files { try? fm.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: scripts.appendingPathComponent(f).path) }
            }
        } else {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var front = "---\nname: \(preview.name)\ndescription: \(preview.description)\n"
            if let lic = preview.license { front += "license: \(lic)\n" }
            if let tools = preview.allowedTools, !tools.isEmpty { front += "allowed-tools: \(tools.joined(separator: ", "))\n" }
            front += "---\n\n"
            try (front + preview.body + "\n\n\(Self.signature)\n").write(
                to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
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

    // Paths track the live anthropics/skills layout (now `skills/<slug>`, previously
    // `document-skills/…` — which 404'd here and caused "No SKILL.md found there").
    let curated: [CuratedSkill] = [
        // Documents
        .init(slug: "pdf", name: "PDF toolkit", description: "Read, fill and generate PDF files reliably.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "skills/pdf"),
        .init(slug: "docx", name: "Word documents", description: "Create and edit .docx documents with proper structure.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "skills/docx"),
        .init(slug: "xlsx", name: "Spreadsheets", description: "Build and analyze Excel spreadsheets and formulas.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "skills/xlsx"),
        .init(slug: "pptx", name: "Presentations", description: "Generate polished PowerPoint decks.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "skills/pptx"),
        .init(slug: "doc-coauthoring", name: "Doc co-authoring", description: "Collaborate on long documents with tracked structure.",
              category: "Documents", owner: "anthropics", repo: "skills", ref: "main", path: "skills/doc-coauthoring"),
        // Design & web
        .init(slug: "web-artifacts-builder", name: "Web artifacts builder", description: "Best practices for building web artifacts.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/web-artifacts-builder"),
        .init(slug: "frontend-design", name: "Frontend design", description: "Craft polished, modern frontend UI.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/frontend-design"),
        .init(slug: "canvas-design", name: "Canvas design", description: "Design rich canvas / graphic compositions.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/canvas-design"),
        .init(slug: "brand-guidelines", name: "Brand guidelines", description: "Apply a brand's voice, color and type consistently.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/brand-guidelines"),
        .init(slug: "theme-factory", name: "Theme factory", description: "Generate cohesive UI themes and design tokens.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/theme-factory"),
        .init(slug: "algorithmic-art", name: "Algorithmic art", description: "Create generative / algorithmic artwork.",
              category: "Design & web", owner: "anthropics", repo: "skills", ref: "main", path: "skills/algorithmic-art"),
        // Developer
        .init(slug: "mcp-builder", name: "MCP builder", description: "Scaffold and build Model Context Protocol servers.",
              category: "Developer", owner: "anthropics", repo: "skills", ref: "main", path: "skills/mcp-builder"),
        .init(slug: "webapp-testing", name: "Web app testing", description: "Write and run tests for web applications.",
              category: "Developer", owner: "anthropics", repo: "skills", ref: "main", path: "skills/webapp-testing"),
        .init(slug: "claude-api", name: "Claude API", description: "Build correctly against the Claude API.",
              category: "Developer", owner: "anthropics", repo: "skills", ref: "main", path: "skills/claude-api"),
        .init(slug: "skill-creator", name: "Skill creator", description: "Author new Agent Skills the right way.",
              category: "Developer", owner: "anthropics", repo: "skills", ref: "main", path: "skills/skill-creator"),
    ]
}
