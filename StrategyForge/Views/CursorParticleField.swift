//
//  CursorParticleField.swift
//  StrategyForge
//
//  The Antigravity landing-page background, retuned to Coral: a whole FIELD of tiny drifting
//  specks that SCATTER AWAY from the cursor — the pointer opens a calm bubble in the field and
//  the specks ease back home when it leaves. Mouse tracking uses SwiftUI's native
//  `.onContinuousHover` (reliable, no NSEvent-monitor lifecycle to get wrong — the earlier miss);
//  the specks also drift gently so the field is alive even before you move. One cheap Canvas.
//  Blank/static under Reduce Motion.
//

import SwiftUI

/// The mutable field state — a reference type so hover updates and the per-frame step mutate it
/// without churning SwiftUI @State (the Canvas reads it each frame).
private final class CursorFieldState {
    struct Speck {
        var hx: Double            // home position, as a fraction of the canvas (0…1)
        var hy: Double
        var x: CGFloat = 0        // live pixel position
        var y: CGFloat = 0
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var len: CGFloat          // half-length of the little dash
        var ang: Double           // orientation
        var phase: Double         // per-speck offset for the idle shimmer
        var colorIndex: Int
    }
    var specks: [Speck] = []
    var cursor: CGPoint = .zero
    var hasCursor = false
    private var seeded = false
    private var size: CGSize = .zero

    /// Lay `count` specks with homes biased AWAY from the centre (so they don't crowd the hero
    /// text) — sampled once. Pixel positions start at home.
    func seed(count: Int, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if seeded, self.size == size { return }
        self.size = size
        if !seeded {
            specks = (0..<count).map { _ in
                var hx = Double.random(in: 0...1), hy = Double.random(in: 0...1)
                for _ in 0..<2 {                              // thin the centre so text stays clean
                    let dx = hx - 0.5, dy = hy - 0.5
                    if (dx * dx) / (0.30 * 0.30) + (dy * dy) / (0.22 * 0.22) < 1 {
                        hx = Double.random(in: 0...1); hy = Double.random(in: 0...1)
                    }
                }
                return Speck(hx: hx, hy: hy,
                             len: CGFloat.random(in: 1.6...3.2),
                             ang: Double.random(in: 0..<(2 * .pi)),
                             phase: Double.random(in: 0..<(2 * .pi)),
                             colorIndex: Int.random(in: 0..<4))
            }
            seeded = true
        }
        for i in specks.indices {
            specks[i].x = CGFloat(specks[i].hx) * size.width
            specks[i].y = CGFloat(specks[i].hy) * size.height
        }
    }

    /// One physics step: idle shimmer around home, a strong PUSH away from the cursor within a
    /// radius (the bubble), damping, integrate.
    func step(size: CGSize, time: Double) {
        guard seeded else { return }
        let radius: CGFloat = 200
        for i in specks.indices {
            var p = specks[i]
            // Home target with a slow sinusoidal wander, so the field breathes even at rest.
            let driftX = CGFloat(cos(time * 0.5 + p.phase)) * 6
            let driftY = CGFloat(sin(time * 0.42 + p.phase)) * 6
            let homeX = CGFloat(p.hx) * size.width + driftX
            let homeY = CGFloat(p.hy) * size.height + driftY
            p.vx += (homeX - p.x) * 0.028
            p.vy += (homeY - p.y) * 0.028
            if hasCursor {
                let dx = p.x - cursor.x, dy = p.y - cursor.y
                let d2 = dx * dx + dy * dy
                if d2 < radius * radius {
                    let d = max(sqrt(d2), 0.01)
                    let falloff = 1 - d / radius
                    let push = falloff * falloff * 9.0        // strong, smooth (quadratic) shove
                    p.vx += dx / d * push
                    p.vy += dy / d * push
                }
            }
            p.vx *= 0.88; p.vy *= 0.88
            p.x += p.vx; p.y += p.vy
            specks[i] = p
        }
    }
}

struct CursorParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many specks fill the field. Cheap enough to be generous.
    var count: Int = 160
    @State private var field = CursorFieldState()

    /// Coral-family palette — warm, on-brand (no cool blues like the reference).
    private static let palette: [Color] = [Theme.coral, Theme.coralDeep, Theme.warning, Theme.accent]

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { ctx, size in
                    field.seed(count: count, size: size)
                    field.step(size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    for p in field.specks {
                        let c = Self.palette[p.colorIndex % Self.palette.count]
                        let hx = CGFloat(cos(p.ang)) * p.len
                        let hy = CGFloat(sin(p.ang)) * p.len
                        var path = Path()
                        path.move(to: CGPoint(x: p.x - hx, y: p.y - hy))
                        path.addLine(to: CGPoint(x: p.x + hx, y: p.y + hy))
                        ctx.stroke(path, with: .color(c.opacity(0.6)),
                                   style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                    }
                }
            }
            // Native hover tracking — fires reliably in the view's own coordinate space.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): field.cursor = p; field.hasCursor = true
                case .ended:         field.hasCursor = false
                }
            }
        }
    }
}
