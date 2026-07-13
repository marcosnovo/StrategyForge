//
//  ChatAvatar.swift
//  StrategyForge
//
//  A per-chat identity avatar so chats are distinguishable at a glance in the list
//  (the old shared strategy mini-topology looked identical everywhere). Each chat
//  gets a deterministic gradient seeded from its id (stable across launches), a bold
//  monogram from its name — or the team-shape glyph while still untitled — and a
//  small provider corner badge. Cheap SwiftUI composition; no per-scroll animation.
//

import SwiftUI

struct ChatAvatar: View {
    let config: Configuration
    var size: CGFloat = 38
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model

    var body: some View {
        let hue = Self.seededHue(config.id) / 360
        let hi = Color(hue: hue, saturation: 0.55, brightness: scheme == .dark ? 0.62 : 0.82)
        let lo = Color(hue: hue, saturation: 0.78, brightness: scheme == .dark ? 0.42 : 0.58)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [hi, lo], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { mark }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) { providerBadge }
            .frame(width: size, height: size)
            .help(config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name)
            .accessibilityLabel(config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name)
    }

    /// Monogram from the name, or the team-shape glyph when still untitled — so even
    /// three brand-new chats differ (by shape + seeded color).
    @ViewBuilder private var mark: some View {
        if let mono = monogram {
            Text(mono)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        } else {
            Image(systemName: Self.strategyGlyph(config.strategy))
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var providerBadge: some View {
        Circle()
            .fill(config.provider.tint)
            .frame(width: size * 0.32, height: size * 0.32)
            .overlay(Image(systemName: config.provider.icon)
                .font(.system(size: size * 0.15, weight: .bold)).foregroundStyle(.white))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
            .offset(x: 3, y: 3)
    }

    private var monogram: String? {
        let name = config.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: Deterministic seeding (shared)

    /// Stable hue for a chat, folded from the raw UUID bytes (NOT `hashValue`, which
    /// Swift salts per launch). Discrete coral-anchored stops so a list reads as
    /// clearly different colors, not near-neighbors.
    static func seededHue(_ id: UUID) -> Double {
        let b = id.uuid
        var h: UInt64 = 0xcbf29ce484222325
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15] {
            h = (h ^ UInt64(byte)) &* 0x100000001b3
        }
        let stops: [Double] = [8, 20, 200, 210, 158, 172, 262, 275, 330, 342, 130, 44]
        return stops[Int(h % UInt64(stops.count))]
    }

    /// SF Symbol for a team's shape (derived from roles, so custom teams work too).
    static func strategyGlyph(_ s: Strategy) -> String {
        let subs = s.subagentRoles
        if subs.isEmpty { return "person.fill" }
        if subs.contains(where: { $0.role == .advisor }) { return "lightbulb.fill" }
        if subs.contains(where: { $0.role == .planner }) { return "list.bullet.clipboard.fill" }
        if !subs.isEmpty, subs.allSatisfy({ $0.role == .specialist }) { return "star.fill" }
        if subs.contains(where: { $0.role == .reviewer }) { return "bubble.left.and.bubble.right.fill" }
        return "arrow.triangle.branch"
    }

    /// Localization key for a short shape name shown in the list meta line.
    static func shortShapeKey(_ s: Strategy) -> String {
        let subs = s.subagentRoles
        if subs.isEmpty { return "shape.solo" }
        if subs.contains(where: { $0.role == .advisor }) { return "shape.advisor" }
        if subs.contains(where: { $0.role == .planner }) { return "shape.planner" }
        if !subs.isEmpty, subs.allSatisfy({ $0.role == .specialist }) { return "shape.specialists" }
        if subs.contains(where: { $0.role == .reviewer }) { return "shape.debate" }
        return "shape.fanout"
    }
}
