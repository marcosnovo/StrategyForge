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
                claudeSection
                otherProvidersSection
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
                Spacer()
                if let u = model.claudeUsage, let last = u.lastActivity {
                    Text(model.t("usage.lastActivity", relative(last)))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
            }

            if let usage = model.claudeUsage, usage.hasData {
                HStack(alignment: .top, spacing: Space.l) {
                    fiveHourCard(usage).frame(width: 230)
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
            UsageRing(fraction: blockFraction(usage), label: formatTokens(usage.blockTokens))
                .frame(width: 130, height: 130)
            Text(model.t("usage.fiveHour")).font(.sfFieldLabel)
                .foregroundStyle(.secondary).tracking(0.6)
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
            if usage.weekByModel.isEmpty {
                Text(model.t("usage.noWeek")).font(.sfCaption2).foregroundStyle(.secondary)
            } else {
                ForEach(usage.weekByModel) { m in
                    modelBar(m, total: usage.weekTokens)
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
            HStack {
                Text(m.model).font(.sfCaption2.weight(.medium))
                Spacer()
                Text("\(Int((frac * 100).rounded()))%")
                    .font(.sfCaption2).foregroundStyle(.secondary)
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
            DotSpinner(size: 16)
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

    // MARK: - Other providers

    private var otherProvidersSection: some View {
        ForEach([AIProvider.openai, AIProvider.gemini]) { p in
            HStack(spacing: Space.m) {
                ProviderLogo(provider: p, size: 26, templateTint: p.tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(p.tint.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.displayName).font(.sfCallout.weight(.semibold))
                    Text(model.t("usage.noProviderData"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.t(model.isConnected(p) ? "provider.connected" : "provider.notFound"))
                    .font(.sfCaption2.weight(.medium))
                    .foregroundStyle(model.isConnected(p) ? Theme.success : Theme.secondaryOnMaterial)
                    .padding(.horizontal, Space.s).padding(.vertical, 3)
                    .background(Capsule().fill((model.isConnected(p) ? Theme.success : Theme.inkDim).opacity(0.12)))
            }
            .card(padding: Space.m)
        }
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
}

/// A thin circular progress ring with a centered label.
struct UsageRing: View {
    let fraction: Double
    let label: String

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
                Text("tokens").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
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
