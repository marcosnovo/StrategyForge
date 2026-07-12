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
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
        // Fresh Canvas when the kind changes so the drawing never lags the picker.
        .id(plan.kind)
    }

    /// One frame of the cycle. Pure drawing from `size`; no GeometryReader.
    private func frame(labels: [String], time: Double, pulse: CGFloat) -> some View {
        Canvas { ctx, size in
            let n = max(labels.count, 1)
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14),
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

/// A left-to-right flow of a loop kind's stages — reads as a *process*, which
/// explains a loop far better than a ring: a tinted TRIGGER pill on the left,
/// neutral work stages, a green EXIT pill, and a dashed "repeat" arc curving back
/// underneath. Static and on-brand (coral wires, Coral tokens); used in the editor
/// to make each loop type self-explanatory.
struct LoopKindFlowDiagram: View {
    let kind: LoopKind
    @Environment(AppModel.self) private var model

    /// Stage labels in flow order (same source as the ring diagram).
    private var stageKeys: [String] {
        switch kind {
        case .turnBased: return ["loop.stage.prompt", "loop.stage.work", "loop.stage.check", "loop.stage.reply"]
        case .goalBased: return ["loop.stage.goal", "loop.stage.try", "loop.stage.judge", "loop.stage.done"]
        case .timeBased: return ["loop.stage.interval", "loop.stage.check", "loop.stage.react", "loop.stage.wait"]
        case .proactive: return ["loop.stage.event", "loop.stage.route", "loop.stage.work", "loop.stage.review"]
        }
    }

    var body: some View {
        let labels = stageKeys.map { model.t($0) }
        let repeatLabel = model.t("loop.flow.repeat")
        Canvas { ctx, size in
            let n = max(labels.count, 1)
            let font = Font.system(size: 11, weight: .semibold, design: .monospaced)
            let resolved = labels.map { ctx.resolve(Text($0).font(font)) }
            let sizes = resolved.map { $0.measure(in: CGSize(width: 220, height: 40)) }
            let pillW = sizes.map { $0.width + 22 }
            let pillH: CGFloat = 30
            let gap: CGFloat = 24
            let totalW = pillW.reduce(0, +) + gap * CGFloat(n - 1)

            // Row sits a little above centre so the repeat arc has room below.
            let y = size.height / 2 - 14
            var x = max((size.width - totalW) / 2, 8)
            var rects: [CGRect] = []
            for i in 0..<n {
                let rect = CGRect(x: x, y: y - pillH / 2, width: pillW[i], height: pillH)
                rects.append(rect)
                x += pillW[i] + gap
            }

            // Straight coral arrows between consecutive stages.
            for i in 0..<(n - 1) {
                let a = CGPoint(x: rects[i].maxX + 3, y: y)
                let b = CGPoint(x: rects[i + 1].minX - 7, y: y)
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(Theme.accent.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ctx.fill(head(at: b, angle: 0, size: 6), with: .color(Theme.accent))
            }

            // Dashed "repeat" arc curving back from the last stage to the trigger.
            if n >= 2 {
                let start = CGPoint(x: rects[n - 1].midX, y: rects[n - 1].maxY)
                let end = CGPoint(x: rects[0].midX, y: rects[0].maxY)
                let dip = min(rects[0].maxY + 36, size.height - 14)
                var arc = Path()
                arc.move(to: start)
                arc.addCurve(to: end,
                             control1: CGPoint(x: start.x, y: dip),
                             control2: CGPoint(x: end.x, y: dip))
                ctx.stroke(arc, with: .color(Theme.accent.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                ctx.fill(head(at: CGPoint(x: end.x, y: end.y + 1), angle: -.pi / 2, size: 6),
                         with: .color(Theme.accent.opacity(0.7)))
                let lbl = ctx.resolve(Text("↺ \(repeatLabel)")
                    .font(.system(size: 9.5, weight: .semibold)))
                var shaded = lbl; shaded.shading = .color(Theme.accent.opacity(0.8))
                ctx.draw(shaded, at: CGPoint(x: (start.x + end.x) / 2, y: dip - 3), anchor: .center)
            }

            // Pills: first = trigger (accent), last = exit (green), middle neutral.
            for (i, r) in resolved.enumerated() {
                let rect = rects[i]
                let isTrigger = i == 0
                let isExit = i == n - 1
                let tint = isExit ? Theme.success : Theme.accent
                let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
                ctx.fill(shape, with: .color(isTrigger ? Theme.accentSoft
                                             : (isExit ? Theme.success.opacity(0.12) : Theme.cardBg)))
                ctx.stroke(shape, with: .color(isTrigger || isExit ? tint : Theme.hairline),
                           lineWidth: isTrigger || isExit ? 1.5 : 1)
                var shaded = r
                shaded.shading = .color(isExit ? Theme.success : Color.primary)
                ctx.draw(shaded, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline, lineWidth: 1))
        .id(kind)
        .accessibilityLabel(labels.joined(separator: " → "))
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
            LoopKindFlowDiagram(kind: k).frame(height: 140)
        }
    }
    .padding()
    .frame(width: 480)
    .environment(AppModel())
}
