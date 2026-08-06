//
//  CursorParticleField.swift
//  StrategyForge
//
//  A living Coral ORB behind the empty chat: a centred cloud of soft glowing dots that slowly
//  rotate as one body (a galaxy, not a swarm of bugs — every position is analytic from angle+time,
//  so there's no per-dot jitter). As the cursor nears, the dots around it ARE DRAWN TOWARD it and
//  fade out — they approach and disappear — then reappear as it moves on. Glow via a blurred bloom
//  pass. Blank under Reduce Motion.
//

import SwiftUI

/// Immutable-ish dot definition + the live cursor. A reference type so hover updates don't churn
/// SwiftUI @State; the Canvas reads it each frame.
private final class OrbFieldState {
    struct Dot {
        var angle: Double        // base angle around the orb centre
        var radius: Double       // 0…1 fraction of the orb radius (denser toward the middle)
        var size: CGFloat        // dot radius in points
        var spin: Double         // per-dot angular-speed multiplier (parallax)
        var colorIndex: Int
    }
    var dots: [Dot] = []
    var cursor: CGPoint = .zero
    var hasCursor = false
    private var seeded = false

    func seed(count: Int) {
        guard !seeded else { return }
        dots = (0..<count).map { _ in
            Dot(angle: Double.random(in: 0..<(2 * .pi)),
                radius: pow(Double.random(in: 0...1), 0.62),   // bias inward → reads as an orb
                size: CGFloat.random(in: 1.7...3.4),
                spin: Double.random(in: 0.6...1.4),
                colorIndex: Int.random(in: 0..<4))
        }
        seeded = true
    }
}

struct CursorParticleField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var count: Int = 170
    @State private var orb = OrbFieldState()

    /// Coral-family palette — VIVID, saturated warm tones (no muddy brick accent) so the specks
    /// read as bright colour fills.
    private static let palette: [Color] = [
        Theme.coral,
        Color(hue: 0.02, saturation: 0.92, brightness: 1.0),   // neon coral-red
        Color(hue: 0.09, saturation: 0.95, brightness: 1.0),   // electric orange
        Color(hue: 0.14, saturation: 0.90, brightness: 1.0),   // fluor gold
    ]

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                Canvas { ctx, size in
                    orb.seed(count: count)
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let cx = size.width / 2, cy = size.height / 2
                    let R = min(size.width, size.height) * 0.46
                    let influence: CGFloat = 160

                    // Resolve every dot's screen position + alpha + size ONCE (shared by both passes).
                    var frame: [(p: CGPoint, r: CGFloat, a: Double, c: Color)] = []
                    frame.reserveCapacity(orb.dots.count)
                    for dot in orb.dots {
                        let ang = dot.angle + t * 0.05 * dot.spin                 // slow galaxy spin
                        let breathe = 1 + 0.03 * sin(t * 0.5 + dot.angle)          // gentle life
                        let rad = dot.radius * Double(R) * breathe
                        var x = cx + CGFloat(cos(ang)) * CGFloat(rad)
                        var y = cy + CGFloat(sin(ang)) * CGFloat(rad)
                        var alpha = 0.85
                        var r = dot.size
                        if orb.hasCursor {
                            let dx = orb.cursor.x - x, dy = orb.cursor.y - y
                            let dist = max(sqrt(dx * dx + dy * dy), 0.01)
                            if dist < influence {
                                let ease = pow(1 - dist / influence, 1.6)          // 0…1, near→1
                                x += dx * ease * 0.8                                // approach cursor
                                y += dy * ease * 0.8
                                alpha *= Double(1 - ease)                           // …and fade away
                                r *= (1 - 0.6 * ease)
                            }
                        }
                        frame.append((CGPoint(x: x, y: y), r, alpha,
                                      Self.palette[dot.colorIndex % Self.palette.count]))
                    }

                    // GLOW pass — a bright coloured bloom (small blur) so each speck glows.
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 3))
                        for f in frame where f.a > 0.02 {
                            let gr = f.r * 2.4
                            layer.fill(Path(ellipseIn: CGRect(x: f.p.x - gr, y: f.p.y - gr, width: 2 * gr, height: 2 * gr)),
                                       with: .color(f.c.opacity(f.a * 0.95)))
                        }
                    }
                    // CRISP cores — fully saturated, fully opaque (founder: "rellenas de color y
                    // más brillantes"). A tiny off-centre highlight gives a lit-bead sheen without
                    // washing the colour to white.
                    for f in frame where f.a > 0.02 {
                        ctx.fill(Path(ellipseIn: CGRect(x: f.p.x - f.r, y: f.p.y - f.r, width: 2 * f.r, height: 2 * f.r)),
                                 with: .color(f.c.opacity(min(1, f.a * 1.6))))
                        let hr = f.r * 0.4
                        let hp = CGPoint(x: f.p.x - f.r * 0.28, y: f.p.y - f.r * 0.28)
                        ctx.fill(Path(ellipseIn: CGRect(x: hp.x - hr, y: hp.y - hr, width: 2 * hr, height: 2 * hr)),
                                 with: .color(f.c.mix(with: .white, by: 0.5).opacity(f.a * 0.8)))
                    }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p): orb.cursor = p; orb.hasCursor = true
                case .ended:         orb.hasCursor = false
                }
            }
        }
    }
}
