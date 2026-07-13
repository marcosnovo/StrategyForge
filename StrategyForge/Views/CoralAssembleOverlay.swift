//
//  CoralBloomOverlay.swift
//  StrategyForge
//
//  "Coral Assemble" — the signature turn-completion moment. The app's own coral
//  glyph is the hero: the four worker TIPS ignite, a bright highlight flows DOWN
//  the branches into the root (the workers reporting back to the orchestrator), the
//  root gives one confident settle-pulse ("the team has it"), then the mark
//  dissolves. It tells the orchestration story in one read — no particles, no
//  confetti, no shader. Reuses the exact CoralMark geometry + Path trim; honors
//  Reduce Motion; never blocks input; self-terminating.
//

import SwiftUI

struct CoralAssembleOverlay: View {
    /// Bump to fire the gesture (parent increments on turn completion).
    var token: Int
    /// A milestone turn — the four arms carry a teal leading edge (agents → delivery).
    var milestone: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let duration: Double = 1.6
    @State private var startDate: Date?
    @State private var active = false
    @State private var staticOpacity: Double = 0

    // The shipping CoralMark geometry (0…100 canvas), inlined because Theme's copy is
    // private. Order matters: branch 0 is the trunk (root→fork); 1/4 are the mains;
    // 2/3/5/6 are the four outer tips.
    private static let branches: [[CGFloat]] = [
        [50,84, 50,70, 50,60],   // 0 trunk
        [50,60, 40,52, 29,40],   // 1 left main
        [29,40, 24,31, 21,24],   // 2 left-outer tip
        [29,40, 34,31, 39,25],   // 3 left-inner tip
        [50,60, 60,52, 71,40],   // 4 right main
        [71,40, 76,31, 79,24],   // 5 right-outer tip
        [71,40, 66,31, 61,25],   // 6 right-inner tip
    ]
    private static let root: [CGFloat] = [50, 84, 7.6]
    private static let tips: [[CGFloat]] = [[21,24,5.6],[39,25,5.6],[61,25,5.6],[79,24,5.6]]
    /// Which branches are outer "arms" (light first) vs mains vs the trunk (light last).
    private static let tipBranches: Set<Int> = [2,3,5,6]
    private static let mainBranches: Set<Int> = [1,4]

    var body: some View {
        Group {
            if reduceMotion {
                // Static "assembled team": the full mark holds, then fades.
                Canvas { ctx, size in drawStatic(&ctx, size) }
                    .opacity(staticOpacity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
                    Canvas { ctx, size in draw(&ctx, size, now: tl.date) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: token) {
            guard token > 0 else { return }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { staticOpacity = 1 }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.4)) { staticOpacity = 0 }
                return
            }
            startDate = Date(); active = true
            try? await Task.sleep(for: .seconds(duration + 0.1))
            active = false; startDate = nil
        }
    }

    // MARK: - Layout

    /// Centre a ~150pt mark and map the 0…100 glyph space into it.
    private func layout(_ size: CGSize) -> (origin: CGPoint, scale: CGFloat) {
        let s = min(size.width, size.height) * 0.42
        let mark = min(max(s, 110), 170)
        return (CGPoint(x: size.width / 2 - mark / 2, y: size.height / 2 - mark / 2), mark)
    }
    private func pt(_ x: CGFloat, _ y: CGFloat, _ o: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: o.x + x / 100 * s, y: o.y + y / 100 * s)
    }
    private func branchPath(_ b: [CGFloat], _ o: CGPoint, _ s: CGFloat) -> Path {
        var p = Path(); p.move(to: pt(b[0], b[1], o, s)); p.addQuadCurve(to: pt(b[4], b[5], o, s), control: pt(b[2], b[3], o, s)); return p
    }
    private func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2*t*t : 1 - pow(-2*t + 2, 2) / 2 }

    // MARK: - Animated draw

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, now: Date) {
        guard let start = startDate else { return }
        let e = now.timeIntervalSince(start)
        guard e >= 0, e <= duration else { return }
        let (o, s) = layout(size)
        let lw = s * 0.062
        // Global fade over the final 0.3s.
        let alpha = e < 1.3 ? 1.0 : max(0, 1 - (e - 1.3) / 0.3)

        // 1) Ghost mark — the resting "team", always present but dim.
        for b in Self.branches {
            ctx.stroke(branchPath(b, o, s), with: .color(Theme.coral.opacity(0.10 * alpha)),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }

        // 2) CONVERGE — bright highlight fills each branch from tip → root, tiered so
        // the arms lead and the trunk lights last (four arms merging into one stem).
        for (i, b) in Self.branches.enumerated() {
            let delay = Self.tipBranches.contains(i) ? 0.0 : (Self.mainBranches.contains(i) ? 0.08 : 0.16)
            let bStart = 0.25 + delay, bDur = 0.55
            let local = max(0, min((e - bStart) / bDur, 1))
            guard local > 0 else { continue }
            let prog = easeInOut(local)
            // Trim from the END (paths go root→tip) so the lit portion grows from the
            // tip inward to the root.
            let lit = branchPath(b, o, s).trimmedPath(from: 1 - prog, to: 1)
            let teal = milestone && Self.tipBranches.contains(i) && local < 0.5
            ctx.stroke(lit, with: .color((teal ? Theme.teal : Theme.coral).opacity(alpha)),
                       style: StrokeStyle(lineWidth: lw * 1.25, lineCap: .round, lineJoin: .round))
        }

        // 3) Tip nodes IGNITE (0–0.25s, staggered) then stay lit.
        for (i, n) in Self.tips.enumerated() {
            let t = max(0, min((e - Double(i) * 0.02) / 0.25, 1))
            guard t > 0 else { continue }
            let r = n[2] / 100 * s * (1 + 0.35 * t)
            let op = (0.1 + 0.9 * t) * alpha
            let c = milestone ? Theme.teal : Theme.coral
            fillDot(&ctx, pt(n[0], n[1], o, s), r, c.opacity(op))
        }

        // 4) LAND — the moment the trunk light reaches the root (~0.96s): one settle
        // pulse (damped sine, not a bounce) + a coral glow bloom behind the root.
        let landAt = 0.96
        let rootPt = pt(Self.root[0], Self.root[1], o, s)
        let baseR = Self.root[2] / 100 * s
        var pulse = 1.0, glow = 0.0
        if e >= landAt {
            let tau = e - landAt
            pulse = 1 + 0.5 * sin(2 * .pi * 1.3 * tau) * exp(-6 * tau)
            pulse = max(1, pulse)
            glow = max(0, 0.45 * exp(-4 * tau))
        }
        if glow > 0.01 {
            let gr = baseR * 3.2
            ctx.fill(Path(ellipseIn: CGRect(x: rootPt.x - gr, y: rootPt.y - gr, width: gr*2, height: gr*2)),
                     with: .radialGradient(Gradient(colors: [Theme.coral.opacity(glow * alpha), .clear]),
                                           center: rootPt, startRadius: 0, endRadius: gr))
        }
        let rootOp = (e >= 0.6 ? 1.0 : 0.1 + 0.9 * (e / 0.6)) * alpha
        fillDot(&ctx, rootPt, baseR * pulse, Theme.coral.opacity(rootOp))
    }

    /// Reduce-Motion: the full assembled mark at rest (no motion).
    private func drawStatic(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let (o, s) = layout(size)
        let lw = s * 0.062
        for b in Self.branches {
            ctx.stroke(branchPath(b, o, s), with: .color(Theme.coral),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        fillDot(&ctx, pt(Self.root[0], Self.root[1], o, s), Self.root[2] / 100 * s, Theme.coral)
        for n in Self.tips { fillDot(&ctx, pt(n[0], n[1], o, s), n[2] / 100 * s, milestone ? Theme.teal : Theme.coral) }
    }

    private func fillDot(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }
}

// MARK: - Labs preview

/// LABS-ONLY: replay Coral Assemble on demand. Mounted in ParticleLabView.
struct CoralAssembleLabSection: View {
    @State private var token = 0
    @State private var milestone = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coral Assemble — turn-completion signature").font(.sfDisplay)
                Text("The coral mark tells the story: the four worker tips ignite, light flows down the branches into the root (workers → orchestrator), the root settle-pulses, then it dissolves. Milestone (every 25th turn) adds a teal leading edge. ~1.6s. Tap to replay.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.l) { stage(dark: false); stage(dark: true) }
            HStack(spacing: Space.s) {
                Button("Play") { milestone = false; token += 1 }.buttonStyle(.moon)
                Button("Play milestone") { milestone = true; token += 1 }.buttonStyle(.bordered)
            }
        }
    }

    private func stage(dark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner)
                .fill(dark ? Color(red: 0.078, green: 0.102, blue: 0.118) : Theme.appBg)   // reef-ink / paper
            CoralAssembleOverlay(token: token, milestone: milestone)
        }
        .frame(width: 260, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
