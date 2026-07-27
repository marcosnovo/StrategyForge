//
//  ClaudeUsagePill.swift
//  StrategyForge
//
//  A compact, always-glanceable Claude rate-limit indicator (the "Claude Karma" pattern):
//  the 5-hour utilization % — the window that throttles you FIRST — coloured calm→amber→red
//  as you near the cap, with both windows + reset countdowns in the tooltip. Tap opens the
//  Usage section (and refreshes). Renders NOTHING when the % isn't available (signed out /
//  not yet fetched) so it never shows a fake 0%. Used in the chat/Code header and the rail.
//

import SwiftUI

extension Theme {
    /// Colour for a rate-limit utilization %: calm/neutral while there's headroom, amber as
    /// you approach the cap, red when you're about to be throttled. One language everywhere.
    static func usageTint(_ percent: Double) -> Color {
        switch percent {
        case ..<80:  return Theme.secondaryOnMaterial
        case ..<92:  return Theme.warning
        default:     return Theme.danger
        }
    }
}

struct ClaudeUsagePill: View {
    @Environment(AppModel.self) private var model
    /// Rail = a vertical tile (icon over %); header = a horizontal chip.
    enum Style { case chip, tile }
    var style: Style = .chip

    var body: some View {
        if let e = model.claudeExact {
            let pct = max(e.fiveHourPercent, 0)
            let tint = Theme.usageTint(pct)
            Button {
                model.navSection = .usage
                Task { await model.refreshUsage(includeExact: true) }
            } label: {
                Group {
                    switch style {
                    case .chip:
                        HStack(spacing: 4) { gauge(tint); percentText(pct, tint) }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(tint.opacity(0.12)))
                    case .tile:
                        VStack(spacing: 1) { gauge(tint).font(.system(size: 15)); percentText(pct, tint) }
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tooltip(e))
            .accessibilityLabel(a11y(pct))
        }
    }

    private func gauge(_ tint: Color) -> some View {
        Image(systemName: "gauge.with.needle").font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
    }
    private func percentText(_ pct: Double, _ tint: Color) -> some View {
        Text("\(Int(pct.rounded()))%")
            .font(.sfCaption2.weight(.semibold)).monospacedDigit()
            .contentTransition(.numericText()).foregroundStyle(tint)
    }

    private func tooltip(_ e: ClaudeUsageAPI.Exact) -> String {
        func win(_ label: String, _ pct: Double, _ reset: Date?) -> String {
            var s = "\(label) \(Int(pct.rounded()))%"
            if let reset { s += " · " + model.t("usage.resetsIn", Self.rel(reset)) }
            return s
        }
        return "Claude · " + win("5h", e.fiveHourPercent, e.fiveHourResetsAt)
             + "   ·   " + win("7d", e.weekPercent, e.weekResetsAt)
    }
    private func a11y(_ pct: Double) -> String { model.t("usage.pill.a11y", Int(pct.rounded())) }

    private static func rel(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
