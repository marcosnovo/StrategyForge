//
//  StrategyEditorView.swift
//  StrategyForge
//
//  Center column: a numbered, guided flow in cards — name → strategy → target
//  folder → roles. Validation is shown live, inline.
//

import SwiftUI

struct StrategyEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var config: Configuration

    @State private var showPreview = false
    @State private var showRepoHelp = false
    @State private var showRoles = false
    @State private var showCostInfo = false
    @State private var costEffort: CostEffort = .medium
    @State private var showWhatNow = false
    @State private var confirmOverwrite = false
    @State private var pendingConflicts: [String] = []
    @State private var runPending: (() -> Void)?
    @State private var showMcp = false

    private var hasRepo: Bool { config.repoPath != nil }
    private var canGenerate: Bool { config.strategy.isValid && hasRepo }

    var body: some View {
        let allIssues = config.strategy.validate()
        let hasRoleErrors = allIssues.contains { $0.roleID != nil && $0.severity == .error }

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                titleField
                strategyCard
                repoCard
                rolesDisclosure(allIssues: allIssues)
                mcpCard
                validationSummary(allIssues)
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .safeAreaInset(edge: .bottom, spacing: 0) { generateBar }
        .onAppear { if hasRoleErrors { showRoles = true } }
        .sheet(isPresented: $showPreview) {
            FilePreviewSheet(config: config)
        }
        .sheet(isPresented: $showWhatNow) {
            WhatNowSheet(config: config)
        }
        .confirmationDialog(
            model.t("preview.overwriteTitle"),
            isPresented: $confirmOverwrite,
            titleVisibility: .visible
        ) {
            Button(model.t("preview.overwrite"), role: .destructive) { runPending?() }
            Button(model.t("common.cancel"), role: .cancel) { runPending = nil }
        } message: {
            Text(model.t("preview.overwriteMsg", pendingConflicts.joined(separator: "\n")))
        }
    }

    /// Plain-language preview of what pressing Generate will do.
    private var willHappenText: String {
        let instances = config.strategy.subagentRoles.reduce(0) { $0 + max(1, $1.count) }
        let files = instances + 1 // one file per subagent instance + CLAUDE.md
        let name = config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name
        if instances == 0 {
            return model.t("summary.willHappen.solo", name, files)
        }
        return model.t("summary.willHappen", instances + 1, name, files)
    }

    // MARK: - MCP tool servers

    /// Optional external tool servers (MCP) — collapsed by default so beginners
    /// don't have to think about it; written to `.mcp.json` when set.
    private var mcpCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            DisclosureGroup(isExpanded: $showMcp) {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach($config.strategy.mcpServers) { $server in
                        mcpRow($server)
                    }
                    Button {
                        config.strategy.mcpServers.append(McpServer(command: "npx"))
                        showMcp = true
                    } label: {
                        Label(model.t("mcp.add"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Text(model.t("mcp.note")).font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s)
            } label: {
                HStack(spacing: Space.s) {
                    Label(model.t("mcp.title"), systemImage: "puzzlepiece.extension.fill")
                        .font(.sfCardTitle)
                    if !config.strategy.mcpServers.isEmpty {
                        Text("\(config.strategy.mcpServers.count)")
                            .font(.sfCaption2.weight(.bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentSoft))
                    }
                }
            }
        }
        .card()
    }

    private func mcpRow(_ server: Binding<McpServer>) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                TextField(model.t("mcp.name"), text: server.name).textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    config.strategy.mcpServers.removeAll { $0.id == server.wrappedValue.id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help(model.t("mcp.remove"))
            }
            TextField(model.t("mcp.command"), text: server.command).textFieldStyle(.roundedBorder)
            TextField(model.t("mcp.args"), text: Binding(
                get: { server.wrappedValue.args.joined(separator: " ") },
                set: { server.wrappedValue.args = $0.split(separator: " ").map(String.init) }))
                .textFieldStyle(.roundedBorder).font(.body.monospaced())
            TextField(model.t("mcp.env"), text: Binding(
                get: { server.wrappedValue.env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n") },
                set: { txt in
                    var d: [String: String] = [:]
                    for line in txt.split(whereSeparator: \.isNewline) {
                        let kv = line.split(separator: "=", maxSplits: 1)
                        guard kv.count == 2 else { continue }
                        d[kv[0].trimmingCharacters(in: .whitespaces)] = String(kv[1])
                    }
                    server.wrappedValue.env = d
                }), axis: .vertical)
                .textFieldStyle(.roundedBorder).font(.body.monospaced()).lineLimit(1...4)
        }
        .padding(Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    // MARK: - Bottom action bar

    private var generateBar: some View {
        VStack(spacing: Space.m) {
            if !hasRepo {
                HStack(spacing: Space.s) {
                    Image(systemName: "folder.badge.plus").foregroundStyle(Theme.accent)
                    Text(model.t("preview.needRepo")).font(.sfCallout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(model.t("preview.needRepo.button")) { model.pickRepo(for: config.id) }
                        .buttonStyle(.moon)
                }
                .padding(Space.m)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.accentSoft))
            } else if !config.strategy.isValid {
                Label(model.t("preview.fixErrors"), systemImage: "exclamationmark.triangle.fill")
                    .font(.sfCallout).foregroundStyle(Theme.warningText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if canGenerate {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent).font(.system(size: 12))
                    Text(willHappenText)
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: Space.m) {
                Button {
                    model.save()
                    model.flashSuccess(model.t("banner.saved"))
                } label: {
                    Label(model.t("editor.save"), systemImage: "tray.and.arrow.down")
                }
                .controlSize(.large)
                .lineLimit(1)
                .help(model.t("editor.save.help"))

                Button {
                    showPreview = true
                } label: {
                    Label(model.t("action.preview"), systemImage: "doc.text.magnifyingglass")
                }
                .controlSize(.large)
                .lineLimit(1)

                // Beginner "use it in the Claude app" path — no repo/Terminal needed.
                Menu {
                    Button {
                        model.downloadBrief(config)
                    } label: {
                        Label(model.t("action.download"), systemImage: "arrow.down.doc")
                    }
                    .help(model.t("action.download.help"))
                    Button {
                        model.copyStarterPrompt(config)
                    } label: {
                        Label(model.t("action.copyPrompt"), systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.button)
                .controlSize(.large)
                .fixedSize()
                .help(model.t("action.download.help"))

                Spacer(minLength: Space.s)

                // Split button: primary = Generate, menu holds the Terminal variant.
                // Keeps the bar narrow so the window can shrink without clipping.
                Menu {
                    Button {
                        attemptGenerate { model.generateAndOpenTerminal(config) }
                    } label: {
                        Label(model.t("preview.generateTerminal"), systemImage: "terminal")
                    }
                    Button {
                        attemptGenerate { model.generateAndCommit(config) }
                    } label: {
                        Label(model.t("action.commit"), systemImage: "arrow.triangle.branch")
                    }
                    .help(model.t("action.commit.help"))
                } label: {
                    Label(model.t("preview.generate"), systemImage: "square.and.arrow.down")
                } primaryAction: {
                    attemptGenerate { if model.generate(config) { showWhatNow = true } }
                }
                .menuStyle(.button)
                .buttonStyle(.moon)
                .controlSize(.large)
                .fixedSize()
                .disabled(!canGenerate)
                .help(model.t("preview.generate.help"))
                .shadow(color: canGenerate ? Theme.accentGlow : .clear, radius: 10, y: 2)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Run a generate action, confirming first if it would overwrite agent files.
    private func attemptGenerate(_ action: @escaping () -> Void) {
        let conflicts = model.overwriteConflicts(for: config)
        if conflicts.isEmpty {
            action()
        } else {
            pendingConflicts = conflicts
            runPending = action
            confirmOverwrite = true
        }
    }

    // MARK: - Cards

    /// Lightweight inline hero title — the config name, no card, no step number.
    private var titleField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            FieldLabel(text: model.t("editor.t.name"))
            TextField(model.t("editor.name.placeholder"), text: $config.name)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
    }

    // Compact cost pill shown in the strategy card header; taps open a breakdown.
    private var costBadge: some View {
        let cost = CostEstimator.estimate(config.strategy, effort: costEffort)
        let color: Color
        let tierLabel: String
        switch cost.tier {
        case .low: color = Theme.success; tierLabel = model.t("cost.tier.low")
        case .medium: color = Theme.warning; tierLabel = model.t("cost.tier.medium")
        case .high: color = Theme.danger; tierLabel = model.t("cost.tier.high")
        }
        return Button { showCostInfo = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").scaledFont(9)
                Text(model.t("cost.perRun", String(format: "$%.2f", cost.perRun)))
                    .font(.sfCaption2.weight(.semibold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help(tierLabel)
        .popover(isPresented: $showCostInfo, arrowEdge: .bottom) {
            CostBreakdownView(strategy: config.strategy, effort: $costEffort)
        }
    }

    // Plain-language "when to use / when not" lines for the selected strategy.
    private var goodForNotFor: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success).font(.system(size: 12))
                Text(model.strategyGoodFor(config.strategy))
                    .font(.sfCallout).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary).font(.system(size: 12))
                Text(model.strategyNotFor(config.strategy))
                    .font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private var strategyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("square.grid.2x2.fill", model.strategyDisplayName(config.strategy), subtitle: model.t("editor.strategy.help")) {
                HStack(spacing: Space.s) {
                    InfoPopoverButton(text: model.t("glossary.strategy"))
                    costBadge
                }
            }
            if model.isBeginnerStrategy(config.strategy) {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill").scaledFont(9)
                    Text(model.t("strat.badge.beginner")).font(.sfCaption2.weight(.semibold))
                }
                .foregroundStyle(Theme.success)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.success.opacity(0.16)))
            }

            Text(model.strategyDisplayDescription(config.strategy))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            goodForNotFor

            // Diagram inside the strategy card, so topology sits with its choice.
            StrategyDiagramView(strategy: config.strategy)
                .frame(height: StrategyDiagramView.preferredHeight(for: config.strategy))
            Text(model.t("editor.diagram.note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var repoCard: some View {
        let hasRepo = config.repoPath != nil
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("folder.fill", model.t("editor.t.folder"), subtitle: model.t("editor.repo.subtitle")) {
                HStack(spacing: 8) {
                    Button {
                        showRepoHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(model.t("editor.repo.helpTitle"))
                    .accessibilityLabel(model.t("editor.repo.helpButton"))
                    .popover(isPresented: $showRepoHelp, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text(model.t("editor.repo.helpTitle")).font(.sfCardTitle)
                            Text(model.t("editor.repo.helpBody"))
                                .font(.sfCallout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Space.l)
                        .frame(width: 360)
                    }
                }
            }
            HStack(spacing: Space.m) {
                Image(systemName: hasRepo ? "folder.fill" : "folder.badge.plus")
                    .foregroundStyle(hasRepo ? Theme.accent : Color.secondary)
                Text(config.repoPath ?? model.t("editor.repo.empty"))
                    .font(hasRepo ? .sfCode : .sfBodyM)
                    .foregroundStyle(hasRepo ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                if hasRepo {
                    Button(model.t("common.choose")) { model.pickRepo(for: config.id) }
                        .buttonStyle(.bordered)
                } else {
                    Button(model.t("common.choose")) { model.pickRepo(for: config.id) }
                        .buttonStyle(.moon)
                }
            }
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .fill(Theme.insetBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            )
            Label(model.t(hasRepo ? "editor.repo.willWrite" : "editor.repo.example"),
                  systemImage: hasRepo ? "checkmark.circle" : "info.circle")
                .font(.sfCaption2)
                .foregroundStyle(hasRepo ? Theme.success : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    /// Roles are advanced: collapsed by default so beginners aren't overwhelmed.
    private func rolesDisclosure(allIssues: [Strategy.ValidationIssue]) -> some View {
        DisclosureGroup(isExpanded: $showRoles) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("editor.advanced.hint"))
                    .font(.sfCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s)
                ForEach($config.strategy.roles) { $role in
                    RoleRowView(
                        role: $role,
                        issues: allIssues.filter { $0.roleID == role.id }
                    )
                }
            }
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.accent)
                Text(model.t("editor.advanced")).font(.sfCardTitle)
                Spacer(minLength: 0)
                Text("\(config.strategy.roles.count)")
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func validationSummary(_ issues: [Strategy.ValidationIssue]) -> some View {
        let globalIssues = issues.filter { $0.roleID == nil }
        let fixable = config.strategy.hasAutoFixableIssues
        if !globalIssues.isEmpty || fixable {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Label(model.t("lint.title"), systemImage: "checklist")
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if fixable {
                        Button {
                            model.autoFixStrategy(config.id)
                        } label: {
                            Label(model.t("lint.fixAll"), systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                ForEach(globalIssues) { issue in
                    Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.sfCallout)
                        .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.warning.opacity(0.10)))
        } else if config.strategy.isValid {
            Label(model.t("editor.valid"), systemImage: "checkmark.seal.fill")
                .font(.sfCallout.weight(.medium))
                .foregroundStyle(Theme.success)
                .padding(.horizontal, Space.xs)
        }
    }
}

/// The cost breakdown shown in the strategy card's cost popover: per-run estimate,
/// an effort selector that only tunes the estimate, and the per-model split.
struct CostBreakdownView: View {
    @Environment(AppModel.self) private var model
    let strategy: Strategy
    @Binding var effort: CostEffort

    var body: some View {
        let cost = CostEstimator.estimate(strategy, effort: effort)
        let color: Color
        let tierLabel: String
        switch cost.tier {
        case .low: color = Theme.success; tierLabel = model.t("cost.tier.low")
        case .medium: color = Theme.warning; tierLabel = model.t("cost.tier.medium")
        case .high: color = Theme.danger; tierLabel = model.t("cost.tier.high")
        }
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(model.t("cost.title")).font(.sfCardTitle)
                Spacer()
                Text(tierLabel).font(.sfCaption2.weight(.semibold)).foregroundStyle(color)
            }
            Text(model.t("cost.perRun", String(format: "$%.2f", cost.perRun)))
                .font(.sfMono).foregroundStyle(Theme.accent)

            Divider()
            FieldLabel(text: model.t("cost.effort"))
            Picker("", selection: $effort) {
                ForEach(CostEffort.allCases) { e in
                    Text(model.t(e.labelKey)).tag(e)
                }
            }
            .pickerStyle(.segmented).tint(Theme.coral)
            .labelsHidden()
            Text(model.t("cost.effort.note"))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            FieldLabel(text: model.t("cost.byModel"))
            ForEach(cost.byModel.sorted { $0.value > $1.value }, id: \.key) { entry in
                HStack {
                    Text(ClaudeModel(rawValue: entry.key)?.displayName ?? entry.key).font(.sfCallout)
                    Spacer()
                    Text(String(format: "$%.2f", entry.value)).font(.sfMono).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text(model.t("cost.disclaimer"))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(width: 320)
    }
}

private struct CostBreakdownPreviewHost: View {
    @State private var effort: CostEffort
    let strategy: Strategy
    init(strategy: Strategy, effort: CostEffort) {
        self.strategy = strategy
        _effort = State(initialValue: effort)
    }
    var body: some View {
        CostBreakdownView(strategy: strategy, effort: $effort)
            .environment(AppModel())
            .tint(Theme.accent)
            .padding()
    }
}

#Preview("Cost breakdown") {
    CostBreakdownPreviewHost(strategy: StrategyLibrary.domainSpecialists(), effort: .high)
}
#Preview("Cost breakdown (Dark)") {
    CostBreakdownPreviewHost(strategy: StrategyLibrary.orchestratorWorkers(), effort: .medium)
        .preferredColorScheme(.dark)
}

private struct EditorPreviewHost: View {
    @State private var model: AppModel = {
        let m = AppModel()
        m.configurations = [Configuration(name: "Backend refactor team", strategy: StrategyLibrary.orchestratorWorkers())]
        m.selectedConfigID = m.configurations.first!.id
        return m
    }()
    var body: some View {
        StrategyEditorView(config: model.configurationBinding(model.selectedConfigID!))
            .environment(model)
            .tint(Theme.accent)
            .frame(width: 680, height: 1180)
    }
}

#Preview { EditorPreviewHost() }
#Preview("Dark") { EditorPreviewHost().preferredColorScheme(.dark) }
