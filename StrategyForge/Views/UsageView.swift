//
//  UsageView.swift
//  StrategyForge
//
//  A usage dashboard (ClaudeKarma-style) built from Claude's real local logs: a
//  5-hour rate-limit block gauge and a rolling 7-day per-model breakdown. Non-Claude
//  providers have no local usage to read via their CLIs, so they show a note.
//

import SwiftUI

struct UsageView: View {
    @Environment(AppModel.self) private var model
    /// Presents the Claude re-login flow from the usage card (so the exact rate-limit
    /// data — which lives behind Claude's own login — can come back after a refresh).
    @State private var reconnectingClaude = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                providerUsageGrid
                // The cross-provider spend roll-up sits BELOW the per-provider detail.
                spendByProviderCard
                if model.configurations.contains(where: { $0.totalTokens > 0 }) {
                    topChatsCard
                }
                // Token Saver: the curated habits that keep the numbers above low.
                TokenSaverGuideView()
                sourceDisclosure
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        // Opening the Usage section is deliberate intent — here (and only here) we also
        // fetch the exact rate-limit % (which reads the Keychain), attempted once/session.
        .task {
            if model.claudeUsage == nil { await model.refreshUsage() }
            await model.refreshExactUsage()
        }
    }

    /// Honest disclosure of WHERE the numbers come from — the Claude % is read from the
    /// Claude Code login token via an endpoint Anthropic doesn't document, so it can
    /// change or stop. Transparency for the privacy policy / ToS posture.
    private var sourceDisclosure: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(.tertiary)
            Text(model.t("usage.sourceDisclosure"))
                .font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.s)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("usage.title")).font(.sfDisplay)
                Text(model.t("usage.subtitle")).font(.sfCallout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshUsage(); await model.refreshExactUsage(force: true) }
            } label: {
                Label(model.t("usage.refresh"), systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isRefreshingUsage)
            }
            .controlSize(.large)
            .disabled(model.isRefreshingUsage)
        }
        .zoomWindowOnDoubleClick()
    }

    // MARK: - Per-provider usage (responsive grid)

    /// The per-provider usage cards in an adaptive grid: as many across as fit (3 on a
    /// wide window), wrapping to 2/1 as it narrows — so space is used and no card is
    /// left wide-and-empty.
    private var providerUsageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: .infinity), spacing: Space.l)],
                  alignment: .leading, spacing: Space.l) {
            claudeUsageCard
            codexUsageCard
            geminiUsageCard
        }
    }

    private func providerCardHeader(_ p: AIProvider, last: Date?) -> some View {
        HStack(spacing: Space.s) {
            ProviderLogo(provider: p, size: 18, templateTint: p.tint)
            Text(p.displayName).font(.sfCardTitle).lineLimit(1)
            planBadge(p)
            Spacer(minLength: 0)
            if let last {
                Text(model.t("usage.lastActivity", relative(last)))
                    .scaledFont(9).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private var claudeUsageCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            providerCardHeader(.claude, last: model.claudeUsage?.lastActivity)
            if let u = model.claudeUsage, u.hasData {
                if let e = model.claudeExact {
                    // Real rate-limit % from Claude's own endpoint (the exact numbers).
                    UsageRing(fraction: e.fiveHourPercent / 100,
                              label: "\(Int(e.fiveHourPercent.rounded()))%",
                              caption: model.t("usage.fiveHour"))
                        .frame(width: 96, height: 96).frame(maxWidth: .infinity)
                    if let r = e.fiveHourResetsAt {
                        TimelineView(.periodic(from: .now, by: 30)) { ctx in
                            Text(model.t("usage.resetsIn", countdown(to: r, now: ctx.date)))
                                .font(.sfCaption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                    modelPctBar(model.t("usage.sevenDay"), percent: e.weekPercent)
                } else {
                    // No exact data yet (signed out / not fetched) — 5h time-to-reset ring
                    // + a sign-in that unlocks the exact percentages.
                    UsageRing(fraction: blockFraction(u), label: fiveHourLabel(u),
                              caption: model.t("usage.fiveHour"))
                        .frame(width: 96, height: 96).frame(maxWidth: .infinity)
                    Button { reconnectingClaude = true } label: {
                        Label(model.t("usage.claude.exact"), systemImage: "arrow.up.forward.app")
                            .font(.sfCaption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.teal)
                    .frame(maxWidth: .infinity)
                }
                Divider()
                HStack {
                    Text(model.t("usage.sevenDay")).font(.sfFieldLabel).foregroundStyle(.secondary).tracking(0.6)
                    Spacer()
                    Text(formatTokens(u.weekTokens)).font(.sfMono).foregroundStyle(.secondary)
                }
                if u.weekByModel.isEmpty {
                    Text(model.t("usage.noWeek")).font(.sfCaption2).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(u.weekByModel.prefix(4).enumerated()), id: \.element.id) { i, m in
                        modelBar(m, total: u.weekTokens, index: i)
                    }
                }
            } else if model.isRefreshingUsage { loadingCard } else { emptyCard }
            Spacer(minLength: 0)
        }
        .equalCard()
        .sheet(isPresented: $reconnectingClaude) {
            ProviderConnectSheet(provider: .claude) { Task { await model.refreshUsage(); await model.refreshExactUsage(force: true) } }
        }
    }

    private var codexUsageCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            providerCardHeader(.openai, last: model.codexUsage?.lastActivity)
            if let c = model.codexUsage, let w = c.primary ?? c.secondary {
                UsageRing(fraction: w.usedPercent / 100, label: "\(Int(w.usedPercent.rounded()))%",
                          caption: model.t(w.kindLabelKey))
                    .frame(width: 96, height: 96).frame(maxWidth: .infinity)
                if let reset = w.resetsAt {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(model.t("usage.resetsIn", countdown(to: reset, now: ctx.date)))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                if let s = (c.primary != nil ? c.secondary : nil) {
                    modelPctBar(model.t(s.kindLabelKey), percent: s.usedPercent)
                }
            } else {
                providerEmpty(model.t("usage.codex.noWindows"))
            }
            Spacer(minLength: 0)
        }
        .equalCard()
    }

    private var geminiUsageCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            providerCardHeader(.gemini, last: nil)
            providerEmpty(model.t("usage.gemini.none"))
            Spacer(minLength: 0)
        }
        .equalCard()
    }

    /// A centered "no data" placeholder used inside a provider card.
    private func providerEmpty(_ text: String) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(.secondary)
            Text(text).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.l)
    }

    /// A labelled percentage bar (label + "%", teal fill) for a secondary window.
    private func modelPctBar(_ label: String, percent: Double) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label).font(.sfCaption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percent.rounded()))%").font(.sfCaption2.weight(.medium).monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline).frame(height: 6)
                    Capsule().fill(Theme.teal).frame(width: max(5, geo.size.width * min(percent / 100, 1)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    /// The Claude 5-hour ring's center label: time to reset, or "—" when idle.
    private func fiveHourLabel(_ u: UsageSummary) -> String {
        guard let reset = u.blockResetAt else { return "—" }
        return countdown(to: reset, now: Date())
    }

    private func modelBar(_ m: ModelUsage, total: Int, index: Int = 0) -> some View {
        let frac = total > 0 ? Double(m.tokens) / Double(total) : 0
        // Top spend = coral (primary); supporting models = teal (secondary series).
        let fill: Color = index == 0 ? Theme.accent : Theme.teal
        return VStack(spacing: 3) {
            HStack(spacing: Space.s) {
                Text(m.model).font(.sfCaption2.weight(.medium))
                Spacer()
                Text(formatTokens(m.tokens)).font(.sfCaption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.sfCaption2).foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline).frame(height: 7)
                    Capsule().fill(fill).frame(width: max(5, geo.size.width * frac), height: 7)
                }
            }
            .frame(height: 7)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: Space.s) {
            WorkingLogo(size: 16)
            Text(model.t("usage.loading")).font(.sfCallout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center).padding(Space.l)
    }

    private var emptyCard: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.secondary)
            Text(model.t("usage.empty")).font(.sfCallout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center).padding(Space.l)
    }

    // MARK: - Spend by provider (multi-agent overview)

    /// A single card comparing spend across every provider — the multi-agent usage
    /// summary. Tokens/cost are rolled up from this device's chats. Claude's dollars
    /// are real (from Claude Code); Codex/Gemini CLIs report no usage, so their bars
    /// reflect chats run, not tokens — flagged honestly.
    private var spendByProviderCard: some View {
        let spend = model.spendByProvider()
        let maxTokens = max(1, spend.map(\.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(Theme.accent)
                Text(model.t("usage.byProvider.title")).font(.sfCardTitle)
                Spacer()
                let totalCost = spend.reduce(0) { $0 + $1.costUSD }
                if totalCost > 0 {
                    Text(formatCost(totalCost)).font(.sfMono).foregroundStyle(Theme.accent)
                }
            }
            Text(model.t("usage.byProvider.hint")).font(.sfCaption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(spend) { s in providerSpendRow(s, maxTokens: maxTokens) }
        }
        .card()
    }

    private func providerSpendRow(_ s: AppModel.ProviderSpend, maxTokens: Int) -> some View {
        let p = s.provider
        let frac = Double(s.tokens) / Double(maxTokens)
        // Codex/Gemini report no token usage via their CLIs → make that explicit.
        let noTokenData = p != .claude && s.tokens == 0
        return VStack(spacing: 5) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: p, size: 18, templateTint: p.tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(p.tint.opacity(0.12)))
                Text(p.displayName).font(.sfCallout.weight(.semibold))
                planBadge(p)
                Spacer()
                if s.costUSD > 0 {
                    Text(formatCost(s.costUSD)).font(.sfCaption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Text(model.t("usage.byProvider.chats", s.chats))
                    .font(.sfCaption2).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: Space.s) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline).frame(height: 7)
                        Capsule().fill(p.tint)
                            .frame(width: max(s.tokens > 0 ? 5 : 0, geo.size.width * frac), height: 7)
                    }
                }
                .frame(height: 7)
                Text(noTokenData ? model.t("usage.byProvider.noTokens") : formatTokens(s.tokens))
                    .font(.sfCaption2).foregroundStyle(noTokenData ? .tertiary : .secondary)
                    .monospacedDigit().frame(minWidth: 54, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }

    /// A tappable plan pill — the user declares their plan (no CLI exposes it).
    private func planBadge(_ p: AIProvider) -> some View {
        let current = model.providerPlan(p)
        return Menu {
            ForEach(p.planOptions, id: \.self) { opt in
                Button {
                    model.setProviderPlan(opt, for: p)
                } label: {
                    if current == opt { Label(opt, systemImage: "checkmark") } else { Text(opt) }
                }
            }
            if current != nil {
                Divider()
                Button(model.t("usage.plan.clear"), role: .destructive) { model.setProviderPlan(nil, for: p) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.text.rectangle").scaledFont(9)
                Text(current ?? model.t("usage.plan.set")).font(.sfCaption2.weight(.medium))
            }
            .foregroundStyle(current == nil ? Theme.secondaryOnMaterial : p.tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill((current == nil ? Theme.inkDim : p.tint).opacity(0.12)))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    // MARK: - Top chats

    /// The chats that spent the most tokens, linking back into the chat list.
    private var topChatsCard: some View {
        let top = model.configurations
            .filter { $0.totalTokens > 0 }
            .sorted { $0.totalTokens > $1.totalTokens }
            .prefix(5)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("usage.topChats.title")).font(.sfCardTitle)
            Text(model.t("usage.topChats.hint")).font(.sfCaption2).foregroundStyle(.secondary)
            ForEach(Array(top)) { config in
                Button {
                    model.selectedConfigID = config.id
                    model.navSection = .chats
                } label: {
                    HStack {
                        Text(config.name.isEmpty ? model.t("chat.untitled") : config.name)
                            .font(.sfCallout).lineLimit(1)
                        Spacer()
                        Text(formatTokens(config.totalTokens))
                            .font(.sfMono).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Space.s).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverTint()
            }
        }
        .card()
    }

    // MARK: - Helpers

    /// The ring reflects how far the current 5-hour window has elapsed (time to
    /// reset) — an honest gauge, since Anthropic's token caps aren't published.
    private func blockFraction(_ usage: UsageSummary) -> Double {
        guard let start = usage.blockStart, let reset = usage.blockResetAt else { return 0 }
        let total = reset.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(max(elapsed / total, 0), 1)
    }

    private func countdown(to date: Date, now: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatCost(_ c: Double) -> String {
        c >= 10 ? String(format: "$%.0f", c) : String(format: "$%.2f", c)
    }
}

/// A thin circular progress ring with a centered label.
struct UsageRing: View {
    let fraction: Double
    let label: String
    /// The small unit caption under the number (localized by the caller).
    let caption: String

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(
                    AngularGradient(colors: [Theme.coral, Theme.coralDeep, Theme.coral],
                                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.accent.opacity(0.35), radius: 6)
            VStack(spacing: 0) {
                Text(label).font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text(caption).scaledFont(9, weight: .medium).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }
}

private struct UsagePreviewHost: View {
    @State private var model: AppModel = {
        let m = AppModel()
        m.usageStore.claudeUsage = UsageSummary(
            blockStart: Date().addingTimeInterval(-2 * 3600),
            blockResetAt: Date().addingTimeInterval(3 * 3600),
            blockTokens: 128_000,
            weekTokens: 3_400_000,
            weekByModel: [ModelUsage(model: "Opus 4.7", tokens: 2_400_000),
                          ModelUsage(model: "Sonnet 4.6", tokens: 900_000),
                          ModelUsage(model: "Haiku 4.5", tokens: 100_000)],
            lastActivity: Date().addingTimeInterval(-600),
            computedAt: Date())
        return m
    }()
    var body: some View {
        UsageView().environment(model).tint(Theme.accent).frame(width: 900, height: 640)
    }
}

#Preview { UsagePreviewHost() }
#Preview("Dark") { UsagePreviewHost().preferredColorScheme(.dark) }
