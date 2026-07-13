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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                spendByProviderCard
                claudeSection
                if model.configurations.contains(where: { $0.totalTokens > 0 }) {
                    topChatsCard
                }
                // Token Saver: the curated habits that keep the numbers above low.
                TokenSaverGuideView()
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .task { if model.claudeUsage == nil { await model.refreshUsage() } }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("usage.title")).font(.sfDisplay)
                Text(model.t("usage.subtitle")).font(.sfCallout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshUsage() }
            } label: {
                Label(model.t("usage.refresh"), systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isRefreshingUsage)
            }
            .controlSize(.large)
            .disabled(model.isRefreshingUsage)
        }
        .zoomWindowOnDoubleClick()
    }

    // MARK: - Claude

    @ViewBuilder
    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: .claude, size: 20)
                Text(AIProvider.claude.displayName).font(.sfCardTitle)
                planBadge(.claude)
                Spacer()
                if let u = model.claudeUsage, let last = u.lastActivity {
                    Text(model.t("usage.lastActivity", relative(last)))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
            }

            if let usage = model.claudeUsage, usage.hasData {
                HStack(alignment: .top, spacing: Space.l) {
                    fiveHourCard(usage).frame(width: 230)
                        .staggeredAppear(index: 0)
                    weeklyCard(usage).frame(maxWidth: .infinity)
                }
            } else if model.isRefreshingUsage {
                loadingCard
            } else {
                emptyCard
            }
        }
        .card()
    }

    private func fiveHourCard(_ usage: UsageSummary) -> some View {
        VStack(spacing: Space.s) {
            UsageRing(fraction: blockFraction(usage), label: formatTokens(usage.blockTokens),
                      caption: model.t("usage.ring.tokens"))
                .frame(width: 130, height: 130)
            HStack(spacing: Space.xs) {
                Text(model.t("usage.fiveHour")).font(.sfFieldLabel)
                    .foregroundStyle(.secondary).tracking(0.6)
                InfoPopoverButton(text: model.t("usage.fiveHour.help"))
            }
            if let reset = usage.blockResetAt {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(model.t("usage.resetsIn", countdown(to: reset, now: ctx.date)))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
            } else {
                Text(model.t("usage.noActiveWindow")).font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private func weeklyCard(_ usage: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(model.t("usage.sevenDay")).font(.sfFieldLabel)
                    .foregroundStyle(.secondary).tracking(0.6)
                Spacer()
                Text(formatTokens(usage.weekTokens)).font(.sfMono).foregroundStyle(Theme.accent)
            }
            Text(model.t("usage.week.gloss")).font(.sfCaption2).foregroundStyle(.tertiary)
            if usage.weekByModel.isEmpty {
                Text(model.t("usage.noWeek")).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                ForEach(Array(usage.weekByModel.enumerated()), id: \.element.id) { index, m in
                    modelBar(m, total: usage.weekTokens)
                        .staggeredAppear(index: index + 1)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private func modelBar(_ m: ModelUsage, total: Int) -> some View {
        let frac = total > 0 ? Double(m.tokens) / Double(total) : 0
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
                    Capsule().fill(Theme.primaryFill).frame(width: max(5, geo.size.width * frac), height: 7)
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
                Image(systemName: "person.text.rectangle").font(.system(size: 9))
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
                Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }
}

private struct UsagePreviewHost: View {
    @State private var model: AppModel = {
        let m = AppModel()
        m.claudeUsage = UsageSummary(
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
