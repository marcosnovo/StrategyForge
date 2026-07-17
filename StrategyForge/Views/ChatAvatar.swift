//
//  ChatAvatar.swift
//  StrategyForge
//
//  A per-chat leading tile. It used to be a gradient seeded from a random hue of the
//  chat's UUID — decorative noise that competed with the coral selection state and
//  encoded nothing. Now it's a calm, MEANINGFUL tile: a neutral inset surface, the
//  team-shape glyph (what kind of team this is), a small provider corner dot (which
//  AI), and a state restyle — teal edge/glyph while running, coral while it needs you.
//  Color in the list now means exactly two things: provider (the dot) and state.
//

import SwiftUI

struct ChatAvatar: View {
    let config: Configuration
    var size: CGFloat = 38
    /// The chat is working right now (teal accent), or finished/awaiting a decision
    /// while you were away (coral accent). Both restyle the same neutral tile.
    var running: Bool = false
    var attention: Bool = false
    /// Whether to show the provider corner dot. Only meaningful when the list mixes
    /// providers — for a single-provider user it's noise (and a coral Claude dot reads
    /// as a false "needs you" alert), so the list hides it.
    var showProvider: Bool = true
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model

    var body: some View {
        // State restyle — coral (needs you) outranks teal (running) outranks rest.
        let glyphColor: Color = attention ? Theme.accent : (running ? Theme.teal : Theme.secondaryOnMaterial)
        let stroke: Color = attention ? Theme.selectionBorder : (running ? Theme.tealEdge : Theme.hairline)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.insetBg)
            .overlay {
                Image(systemName: Self.strategyGlyph(config.strategy))
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(glyphColor)
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) { if showProvider { providerDot } }
            .frame(width: size, height: size)
            .help(config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name)
            .accessibilityLabel(config.name.isEmpty ? model.strategyDisplayName(config.strategy) : config.name)
    }

    /// Provider identity as a small solid dot (not a glyph badge — an 8pt dot is more
    /// legible than a tiny SF Symbol and reads instantly as an identity pip). The exact
    /// provider name is available on hover via the tile's `.help`.
    private var providerDot: some View {
        Circle()
            .fill(config.provider.tint)
            .frame(width: size * 0.24, height: size * 0.24)
            .overlay(Circle().strokeBorder(Theme.insetBg, lineWidth: 1.5))
            .help(config.provider.displayName)
            .offset(x: 2, y: 2)
    }

    // MARK: Shape mapping (shared)

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

// MARK: - Iridescent sphere (Aetheris assistant avatar)

/// The app's own 3D globe — the "Sphere" figure from the in-app particle set: a
/// Fibonacci globe of coral dots, depth-shaded and gently rotating (still under
/// Reduce Motion). Used as the assistant avatar and the empty-state hero. Wraps
/// `Particle3DSpinner` so callers just pass a size.
struct CoralSphere: View {
    var size: CGFloat = 28
    /// Pass `false` on a resting bubble so the globe holds a still frame instead of
    /// spinning a Canvas at 30fps for the whole transcript's lifetime.
    var animating: Bool = true
    var body: some View {
        Particle3DSpinner(size: size, color: Theme.accent, figure: .sphere, animating: animating)
            .accessibilityHidden(true)
    }
}
