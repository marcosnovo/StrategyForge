//
//  ContextWindow.swift
//  StrategyForge
//
//  A Claude-Code-style "context window" breakdown: how much of the model's context
//  the current chat is using, split by category (messages, system prompt, tools,
//  MCP tools, skills, free space) + the account's plan limits. The split is an
//  honest ESTIMATE (headless Claude doesn't report per-category occupancy), so it's
//  labelled as such; the plan-limit rows come from the real ~/.claude logs.
//

import SwiftUI

/// An estimated breakdown of the current context-window occupancy.
struct ContextBreakdown: Equatable {
    var messages: Int
    var systemPrompt: Int
    var tools: Int
    var mcp: Int
    var skills: Int
    var maxTokens: Int

    var used: Int { messages + systemPrompt + tools + mcp + skills }
    var free: Int { max(maxTokens - used, 0) }
    var fraction: Double { maxTokens > 0 ? min(Double(used) / Double(maxTokens), 1) : 0 }

    /// ~3.5 chars/token is a decent English/Spanish approximation; the system prompt
    /// (CLAUDE.md + working agreement), default toolset and MCP servers are coarse
    /// constants — enough to make the gauge meaningful without a tokenizer.
    static func estimate(transcript: [ChatMessage], strategy: Strategy, maxTokens: Int = 200_000) -> ContextBreakdown {
        let chars = transcript.reduce(0) { $0 + $1.text.count }
        return ContextBreakdown(
            messages: Int(Double(chars) / 3.5),
            systemPrompt: 3_500,
            tools: 12_000,
            mcp: strategy.mcpServers.count * 2_000,
            skills: 0,
            maxTokens: maxTokens)
    }

    /// The category rows, in display order (skips empties except messages/free).
    var segments: [(key: String, tokens: Int, color: Color)] {
        var out: [(String, Int, Color)] = [
            ("context.seg.messages", messages, Theme.accent),
            ("context.seg.system", systemPrompt, Theme.secondaryOnMaterial),
            ("context.seg.tools", tools, Theme.teal),
        ]
        if mcp > 0 { out.append(("context.seg.mcp", mcp, Theme.tealDeep)) }
        if skills > 0 { out.append(("context.seg.skills", skills, Theme.warning)) }
        out.append(("context.seg.free", free, Theme.hairline))
        return out
    }
}

/// The composer chip: a compact context gauge that opens the breakdown popover.
struct ContextWindowChip: View {
    @Environment(AppModel.self) private var model
    let breakdown: ContextBreakdown
    @State private var open = false

    private var color: Color {
        switch breakdown.fraction {
        case ..<0.5: return Theme.secondaryOnMaterial
        case ..<0.8: return Theme.warning
        default: return Theme.danger
        }
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 5) {
                gauge
                Text("\(Int((breakdown.fraction * 100).rounded()))%")
                    .font(.sfCaption2.weight(.medium)).foregroundStyle(color).monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .help(model.t("context.title"))
        .popover(isPresented: $open, arrowEdge: .bottom) { ContextWindowPopover(breakdown: breakdown) }
    }

    private var gauge: some View {
        Circle()
            .trim(from: 0, to: max(0.02, breakdown.fraction))
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 12, height: 12)
            .background(Circle().stroke(Theme.hairline, lineWidth: 2).frame(width: 12, height: 12))
    }
}

/// The breakdown popover (stacked bar + per-category rows + plan limits).
struct ContextWindowPopover: View {
    @Environment(AppModel.self) private var model
    let breakdown: ContextBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(model.t("context.title")).font(.sfCardTitle)
                Spacer()
                Text("\(fmt(breakdown.used)) / \(fmt(breakdown.maxTokens)) · \(Int((breakdown.fraction * 100).rounded()))%")
                    .font(.sfCaption2).foregroundStyle(.secondary).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: Space.m) {
                // Stacked bar of the categories.
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(breakdown.segments, id: \.key) { seg in
                            Rectangle().fill(seg.color)
                                .frame(width: max(0, geo.size.width * Double(seg.tokens) / Double(max(breakdown.maxTokens, 1))))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)

                VStack(spacing: 5) {
                    ForEach(breakdown.segments, id: \.key) { seg in
                        HStack(spacing: Space.s) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(seg.color).frame(width: 9, height: 9)
                            Text(model.t(seg.key)).font(.sfCaption2)
                            Spacer()
                            Text(fmt(seg.tokens)).font(.sfCaption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text("\(Int((Double(seg.tokens) / Double(max(breakdown.maxTokens, 1)) * 100).rounded()))%")
                                .font(.sfCaption2).foregroundStyle(.tertiary).monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg))

            Text(model.t("context.estimate")).font(.system(size: 9)).foregroundStyle(.tertiary)

            // Real plan limits from the local logs.
            if let u = model.claudeUsage, u.hasData {
                Divider()
                Text(model.t("context.limits")).font(.sfFieldLabel)
                    .foregroundStyle(.tertiary).tracking(0.6)
                limitRow(model.t("usage.fiveHour"), u.blockResetAt.map { resetText($0) } ?? model.t("usage.noActiveWindow"))
                limitRow(model.t("usage.week"), fmt(u.weekTokens))
            }
        }
        .padding(Space.l)
        .frame(width: 320)
    }

    private func limitRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.sfCaption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.sfCaption2.weight(.medium)).foregroundStyle(.primary).monospacedDigit()
        }
    }

    private func resetText(_ date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(Date())))
        let h = s / 3600, m = (s % 3600) / 60
        return model.t("usage.resetsIn", h > 0 ? "\(h)h \(m)m" : "\(m)m")
    }

    private func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
