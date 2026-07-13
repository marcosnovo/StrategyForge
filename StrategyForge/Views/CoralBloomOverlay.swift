//
//  CoralBloomOverlay.swift
//  StrategyForge
//
//  The "Coral Bloom" — a short, self-terminating coral-particle bloom shown over the
//  chat the moment an agent turn finishes. It's the app's little wow beat: reuses the
//  golden-angle particle DNA of the brand loader, never blocks input, and honors
//  Reduce Motion. Every 25th completed turn it escalates (more dots + a teal accent)
//  so a returning user gets a periodic "you're building something" lift.
//

import SwiftUI

struct CoralBloomOverlay: View {
    /// Bump to fire a new bloom (the parent increments it on turn completion).
    var token: Int
    /// A milestone turn — bigger bloom with a teal second note.
    var milestone: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: Double = 1.8
    @State private var startDate: Date?
    @State private var active = false
    /// Reduce-Motion: a single calm dot whose opacity we fade out.
    @State private var staticOpacity: Double = 0

    var body: some View {
        Group {
            if reduceMotion {
                Circle()
                    .fill(Theme.coral)
                    .frame(width: 8, height: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(staticOpacity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { tl in
                    Canvas { ctx, size in draw(&ctx, size, now: tl.date) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: token) {
            guard token > 0 else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.15)) { staticOpacity = 0.7 }
                try? await Task.sleep(for: .seconds(0.15))
                withAnimation(.easeOut(duration: 0.5)) { staticOpacity = 0 }
                return
            }
            startDate = Date(); active = true
            try? await Task.sleep(for: .seconds(duration + 0.1))
            active = false; startDate = nil
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, now: Date) {
        guard let start = startDate else { return }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0, elapsed <= duration else { return }
        let p = elapsed / duration                              // overall progress 0…1
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rMax = min(size.width, size.height) * 0.26
        let n = milestone ? 20 : 12
        let ga = 2.399963                                       // golden angle

        // Ambient radial glow that swells then fades (self-contained; never touches
        // the page's Aurora layer).
        let glow = sin(.pi * p) * 0.35
        if glow > 0.01 {
            let g = Path(ellipseIn: CGRect(x: center.x - rMax, y: center.y - rMax, width: rMax * 2, height: rMax * 2))
            ctx.fill(g, with: .radialGradient(
                Gradient(colors: [Theme.coral.opacity(glow), .clear]),
                center: center, startRadius: 0, endRadius: rMax))
        }

        for i in 0..<n {
            let delay = Double(i) / Double(n) * 0.3
            let t = max(0, min((p - delay) / (1 - delay), 1))   // per-dot local progress
            guard t > 0 else { continue }
            let eased = 1 - pow(1 - t, 3)                        // easeOut
            let ang = ga * Double(i)
            let r = rMax * eased
            let x = center.x + CoordMath.cos(ang) * r
            let y = center.y + CoordMath.sin(ang) * r
            let dia = 2 + 4 * t
            let op = sin(.pi * t) * 0.55                         // 0 → .55 → 0
            let color: Color = (milestone && i % 5 == 0) ? Theme.teal : Theme.coral
            // Soft halo, then the dot.
            let halo = dia * 2.4
            ctx.fill(Path(ellipseIn: CGRect(x: x - halo / 2, y: y - halo / 2, width: halo, height: halo)),
                     with: .color(color.opacity(op * 0.25)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - dia / 2, y: y - dia / 2, width: dia, height: dia)),
                     with: .color(color.opacity(op)))
        }
    }
}

/// Tiny trig shim (keeps the Canvas call sites readable).
private enum CoordMath {
    static func cos(_ a: Double) -> CGFloat { CGFloat(Foundation.cos(a)) }
    static func sin(_ a: Double) -> CGFloat { CGFloat(Foundation.sin(a)) }
}
