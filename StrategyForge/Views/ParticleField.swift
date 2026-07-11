//
//  ParticleField.swift
//  StrategyForge
//
//  The app's motion identity: a quiet dot/particle system (inspired by
//  getthinkable.com) used for spinners, waiting/empty states, and ambient accents.
//  Pure SwiftUI Canvas + TimelineView (no SpriteKit — too heavy for a spinner). One
//  coherent language: a field of small dots with a soft coral glow that travels.
//  Honors accessibilityReduceMotion (falls back to a still frame).
//

import SwiftUI

/// A compact dot-ring spinner: 12 dots on a circle with a coral glow wave rotating
/// around them. The app's standard "working / waiting" indicator.
struct DotSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var dots: Int = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let radius = min(sz.width, sz.height) / 2 - sz.width * 0.13
                let base = max(1.3, sz.width * 0.085)
                let phase = (t * 1.15).truncatingRemainder(dividingBy: 1.0)
                for i in 0..<dots {
                    let frac = Double(i) / Double(dots)
                    let ang = frac * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + cos(ang) * radius, y: c.y + sin(ang) * radius)
                    // Circular distance of this dot from the travelling glow (0…0.5).
                    let d = abs(frac - phase)
                    let near = min(d, 1 - d)
                    let intensity = pow(max(0, 1 - near * 3.2), 2)   // sharp coral pulse
                    // Resting dot.
                    ctx.fill(dot(p, base),
                             with: .color(color.opacity(0.20 + 0.12 * intensity)))
                    // Glow + bright core for the ones the wave is passing.
                    if intensity > 0.04 {
                        let g = base * (1 + 2.4 * intensity)
                        ctx.fill(dot(p, g), with: .color(color.opacity(0.16 * intensity)))
                        ctx.fill(dot(p, base), with: .color(color.opacity(0.45 + 0.55 * intensity)))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func dot(_ p: CGPoint, _ d: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
}

/// A calm scattered dot field for large empty/ambient states: dots on a disc, a
/// slow coral glow wandering across a few of them. Deterministic (seeded), so it's
/// stable across redraws and testable-looking.
struct ParticleField: View {
    var color: Color = Theme.accent
    var density: Int = 90
    var reactive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let R = min(sz.width, sz.height) / 2 - 6
                // Two slow glow centres wandering around the disc.
                let g1 = CGPoint(x: c.x + cos(t * 0.23) * R * 0.55,
                                 y: c.y + sin(t * 0.19) * R * 0.55)
                let g2 = CGPoint(x: c.x + cos(t * 0.17 + 2.1) * R * 0.5,
                                 y: c.y + sin(t * 0.27 + 1.3) * R * 0.5)
                for i in 0..<density {
                    // Deterministic golden-angle spiral placement (no RNG).
                    let f = Double(i) / Double(density)
                    let rr = R * CGFloat(sqrt(f))
                    let aa = Double(i) * 2.399963  // golden angle
                    let p = CGPoint(x: c.x + cos(aa) * rr, y: c.y + sin(aa) * rr)
                    let size = CGFloat(1.2 + 1.6 * ((Double(i) * 0.61803).truncatingRemainder(dividingBy: 1)))
                    // Nearness to a glow centre → coral highlight.
                    let near = min(hypot(p.x - g1.x, p.y - g1.y), hypot(p.x - g2.x, p.y - g2.y))
                    let lit = reactive ? pow(max(0, 1 - near / (R * 0.32)), 2.2) : 0
                    ctx.fill(dot(p, size + CGFloat(lit) * 2),
                             with: .color(color.opacity(0.14 + 0.55 * lit)))
                    if lit > 0.15 {
                        let g = (size + 3) * CGFloat(1 + lit * 2)
                        ctx.fill(dot(p, g), with: .color(color.opacity(0.14 * lit)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(_ p: CGPoint, _ d: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
}

#Preview("Spinner") {
    HStack(spacing: 24) {
        DotSpinner(size: 20)
        DotSpinner(size: 32)
        DotSpinner(size: 48, color: Theme.teal)
    }
    .padding(40).background(Theme.appBg)
}
#Preview("Field") {
    ParticleField().frame(width: 260, height: 260).padding().background(Theme.appBg)
}
