//
//  WorkingLogo.swift
//  StrategyForge
//
//  An animated version of the app's hub-and-spoke mark: signal packets travel from
//  the orchestrator hub out along the spokes while the hub breathes. Used as the
//  "working" indicator while Claude is responding.
//

import SwiftUI

struct WorkingLogo: View {
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = min(sz.width, sz.height) / 2 - 2
                let hubR = r * 0.36
                let dot = max(r * 0.16, 1.6)
                let sats = [90.0, 210.0, 330.0].map { deg -> CGPoint in
                    let a = deg * .pi / 180
                    return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                }

                for p in sats {
                    var spoke = Path(); spoke.move(to: c); spoke.addLine(to: p)
                    ctx.stroke(spoke, with: .color(Theme.accent.opacity(0.30)), lineWidth: 1)
                }
                // Travelling signal packets, staggered per spoke.
                for (i, p) in sats.enumerated() {
                    let u = (t * 0.9 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                    let pt = CGPoint(x: c.x + (p.x - c.x) * u, y: c.y + (p.y - c.y) * u)
                    let fade = sin(u * .pi)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - dot, y: pt.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(Theme.accent.opacity(0.35 + 0.65 * fade)))
                }
                for p in sats {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(Theme.accent.opacity(0.55)))
                }
                // Breathing hub.
                let pulse = 0.6 + 0.4 * sin(t * 3)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - hubR - 2, y: c.y - hubR - 2, width: (hubR + 2) * 2, height: (hubR + 2) * 2)),
                         with: .color(Theme.accent.opacity(0.18 * pulse)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2)),
                         with: .color(Theme.accent))
            }
        }
        .frame(width: size, height: size)
    }
}
