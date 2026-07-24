//
//  ArenaView.swift
//  StrategyForge
//
//  Arena mode: run one task against several providers at once and keep the best answer.
//  A task field, a row of connected providers to enter (each with a model), Run, then a
//  results card per entrant with its answer + tokens/cost, a suggested (cheapest) winner,
//  and actions to copy or carry the answer into a real chat on that provider.
//

import SwiftUI
import AppKit

@Observable
@MainActor
final class ArenaModel {
    var prompt: String = ""
    var outcomes: [ArenaOutcome] = []
    var isRunning = false
    var winnerID: ArenaOutcome.ID?
    var elapsed: TimeInterval = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?

    func run(entrants: [ArenaEntrant], cwd: String?, runner: OneShotRunner) {
        guard !isRunning, !entrants.isEmpty else { return }
        isRunning = true; outcomes = []; winnerID = nil; elapsed = 0
        let prompt = self.prompt
        runTask = Task { [weak self] in
            let start = Date()
            let out = await ArenaEngine.run(prompt: prompt, entrants: entrants, cwd: cwd, runner: runner)
            guard let self, !Task.isCancelled else { return }
            self.outcomes = out
            self.winnerID = ArenaEngine.suggestedWinner(out)
            self.elapsed = Date().timeIntervalSince(start)
            self.isRunning = false
        }
    }

    func cancel() {
        runTask?.cancel(); runTask = nil
        LiveProcesses.terminateAll()   // stop the in-flight CLIs
        isRunning = false
    }

    // MARK: Teams mode (whole strategies race each other)

    var teamOrder: [StrategyContestant] = []
    var teamProgress: [String: StrategyRunProgress] = [:]
    var teamWinnerID: String?
    var isRunningTeams = false
    /// Per-contestant start/end wall times, for the live elapsed timer on each card.
    var teamStart: [String: Date] = [:]
    var teamEnd: [String: Date] = [:]
    @ObservationIgnored private var teamTask: Task<Void, Never>?

    func runTeams(task: String, contestants: [StrategyContestant], cwd: String?, runner: OneShotRunner) {
        guard !isRunningTeams, contestants.count >= 2 else { return }
        isRunningTeams = true
        teamOrder = contestants
        teamProgress = Dictionary(uniqueKeysWithValues: contestants.map { ($0.id, StrategyRunProgress(state: .queued)) })
        teamWinnerID = nil; teamStart = [:]; teamEnd = [:]
        teamTask = Task { [weak self] in
            let finals = await StrategyArenaEngine.run(
                task: task, cwd: cwd, contestants: contestants, runner: runner
            ) { id, prog in
                // onUpdate fires from concurrent worker tasks — marshal to the main actor.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.teamStart[id] == nil { self.teamStart[id] = Date() }
                    if (prog.state == .done || prog.state == .failed), self.teamEnd[id] == nil {
                        self.teamEnd[id] = Date()
                    }
                    self.teamProgress[id] = prog
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.teamWinnerID = StrategyArenaEngine.suggestedWinner(finals)
            self.isRunningTeams = false
        }
    }

    func cancelTeams() {
        teamTask?.cancel(); teamTask = nil
        LiveProcesses.terminateAll()
        isRunningTeams = false
    }
}

enum ArenaMode: String, CaseIterable { case models, teams }

struct ArenaView: View {
    @Environment(AppModel.self) private var model
    @State private var arena = ArenaModel()
    @State private var mode: ArenaMode = .models
    @State private var selected: Set<AIProvider> = []
    @State private var modelChoice: [AIProvider: String] = [:]
    @State private var didSeed = false
    // Teams mode
    @State private var selectedTeams: Set<String> = []
    @State private var showTeamCostConfirm = false

    private var connected: [AIProvider] { AIProvider.allCases.filter { model.isConnected($0) } }

    private var entrants: [ArenaEntrant] {
        connected.filter { selected.contains($0) }.map {
            ArenaEntrant(provider: $0, model: modelChoice[$0] ?? $0.models.first?.id ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    taskCard
                    if mode == .models {
                        entrantsCard
                        if !arena.outcomes.isEmpty || arena.isRunning { resultsSection }
                    } else {
                        teamsCard
                        if !arena.teamOrder.isEmpty { teamsResultsSection }
                    }
                }
                .padding(Space.xl).frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .task {
            await model.refreshConnectedProviders()
            if !didSeed { selected = Set(connected); didSeed = true }   // default: everyone in
        }
        .confirmationDialog(model.t("arena.teams.cost.title"), isPresented: $showTeamCostConfirm, titleVisibility: .visible) {
            Button(model.t("arena.teams.cost.run"), role: .destructive) {
                arena.runTeams(task: arena.prompt, contestants: chosenTeams,
                               cwd: nil, runner: model.oneShotRunner(readOnly: true))
            }
            Button(model.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(model.t("arena.teams.cost.body", chosenTeams.count))
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.t("arena.title")).font(.sfCardTitle)
                Text(model.t(mode == .models ? "arena.subtitle" : "arena.teams.subtitle"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $mode) {
                Text(model.t("arena.mode.models")).tag(ArenaMode.models)
                Text(model.t("arena.mode.teams")).tag(ArenaMode.teams)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(.bar)
        .zoomWindowOnDoubleClick()
    }

    // MARK: Task + entrants

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("arena.task")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            TextEditor(text: $arena.prompt)
                .font(.sfBodyM).frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.insetBg))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if arena.prompt.isEmpty {
                        Text(model.t("arena.task.placeholder")).font(.sfBodyM).foregroundStyle(.tertiary)
                            .padding(.horizontal, Space.s + 5).padding(.vertical, Space.s + 8).allowsHitTesting(false)
                    }
                }
        }
        .card()
    }

    @ViewBuilder
    private var entrantsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("arena.entrants")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                runButton
            }
            if connected.isEmpty {
                Text(model.t("arena.noProviders")).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                FlowRow(spacing: Space.s) {
                    ForEach(connected) { p in entrantChip(p) }
                }
            }
        }
        .card()
    }

    private func entrantChip(_ p: AIProvider) -> some View {
        let on = selected.contains(p)
        let models = p.models
        return HStack(spacing: Space.xs) {
            ProviderAvatar(provider: p, size: 20, active: on)
            Text(p.displayName).font(.sfCaption2.weight(.medium))
            if models.count > 1 {
                Menu(shortModel(modelChoice[p] ?? models.first?.id ?? "", p)) {
                    ForEach(models) { m in
                        Button(m.displayName) { modelChoice[p] = m.id }
                    }
                }
                .font(.sfCaption2).fixedSize()
            } else if let m = models.first {
                Text(m.displayName).font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Space.s).padding(.vertical, 5)
        .background(Capsule().fill(on ? Theme.accentSoft : Color.clear))
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(on ? 0.5 : 0.15), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { if on { selected.remove(p) } else { selected.insert(p) } }
    }

    private func shortModel(_ id: String, _ p: AIProvider) -> String {
        p.models.first { $0.id == id }?.displayName ?? id
    }

    private var runButton: some View {
        Group {
            if arena.isRunning {
                Button(role: .cancel) { arena.cancel() } label: {
                    HStack(spacing: Space.xs) { WorkingLogo(size: 13); Text(model.t("arena.cancel")) }
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button {
                    arena.run(entrants: entrants, cwd: nil, runner: model.oneShotRunner(readOnly: true))
                } label: {
                    Label(model.t("arena.run"), systemImage: "flag.checkered")
                }
                .buttonStyle(.moon).controlSize(.small)
                .disabled(arena.prompt.trimmingCharacters(in: .whitespaces).isEmpty || entrants.count < 2)
            }
        }
    }

    // MARK: Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("arena.results")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                if arena.elapsed > 0 {
                    Text(String(format: "%.0fs", arena.elapsed)).font(.sfCaption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            if arena.isRunning && arena.outcomes.isEmpty {
                HStack(spacing: Space.s) { WorkingLogo(size: 16); Text(model.t("arena.running")).font(.sfCaption2).foregroundStyle(.secondary) }
                    .padding(.vertical, Space.m)
            }
            let cols = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Space.l, alignment: .top)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                ForEach(arena.outcomes) { outcome in resultCard(outcome) }
            }
        }
    }

    private func resultCard(_ outcome: ArenaOutcome) -> some View {
        let isWinner = arena.winnerID == outcome.id
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ProviderAvatar(provider: outcome.entrant.provider, size: 22, active: isWinner)
                VStack(alignment: .leading, spacing: 0) {
                    Text(outcome.entrant.provider.displayName).font(.sfBodyM.weight(.medium))
                    Text(shortModel(outcome.entrant.model, outcome.entrant.provider))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { arena.winnerID = outcome.id } label: {
                    Image(systemName: isWinner ? "trophy.fill" : "trophy")
                        .foregroundStyle(isWinner ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain).help(model.t("arena.pickWinner"))
                .disabled(!outcome.succeeded)
            }

            if let result = outcome.result {
                Text(result.text)
                    .font(.sfBodyM).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 260, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                metrics(result)
                HStack(spacing: Space.s) {
                    Button(model.t("arena.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.text, forType: .string)
                        model.flashSuccess(model.t("arena.copied"))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button(model.t("arena.sendToChat")) { sendToChat(outcome) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Label(outcome.error ?? model.t("arena.error"), systemImage: "exclamationmark.triangle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .fill(Theme.cardBg).elevation(isWinner ? .e3 : .e1))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(isWinner ? Theme.accent.opacity(0.4) : Theme.hairline, lineWidth: 1))
    }

    private func metrics(_ r: OneShotResult) -> some View {
        let tilde = r.estimated ? "~" : ""
        return HStack(spacing: Space.m) {
            metric("number", "\(tilde)\(fmtTokens(r.tokens))")
            metric("dollarsign.circle", r.costUSD > 0 ? String(format: "%@$%.3f", tilde, r.costUSD) : "—")
        }
        .font(.sfCaption2.monospaced()).foregroundStyle(.secondary)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 3) { Image(systemName: icon).font(.system(size: 9)); Text(value) }
    }

    private func fmtTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Carry the winning provider forward: open a fresh chat on it, seeded with the task
    /// so the user can keep iterating with the model that won.
    private func sendToChat(_ outcome: ArenaOutcome) {
        model.addConfiguration(provider: outcome.entrant.provider)
        if let id = model.selectedConfigID { model.updateDraft(id, arena.prompt) }
    }

    // MARK: - Teams mode

    private var availableTeams: [StrategyContestant] {
        let saved = model.savedTeams.map {
            StrategyContestant(id: "saved:\($0.id.uuidString)", name: $0.name, strategy: $0.strategy)
        }
        let curated = StrategyLibrary.all.map {
            StrategyContestant(id: "lib:\($0.id)", name: $0.name, strategy: $0)
        }
        return saved + curated
    }
    private var chosenTeams: [StrategyContestant] { availableTeams.filter { selectedTeams.contains($0.id) } }

    @ViewBuilder
    private var teamsCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("arena.teams.pick")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
                Spacer()
                teamsRunButton
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(availableTeams) { c in teamRow(c) }
                }
            }
            .frame(maxHeight: 240)
            Text(model.t("arena.teams.hint")).font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func teamRow(_ c: StrategyContestant) -> some View {
        let on = selectedTeams.contains(c.id)
        let providers = Array(Set(c.strategy.roles.map(\.provider))).sorted { $0.rawValue < $1.rawValue }
        return HStack(spacing: Space.s) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.sfBodyM.weight(.medium)).lineLimit(1)
                Text(model.t("arena.teams.makeup", c.strategy.roles.count))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: -5) { ForEach(providers) { p in ProviderAvatar(provider: p, size: 18) } }
        }
        .padding(.vertical, 5).padding(.horizontal, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(on ? Theme.accentSoft.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if on { selectedTeams.remove(c.id) } else { selectedTeams.insert(c.id) } }
    }

    private var teamsRunButton: some View {
        Group {
            if arena.isRunningTeams {
                Button(role: .cancel) { arena.cancelTeams() } label: {
                    HStack(spacing: Space.xs) { WorkingLogo(size: 13); Text(model.t("arena.cancel")) }
                }
                .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button { showTeamCostConfirm = true } label: {
                    Label(model.t("arena.run"), systemImage: "flag.checkered")
                }
                .buttonStyle(.moon).controlSize(.small)
                .disabled(arena.prompt.trimmingCharacters(in: .whitespaces).isEmpty || chosenTeams.count < 2)
            }
        }
    }

    private var teamsResultsSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("arena.results")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.8)
            // A 1s heartbeat keeps every card's elapsed timer ticking while running, so a
            // slow team visibly progresses instead of looking frozen.
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let cols = [GridItem(.adaptive(minimum: 320, maximum: 440), spacing: Space.l, alignment: .top)]
                LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                    ForEach(arena.teamOrder) { c in teamResultCard(c, now: context.date) }
                }
            }
        }
    }

    private func teamResultCard(_ c: StrategyContestant, now: Date) -> some View {
        let p = arena.teamProgress[c.id] ?? StrategyRunProgress()
        let isWinner = arena.teamWinnerID == c.id
        let elapsed = arena.teamStart[c.id].map { (arena.teamEnd[c.id] ?? now).timeIntervalSince($0) } ?? 0
        let providers = Array(Set(c.strategy.roles.map(\.provider))).sorted { $0.rawValue < $1.rawValue }
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                HStack(spacing: -5) { ForEach(providers) { pr in ProviderAvatar(provider: pr, size: 20, active: isWinner) } }
                Text(c.name).font(.sfBodyM.weight(.medium)).lineLimit(1)
                Spacer()
                if p.state == .done {
                    Button { arena.teamWinnerID = c.id } label: {
                        Image(systemName: isWinner ? "trophy.fill" : "trophy")
                            .foregroundStyle(isWinner ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain).help(model.t("arena.pickWinner"))
                }
            }

            liveStatus(p, elapsed: elapsed)

            switch p.state {
            case .done:
                if let answer = p.answer {
                    Text(answer).font(.sfBodyM).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(maxHeight: 240, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s) {
                        Button(model.t("arena.copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(answer, forType: .string)
                            model.flashSuccess(model.t("arena.copied"))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            case .failed:
                Label(p.error ?? model.t("arena.error"), systemImage: "exclamationmark.triangle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
            case .queued, .running:
                EmptyView()
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .fill(Theme.cardBg).elevation(isWinner ? .e3 : .e1))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(isWinner ? Theme.accent.opacity(0.4) : Theme.hairline, lineWidth: 1))
    }

    /// The transparency line: exactly what a team is doing right now + a ticking clock, so
    /// a multi-minute run never reads as "stuck".
    @ViewBuilder
    private func liveStatus(_ p: StrategyRunProgress, elapsed: TimeInterval) -> some View {
        HStack(spacing: Space.s) {
            switch p.state {
            case .queued:
                Image(systemName: "clock").font(.sfCaption2).foregroundStyle(.secondary)
                Text(model.t("arena.state.queued")).font(.sfCaption2).foregroundStyle(.secondary)
            case .running:
                WorkingLogo(size: 13)
                Text(phaseLabel(p.phase)).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.sfCaption2).foregroundStyle(Theme.success)
                Text(model.t("arena.state.done")).font(.sfCaption2).foregroundStyle(Theme.success)
            case .failed:
                EmptyView()
            }
            Spacer()
            // Live metrics — tokens/cost accumulate, elapsed ticks.
            if p.tokens > 0 || elapsed > 0 {
                Text(liveMetrics(p, elapsed: elapsed))
                    .font(.sfCaption2.monospaced()).foregroundStyle(.secondary)
            }
        }
        // Active agents right now — the "it's alive" signal.
        if p.state == .running, !p.activeRoles.isEmpty {
            FlowRow(spacing: 4) {
                ForEach(p.activeRoles, id: \.self) { role in
                    Text(role).font(.sfCaption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accentSoft))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "plan": return model.t("arena.phase.plan")
        case "delegate": return model.t("arena.phase.delegate")
        case "synthesize": return model.t("arena.phase.synthesize")
        default: return model.t("arena.state.running")
        }
    }

    private func liveMetrics(_ p: StrategyRunProgress, elapsed: TimeInterval) -> String {
        let tilde = p.estimated ? "~" : ""
        let secs = Int(elapsed.rounded())
        let time = secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
        let cost = p.costUSD > 0 ? String(format: " · %@$%.3f", tilde, p.costUSD) : ""
        return "\(tilde)\(fmtTokens(p.tokens)) tok\(cost) · \(time)"
    }
}

/// A minimal wrapping row (chips flow to the next line). Local, dependency-free.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
