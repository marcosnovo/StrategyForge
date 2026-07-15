//
//  LoopDiagramView.swift
//  StrategyForge
//
//  A simple circular cycle diagram for a loop: the kind's 4 stages laid out on
//  a circle with coral arrows clockwise between them; the exit stage is tinted
//  green. Matches StrategyDiagramView's visual language (insetBg canvas, coral
//  wires, breathing halo on the live node) but stays deliberately small.
//

import SwiftUI

struct LoopDiagramView: View {
    let plan: LoopPlan
    var isLive: Bool = false
    /// Highlight this stage with a breathing halo while the loop runs.
    var activeStageIndex: Int? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Localization keys for the kind's stages, in clockwise order.
    private var stageKeys: [String] {
        switch plan.kind {
        case .turnBased: return ["loop.stage.prompt", "loop.stage.work", "loop.stage.check", "loop.stage.reply"]
        case .goalBased: return ["loop.stage.goal", "loop.stage.try", "loop.stage.judge", "loop.stage.done"]
        case .timeBased: return ["loop.stage.interval", "loop.stage.check", "loop.stage.react", "loop.stage.wait"]
        case .proactive: return ["loop.stage.event", "loop.stage.route", "loop.stage.work", "loop.stage.review"]
        }
    }

    var body: some View {
        // Canvas text needs resolved strings — compute them before drawing.
        let labels = stageKeys.map { model.t($0) }
        // A single animated dot travels the circle only when live; otherwise one
        // static Canvas (and always static under Reduce Motion).
        let animate = isLive && !reduceMotion
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    frame(labels: labels, time: t, pulse: CGFloat(0.5 + 0.5 * sin(t * 1.7)))
                }
            } else {
                frame(labels: labels, time: 0, pulse: 0.6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        // Fresh Canvas when the kind changes so the drawing never lags the picker.
        .id(plan.kind)
    }

    /// One frame of the cycle. Pure drawing from `size`; no GeometryReader.
    private func frame(labels: [String], time: Double, pulse: CGFloat) -> some View {
        Canvas { ctx, size in
            let n = max(labels.count, 1)
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Theme.innerCorner),
                     with: .color(Theme.insetBg))

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(min(size.width, size.height) / 2 - 26, 24)
            func point(_ angle: Double) -> CGPoint {
                CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                        y: center.y + CGFloat(sin(angle)) * radius)
            }
            // Stage centers, starting at 12 o'clock and going clockwise (screen
            // coordinates have y down, so increasing angle IS clockwise).
            let angles = (0..<n).map { -Double.pi / 2 + Double($0) * 2 * .pi / Double(n) }

            // The kind's icon at the hub, quiet, so an empty middle still reads.
            let icon = ctx.resolve(Image(systemName: plan.kind.icon))
            var dimmed = ctx
            dimmed.opacity = 0.35
            dimmed.draw(icon, at: center)

            // Arrows: clockwise arcs between consecutive stages, leaving a gap
            // around each node so the wire never runs under the pill.
            let gap = 0.55
            for i in 0..<n {
                let a0 = angles[i] + gap
                var a1 = angles[(i + 1) % n] - gap
                if a1 <= a0 { a1 += 2 * .pi }
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.accent.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
                // Arrowhead along the direction of travel at the arc's end.
                ctx.fill(arrowHead(at: point(a1), angle: CGFloat(a1) + .pi / 2, size: 7),
                         with: .color(Theme.accent))
            }

            // A single coral signal dot traveling the circle while live.
            if time != 0 {
                let u = (time * 0.22).truncatingRemainder(dividingBy: 1.0)
                let p = point(-Double.pi / 2 + u * 2 * .pi)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)),
                         with: .color(Theme.accent.opacity(0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(Theme.accent))
            }

            // Stage pills. The last stage is the exit ("Reply"/"Done"/"Wait"/
            // "Review") and gets the success tint.
            for (i, label) in labels.enumerated() {
                let p = point(angles[i])
                let isExit = i == n - 1
                let tint = isExit ? Theme.success : Theme.accent
                let resolved = ctx.resolve(
                    Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)))
                let tSize = resolved.measure(in: CGSize(width: 160, height: 30))
                let rect = CGRect(x: p.x - (tSize.width + 20) / 2,
                                  y: p.y - (tSize.height + 10) / 2,
                                  width: tSize.width + 20, height: tSize.height + 10)
                let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)

                // Breathing halo for the stage currently at work (same live-halo
                // technique as StrategyDiagramView.drawBox).
                if i == activeStageIndex {
                    let spread = 3.0 + 4.0 * pulse
                    let halo = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread),
                                    cornerRadius: rect.height / 2 + spread)
                    ctx.stroke(halo, with: .color(tint.opacity(0.25 + 0.30 * pulse)), lineWidth: 5)
                }
                ctx.fill(shape, with: .color(Theme.cardBg))
                ctx.stroke(shape, with: .color(i == activeStageIndex ? tint : tint.opacity(isExit ? 0.9 : 0.55)),
                           lineWidth: i == activeStageIndex ? 2 : 1.2)

                var shaded = resolved
                shaded.shading = .color(isExit ? Theme.success : Color.primary)
                ctx.draw(shaded, at: p, anchor: .center)
            }
        }
    }

    private func arrowHead(at tip: CGPoint, angle: CGFloat, size: CGFloat) -> Path {
        let a1 = angle + .pi - 0.4
        let a2 = angle + .pi + 0.4
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x + cos(a1) * size, y: tip.y + sin(a1) * size))
        p.addLine(to: CGPoint(x: tip.x + cos(a2) * size, y: tip.y + sin(a2) * size))
        p.closeSubpath()
        return p
    }
}

// MARK: - Horizontal flow (explainer)

/// Explains a loop kind with a flow diagram whose *topology is distinct per type*,
/// so its mechanism is unmistakable: turn-based has a human Y/N branch, goal-based a
/// verifier Pass/Fail gate, time-based a timer cycle, proactive an event fan-in →
/// router → parallel workers. Static, on-brand (coral trigger, green exit, hairline
/// structure, dashed loop-backs). Used in the editor's cycle card.
struct LoopKindFlowDiagram: View {
    let kind: LoopKind
    /// Real plan values, so the timer arc / brake can show honest numbers.
    var maxTurns: Int = 20
    var intervalMinutes: Int = 30
    @Environment(AppModel.self) private var model

    private var accessibilitySuffix: String {
        switch kind {
        case .turnBased: return ", human decides each round"
        case .goalBased: return ", verifier gates the exit"
        case .timeBased: return ", fires on a timer"
        case .proactive: return ", event-driven and parallel"
        }
    }

    var body: some View {
        Canvas { ctx, size in
            switch kind {
            case .turnBased: drawTurnBased(&ctx, size)
            case .goalBased: drawGoalBased(&ctx, size)
            case .timeBased: drawTimeBased(&ctx, size)
            case .proactive: drawProactive(&ctx, size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .id(kind)
        .accessibilityLabel(model.t(kind.blurbKey) + accessibilitySuffix)
    }

    // MARK: Topologies

    /// Prompt → Work → Check → ◇(you) : "stop" → Reply, dashed "next round" back.
    private func drawTurnBased(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let W = size.width, H = size.height
        let row = H * 0.56
        let prompt = pillRect(&ctx, CGPoint(x: W * 0.11, y: row), model.t("loop.stage.prompt"))
        let work   = pillRect(&ctx, CGPoint(x: W * 0.31, y: row), model.t("loop.stage.work"))
        let check  = pillRect(&ctx, CGPoint(x: W * 0.50, y: row), model.t("loop.stage.check"))
        let dc = CGPoint(x: W * 0.68, y: row); let half: CGFloat = 15
        let reply  = pillRect(&ctx, CGPoint(x: W * 0.88, y: row), model.t("loop.stage.reply"))

        arrow(&ctx, from: CGPoint(x: prompt.maxX + 3, y: row), to: CGPoint(x: work.minX - 7, y: row))
        arrow(&ctx, from: CGPoint(x: work.maxX + 3, y: row), to: CGPoint(x: check.minX - 7, y: row))
        arrow(&ctx, from: CGPoint(x: check.maxX + 3, y: row), to: CGPoint(x: dc.x - half - 5, y: row))
        arrow(&ctx, from: CGPoint(x: dc.x + half + 2, y: row), to: CGPoint(x: reply.minX - 7, y: row))
        branchLabel(&ctx, model.t("loop.flow.stop"), at: CGPoint(x: (dc.x + half + reply.minX) / 2, y: row - 10))
        // "next round" arcs over the top back to Prompt.
        loopBack(&ctx, from: CGPoint(x: dc.x, y: dc.y - half),
                 to: CGPoint(x: prompt.midX, y: prompt.minY - 2),
                 dip: H * 0.14, endAngle: .pi / 2)
        branchLabel(&ctx, model.t("loop.flow.nextRound"),
                    at: CGPoint(x: (dc.x + prompt.midX) / 2, y: H * 0.13), color: Theme.accent.opacity(0.8))

        fillPill(&ctx, prompt, model.t("loop.stage.prompt"), .trigger)
        fillPill(&ctx, work, model.t("loop.stage.work"), .work)
        fillPill(&ctx, check, model.t("loop.stage.check"), .work)
        drawDiamond(&ctx, center: dc, half: half, glyph: "person.fill")
        fillPill(&ctx, reply, model.t("loop.stage.reply"), .exit)
    }

    /// Goal → Try → ◇(verifier) : "Pass" → Done, dashed "Fail" back to Try.
    private func drawGoalBased(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let W = size.width, H = size.height
        let row = H * 0.52
        let goal = pillRect(&ctx, CGPoint(x: W * 0.12, y: row), model.t("loop.stage.goal"))
        let tryR = pillRect(&ctx, CGPoint(x: W * 0.36, y: row), model.t("loop.stage.try"))
        let dc = CGPoint(x: W * 0.58, y: row); let half: CGFloat = 16
        let done = pillRect(&ctx, CGPoint(x: W * 0.84, y: row), model.t("loop.stage.done"))

        arrow(&ctx, from: CGPoint(x: goal.maxX + 3, y: row), to: CGPoint(x: tryR.minX - 7, y: row))
        arrow(&ctx, from: CGPoint(x: tryR.maxX + 3, y: row), to: CGPoint(x: dc.x - half - 5, y: row))
        arrow(&ctx, from: CGPoint(x: dc.x + half + 2, y: row), to: CGPoint(x: done.minX - 7, y: row))
        branchLabel(&ctx, model.t("loop.flow.pass"), at: CGPoint(x: (dc.x + half + done.minX) / 2, y: row - 10), color: Theme.success)
        // "Fail" arcs under, back to Try (retry the attempt, not the goal).
        loopBack(&ctx, from: CGPoint(x: dc.x, y: dc.y + half),
                 to: CGPoint(x: tryR.midX, y: tryR.maxY + 2),
                 dip: H * 0.88, endAngle: -.pi / 2)
        branchLabel(&ctx, model.t("loop.flow.fail"),
                    at: CGPoint(x: (dc.x + tryR.midX) / 2, y: H * 0.9), color: Theme.warning)

        fillPill(&ctx, goal, model.t("loop.stage.goal"), .trigger)
        fillPill(&ctx, tryR, model.t("loop.stage.try"), .work)
        drawDiamond(&ctx, center: dc, half: half, glyph: "checkmark.seal.fill")
        fillPill(&ctx, done, model.t("loop.stage.done"), .exit)
    }

    /// ⏱ (clock trigger) → Check → React → Wait, dashed "every N min" arc back.
    private func drawTimeBased(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let W = size.width, H = size.height
        let row = H * 0.50
        let clock = CGPoint(x: W * 0.12, y: row); let r: CGFloat = 18
        let check = pillRect(&ctx, CGPoint(x: W * 0.38, y: row), model.t("loop.stage.check"))
        let react = pillRect(&ctx, CGPoint(x: W * 0.58, y: row), model.t("loop.stage.react"))
        let wait  = pillRect(&ctx, CGPoint(x: W * 0.78, y: row), model.t("loop.stage.wait"))

        arrow(&ctx, from: CGPoint(x: clock.x + r + 3, y: row), to: CGPoint(x: check.minX - 7, y: row))
        arrow(&ctx, from: CGPoint(x: check.maxX + 3, y: row), to: CGPoint(x: react.minX - 7, y: row))
        arrow(&ctx, from: CGPoint(x: react.maxX + 3, y: row), to: CGPoint(x: wait.minX - 7, y: row))
        loopBack(&ctx, from: CGPoint(x: wait.midX, y: wait.maxY + 2),
                 to: CGPoint(x: clock.x, y: clock.y + r + 2),
                 dip: H * 0.9, endAngle: -.pi / 2)
        branchLabel(&ctx, model.t("loop.flow.everyMin", intervalMinutes),
                    at: CGPoint(x: (wait.midX + clock.x) / 2, y: H * 0.92), color: Theme.accent.opacity(0.8))

        circleNode(&ctx, center: clock, radius: r, glyph: "clock.fill", role: .trigger)
        fillPill(&ctx, check, model.t("loop.stage.check"), .work)
        fillPill(&ctx, react, model.t("loop.stage.react"), .work)
        fillPill(&ctx, wait, model.t("loop.stage.wait"), .work)
    }

    /// Several events fan into a Router diamond, which fans out to parallel workers,
    /// which converge into Review; a dashed arc shows it keeps watching.
    private func drawProactive(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let W = size.width, H = size.height
        let er: CGFloat = 11
        let events: [(CGPoint, String)] = [
            (CGPoint(x: W * 0.10, y: H * 0.24), "bolt.fill"),
            (CGPoint(x: W * 0.10, y: H * 0.50), "arrow.down.doc.fill"),
            (CGPoint(x: W * 0.10, y: H * 0.76), "exclamationmark.triangle.fill"),
        ]
        let dc = CGPoint(x: W * 0.40, y: H * 0.50); let half: CGFloat = 19
        let w1 = pillRect(&ctx, CGPoint(x: W * 0.68, y: H * 0.30), model.t("loop.stage.work"))
        let w2 = pillRect(&ctx, CGPoint(x: W * 0.68, y: H * 0.70), model.t("loop.stage.work"))
        let review = pillRect(&ctx, CGPoint(x: W * 0.90, y: H * 0.50), model.t("loop.stage.review"))

        // Fan-in: each event → router.
        for (p, _) in events {
            arrow(&ctx, from: CGPoint(x: p.x + er + 2, y: p.y), to: CGPoint(x: dc.x - half - 4, y: dc.y))
        }
        // Fan-out: router → each worker.
        arrow(&ctx, from: CGPoint(x: dc.x + half + 2, y: dc.y), to: CGPoint(x: w1.minX - 7, y: w1.midY))
        arrow(&ctx, from: CGPoint(x: dc.x + half + 2, y: dc.y), to: CGPoint(x: w2.minX - 7, y: w2.midY))
        // Converge: workers → review.
        arrow(&ctx, from: CGPoint(x: w1.maxX + 3, y: w1.midY), to: CGPoint(x: review.minX - 7, y: review.midY))
        arrow(&ctx, from: CGPoint(x: w2.maxX + 3, y: w2.midY), to: CGPoint(x: review.minX - 7, y: review.midY))
        // Keeps watching: dashed arc from review back to the events column.
        loopBack(&ctx, from: CGPoint(x: review.midX, y: review.maxY + 2),
                 to: CGPoint(x: events[2].0.x, y: events[2].0.y + er + 2),
                 dip: H * 0.96, endAngle: -.pi / 2)

        for (p, glyph) in events { circleNode(&ctx, center: p, radius: er, glyph: glyph, role: .trigger) }
        drawDiamond(&ctx, center: dc, half: half, glyph: "arrow.triangle.branch")
        fillPill(&ctx, w1, model.t("loop.stage.work"), .work)
        fillPill(&ctx, w2, model.t("loop.stage.work"), .work)
        fillPill(&ctx, review, model.t("loop.stage.review"), .exit)
    }

    // MARK: Drawing primitives

    private enum NodeRole { case trigger, work, exit }
    private var pillFont: Font { .system(size: 11, weight: .semibold, design: .monospaced) }

    /// The rect a pill will occupy (measured), so arrows can be routed before the
    /// pill is drawn on top.
    private func pillRect(_ ctx: inout GraphicsContext, _ center: CGPoint, _ text: String) -> CGRect {
        let s = ctx.resolve(Text(text).font(pillFont)).measure(in: CGSize(width: 220, height: 40))
        let w = s.width + 22, h: CGFloat = 30
        return CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
    }

    private func fillPill(_ ctx: inout GraphicsContext, _ rect: CGRect, _ text: String, _ role: NodeRole) {
        let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
        let fill: Color, stroke: Color, lw: CGFloat
        switch role {
        // Trigger = coral (the orchestrator / brand). Work = teal (the reef-water
        // secondary: worker agents). Exit = success green.
        case .trigger: fill = Theme.accentSoft; stroke = Theme.accent; lw = 1.5
        case .work:    fill = Theme.tealSoft; stroke = Theme.tealEdge; lw = 1
        case .exit:    fill = Theme.success.opacity(0.12); stroke = Theme.success; lw = 1.5
        }
        ctx.fill(shape, with: .color(fill))
        ctx.stroke(shape, with: .color(stroke), lineWidth: lw)
        var t = ctx.resolve(Text(text).font(pillFont))
        t.shading = .color(role == .exit ? Theme.success : Color.primary)
        ctx.draw(t, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    private func circleNode(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, glyph: String, role: NodeRole) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let (fill, stroke): (Color, Color)
        switch role {
        case .exit: (fill, stroke) = (Theme.success.opacity(0.12), Theme.success)
        case .work: (fill, stroke) = (Theme.tealSoft, Theme.teal)
        case .trigger: (fill, stroke) = (Theme.accentSoft, Theme.accent)
        }
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.5)
        var g = ctx.resolve(Text(Image(systemName: glyph)).font(.system(size: radius * 0.72)))
        g.shading = .color(stroke)
        ctx.draw(g, at: center)
    }

    private func drawDiamond(_ ctx: inout GraphicsContext, center c: CGPoint, half: CGFloat, glyph: String?) {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - half))
        p.addLine(to: CGPoint(x: c.x + half, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + half))
        p.addLine(to: CGPoint(x: c.x - half, y: c.y))
        p.closeSubpath()
        ctx.fill(p, with: .color(Theme.cardBg))
        ctx.stroke(p, with: .color(Theme.accent), lineWidth: 1.5)
        if let glyph {
            var g = ctx.resolve(Text(Image(systemName: glyph)).font(.system(size: half * 0.7)))
            g.shading = .color(Theme.accent.opacity(0.5))
            ctx.draw(g, at: c)
        }
    }

    private func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                       color: Color = Theme.accent.opacity(0.8)) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(head(at: b, angle: atan2(b.y - a.y, b.x - a.x), size: 6), with: .color(color))
    }

    /// A dashed cubic loop-back with an arrowhead at the end (`endAngle` = travel dir).
    private func loopBack(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                          dip: CGFloat, endAngle: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addCurve(to: b, control1: CGPoint(x: a.x, y: dip), control2: CGPoint(x: b.x, y: dip))
        ctx.stroke(p, with: .color(Theme.accent.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        ctx.fill(head(at: b, angle: endAngle, size: 6), with: .color(Theme.accent.opacity(0.7)))
    }

    private func branchLabel(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint,
                             color: Color = Theme.inkDim) {
        var t = ctx.resolve(Text(text).font(.system(size: 9.5, weight: .semibold)))
        t.shading = .color(color)
        ctx.draw(t, at: p, anchor: .center)
    }

    private func head(at tip: CGPoint, angle: CGFloat, size: CGFloat) -> Path {
        let a1 = angle + .pi - 0.4
        let a2 = angle + .pi + 0.4
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x + cos(a1) * size, y: tip.y + sin(a1) * size))
        p.addLine(to: CGPoint(x: tip.x + cos(a2) * size, y: tip.y + sin(a2) * size))
        p.closeSubpath()
        return p
    }
}

#Preview("Loop flows") {
    VStack(spacing: 16) {
        ForEach(LoopKind.allCases) { k in
            LoopKindFlowDiagram(kind: k, maxTurns: 20, intervalMinutes: 30)
                .frame(height: k == .proactive ? 160 : 140)
        }
    }
    .padding()
    .frame(width: 520)
    .environment(AppModel())
}
