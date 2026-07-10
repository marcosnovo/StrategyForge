//
//  StrategyDiagramView.swift
//  StrategyForge
//
//  A hand-drawn-style topology diagram for a strategy, rendered natively. The
//  spec is DERIVED from the Strategy, so it stays correct as models and counts
//  are edited. Visual language matches the reference diagrams: a terracotta,
//  dashed "accent" node (the highest-tier model), white nodes for the rest,
//  terracotta delegation arrows, gray dashed return arrows, and curved self-loops.
//

import SwiftUI

// MARK: - Spec

/// One box in the diagram.
private struct DiagramNode: Identifiable {
    let id = UUID()
    var title: String
    var model: String
    var subtitle: String?
    /// Terracotta fill + dashed border (the highlighted / top-tier node).
    var isAccent: Bool
    /// Draw a self-loop with this label (nil = no loop).
    var loopLabel: String?
    /// Left column (orchestrator) vs right column (subagents).
    var isOrchestrator: Bool
    /// Vertical slot index and total, for positioning within the right column.
    var slot: Int
    var slotCount: Int
    /// >1 renders stacked cards + a "×N" badge.
    var stackCount: Int
}

private enum EdgeKind { case delegate, returns }

private struct DiagramEdge {
    var from: UUID
    var to: UUID
    var kind: EdgeKind
    var label: String?
}

private struct DiagramSpec {
    var orchestrator: DiagramNode
    var subagents: [DiagramNode]
    var edges: [DiagramEdge]
    var allNodes: [DiagramNode] { [orchestrator] + subagents }
}

// MARK: - Spec builder

private enum DiagramSpecBuilder {

    /// Model tiers — the accent node is the one running the highest tier.
    private static func tier(_ model: ClaudeModel) -> Int {
        switch model {
        case .opus48, .fable5: return 3
        case .sonnet5: return 2
        case .haiku45: return 1
        }
    }

    private static func titleCase(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Localization key for the verb on the fan-out / delegation arrow, by strategy.
    private static func delegateKey(_ strategy: Strategy) -> String {
        let n = strategy.name.lowercased()
        if n.contains("fan-out") && n.contains("worker") { return "diag.fanout" }
        if n.contains("advisor") { return "diag.toolcall" }
        if n.contains("research") { return "diag.fanout" }
        if n.contains("specialist") { return "diag.route" }
        if n.contains("debate") || n.contains("consensus") { return "diag.ask" }
        return "diag.delegate"
    }

    private static func orchestratorSubtitleKey(_ strategy: Strategy) -> String {
        let n = strategy.name.lowercased()
        if n.contains("advisor") { return "diag.everyturn" }
        if n.contains("specialist") { return "diag.route" }
        if n.contains("debate") || n.contains("consensus") { return "diag.mediate" }
        if n.contains("sparring") { return "diag.mediate" }
        if n.contains("solo") { return "diag.everything" }
        return "diag.plan"
    }

    /// Advisory roles report back (gray dashed return arrow) and get no work loop.
    private static func isAdvisory(_ kind: RoleKind) -> Bool {
        switch kind {
        case .advisor, .reviewer, .researcher: return true
        case .orchestrator, .worker, .planner, .specialist: return false
        }
    }

    private static func returnKey(_ kind: RoleKind, strategy: Strategy) -> String {
        if strategy.name.lowercased().contains("debate") { return "diag.sendArgument" }
        switch kind {
        case .reviewer: return "diag.sendReview"
        case .researcher: return "diag.sendSummary"
        default: return "diag.sendAdvice"
        }
    }

    private static func rightSubtitleKey(_ kind: RoleKind, strategy: Strategy) -> String? {
        if strategy.name.lowercased().contains("debate") { return "diag.argue" }
        switch kind {
        case .advisor: return "diag.ondemand"
        case .reviewer: return "diag.aftercoding"
        case .researcher: return "diag.explore"
        default: return nil
        }
    }

    static func build(from strategy: Strategy, t: (String) -> String) -> DiagramSpec {
        let topTier = strategy.roles.map { tier($0.model) }.max() ?? 3

        // Orchestrator (or the single solo agent).
        let orchRole = strategy.orchestrator
        let orchestrator = DiagramNode(
            title: titleCase(orchRole?.name ?? "orchestrator"),
            model: orchRole?.modelDisplayName ?? "—",
            subtitle: t(orchestratorSubtitleKey(strategy)),
            isAccent: tier(orchRole?.model ?? .fable5) >= topTier,
            loopLabel: nil,
            isOrchestrator: true,
            slot: 0, slotCount: 1, stackCount: 1
        )

        // Expand subagent roles into drawn boxes; collapse if it would get crowded.
        let roles = strategy.subagentRoles
        let maxIndividual = 5
        var expanded = roles.reduce(0) { $0 + (min($1.count, maxIndividual + 1) <= maxIndividual ? $1.count : 1) }
        let collapse = expanded > 7 || roles.contains { $0.count > maxIndividual }
        _ = expanded

        var boxes: [(role: AgentRole, title: String, stack: Int)] = []
        for role in roles {
            let base = titleCase(role.name)
            if collapse || role.count > maxIndividual {
                boxes.append((role, base, role.count))
            } else if role.count == 1 {
                boxes.append((role, base, 1))
            } else {
                for i in 1...role.count { boxes.append((role, "\(base) \(i)", 1)) }
            }
        }

        let count = boxes.count
        let midIndex = count / 2
        var subagents: [DiagramNode] = []
        var edges: [DiagramEdge] = []

        for (i, box) in boxes.enumerated() {
            let advisory = isAdvisory(box.role.role)
            let subKey = rightSubtitleKey(box.role.role, strategy: strategy)
            let subtitle: String? = subKey == nil ? nil : t(subKey!)
            let node = DiagramNode(
                title: box.title,
                model: box.role.modelDisplayName,
                subtitle: subtitle,
                isAccent: tier(box.role.model) >= topTier,
                loopLabel: nil,   // no self-loops — the round-trip tells the story
                isOrchestrator: false,
                slot: i, slotCount: count, stackCount: box.stack
            )
            subagents.append(node)

            // Every delegation is a round-trip: the orchestrator invokes the
            // subagent (delegate) and the subagent reports its result back. This
            // is the faithful single-level model — no subagent talks to another.
            edges.append(DiagramEdge(
                from: orchestrator.id, to: node.id, kind: .delegate,
                label: i == midIndex ? t(delegateKey(strategy)) : nil
            ))
            let retLabel = advisory ? t(returnKey(box.role.role, strategy: strategy)) : t("diag.reports")
            edges.append(DiagramEdge(
                from: node.id, to: orchestrator.id, kind: .returns,
                label: i == midIndex ? retLabel : nil
            ))
        }

        return DiagramSpec(orchestrator: orchestrator, subagents: subagents, edges: edges)
    }
}

// MARK: - Palette

private struct DiagramPalette {
    let canvas: Color
    let surface: Color
    let accent: Color
    let border: Color
    let text: Color
    let secondary: Color
    let returnArrow: Color
    let loop: Color

    /// The diagram uses the shared Voltage tokens (dynamic — they adapt to light
    /// and dark automatically inside Canvas).
    static func make(_ scheme: ColorScheme) -> DiagramPalette {
        DiagramPalette(
            canvas: Theme.insetBg,
            surface: Theme.cardBg,
            accent: Theme.accent,
            border: Theme.hairline,
            text: .primary,
            secondary: .secondary,
            returnArrow: Color.secondary.opacity(0.6),
            loop: Color.secondary.opacity(0.85)
        )
    }
}

// MARK: - View

struct StrategyDiagramView: View {
    let strategy: Strategy
    /// When live, the node for this agent (nil → the orchestrator) gets a bright
    /// "at work" glow, so the diagram doubles as a live activity visualization.
    var activeAgent: String? = nil
    var isLive: Bool = false
    /// Compact mode for narrow columns (e.g. the activity panel): drops edge
    /// labels, the legend and node subtitles, and tightens spacing so the topology
    /// stays legible at ~300pt instead of overlapping.
    var compact: Bool = false
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = DiagramPalette.make(scheme)
        let spec = DiagramSpecBuilder.build(from: strategy, t: { model.t($0) })
        // Which node (if any) is the one currently working.
        let activeID: UUID? = {
            guard isLive else { return nil }
            if let a = activeAgent {
                return spec.subagents.first { Self.titlesMatch($0.title, a) }?.id
            }
            return spec.orchestrator.id
        }()

        // Pure Canvas — no GeometryReader (which destabilizes ScrollView content
        // height) and no positioned subviews. Everything is drawn from `size`.
        // TimelineView drives the "live circuit" animation (flowing signal +
        // breathing root glow).
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat(0.5 + 0.5 * sin(t * 1.7))
            Canvas { ctx, size in
                let frames = layout(spec: spec, in: size)
                ctx.fill(
                    Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14),
                    with: .color(palette.canvas)
                )
                drawBackground(spec: spec, frames: frames, size: size, pulse: pulse, ctx: &ctx, palette: palette)
                drawEdges(spec: spec, frames: frames, time: t, ctx: &ctx, palette: palette)
                drawNodes(spec: spec, frames: frames, pulse: pulse, activeID: activeID, ctx: &ctx, palette: palette)
                if !compact {
                    drawLabels(spec: spec, frames: frames, size: size, ctx: &ctx, palette: palette)
                    drawLegend(spec: spec, size: size, ctx: &ctx, palette: palette)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        // Force a fresh Canvas when the strategy changes so the drawing can never
        // lag behind the picker selection.
        .id(strategy.name)
    }

    // MARK: Layout

    /// Preferred height for a strategy's diagram, so nodes never overlap.
    static func preferredHeight(for strategy: Strategy) -> CGFloat {
        let n = DiagramSpecBuilder.build(from: strategy, t: { $0 }).subagents.count
        return min(max(CGFloat(n) * 66 + 96, 190), 380)
    }

    private func nodeWidth(in size: CGSize) -> CGFloat {
        compact ? min(max(size.width * 0.30, 84), 120)
                : min(max(size.width * 0.22, 104), 180)
    }

    private func layout(spec: DiagramSpec, in size: CGSize) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        let w = nodeWidth(in: size)
        let k = max(spec.subagents.count, 1)

        // Fit node height to the available space so boxes never overlap.
        let topPad: CGFloat = 24
        let availH = size.height - topPad * 2
        let gap: CGFloat = 12
        let fitH = (availH - gap * CGFloat(k - 1)) / CGFloat(k)
        let nodeH = max(min(fitH, 80), 46)

        // Reserve room on the left for the Main loop and on the right for the
        // per-node loops and labels (scaled so the diagram fits narrow widths).
        let reserve: CGFloat = compact ? min(16, size.width * 0.05) : min(48, size.width * 0.11)
        let leftX: CGFloat = reserve
        let rightX = size.width - w - reserve

        // Orchestrator vertically centered; horizontally centered when solo.
        let orchX = spec.subagents.isEmpty ? (size.width - w) / 2 : leftX
        frames[spec.orchestrator.id] = CGRect(
            x: orchX, y: (size.height - nodeH) / 2, width: w, height: nodeH
        )

        // Subagents evenly stacked on the right.
        let slotSpan = availH / CGFloat(k)
        for node in spec.subagents {
            let slotCenter = topPad + (CGFloat(node.slot) + 0.5) * slotSpan
            frames[node.id] = CGRect(
                x: rightX, y: slotCenter - nodeH / 2, width: w, height: nodeH
            )
        }
        return frames
    }

    // MARK: Background (dot grid + powered-root glow)

    private func drawBackground(spec: DiagramSpec, frames: [UUID: CGRect], size: CGSize, pulse: CGFloat, ctx: inout GraphicsContext, palette: DiagramPalette) {
        // Faint engineering dot grid.
        let spacing: CGFloat = 22
        var dots = Path()
        var y = spacing
        while y < size.height {
            var x = spacing
            while x < size.width {
                dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                x += spacing
            }
            y += spacing
        }
        ctx.fill(dots, with: .color(.primary.opacity(0.06)))

        // Radial Voltage glow behind the orchestrator so the topology feels powered.
        if let rect = frames[spec.orchestrator.id] {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = 130
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.10 + 0.10 * pulse), .clear]),
                    center: c, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Legend (teaches the arrow meaning)

    private func drawLegend(spec: DiagramSpec, size: CGSize, ctx: inout GraphicsContext, palette: DiagramPalette) {
        guard !spec.subagents.isEmpty else { return }
        let font = Font.system(size: 10, weight: .medium)
        let y = size.height - 16
        var x: CGFloat = 16

        // delegate swatch
        var l1 = Path(); l1.move(to: CGPoint(x: x, y: y)); l1.addLine(to: CGPoint(x: x + 16, y: y))
        ctx.stroke(l1, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fill(arrowHead(at: CGPoint(x: x + 16, y: y), angle: 0, size: 5), with: .color(palette.accent))
        x += 22
        let d = ctx.resolve(Text(model.t("diag.legend.delegate")).font(font))
        var dShaded = d; dShaded.shading = .color(palette.secondary)
        ctx.draw(dShaded, at: CGPoint(x: x, y: y), anchor: .leading)
        x += d.measure(in: CGSize(width: 200, height: 20)).width + 20

        // report swatch (dashed)
        var l2 = Path(); l2.move(to: CGPoint(x: x, y: y)); l2.addLine(to: CGPoint(x: x + 16, y: y))
        ctx.stroke(l2, with: .color(palette.returnArrow), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3]))
        ctx.fill(arrowHead(at: CGPoint(x: x + 16, y: y), angle: 0, size: 4.5), with: .color(palette.returnArrow))
        x += 22
        let r = ctx.resolve(Text(model.t("diag.legend.report")).font(font))
        var rShaded = r; rShaded.shading = .color(palette.secondary)
        ctx.draw(rShaded, at: CGPoint(x: x, y: y), anchor: .leading)
    }

    // MARK: Edges

    private func drawEdges(spec: DiagramSpec, frames: [UUID: CGRect], time: Double, ctx: inout GraphicsContext, palette: DiagramPalette) {
        // RETURNS first (quiet, underneath): every subagent reports its result back
        // to the orchestrator — a curve bowing into its own lane below the fan.
        for edge in spec.edges where edge.kind == .returns {
            guard let a = frames[edge.from], let b = frames[edge.to] else { continue }
            let start = CGPoint(x: a.minX, y: a.midY + 10)
            let end = CGPoint(x: b.maxX + 8, y: b.midY + 16)
            let control = bowControl(start: start, end: end, bow: 34)
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            ctx.stroke(path, with: .color(palette.returnArrow),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 5]))
            let angle = atan2(end.y - control.y, end.x - control.x)
            ctx.fill(arrowHead(at: end, angle: angle, size: 7), with: .color(palette.returnArrow))
        }

        // DELEGATE (prominent): the orchestrator invokes each subagent. A base wire
        // plus a travelling "signal packet" of light, staggered per edge.
        var index = 0
        for edge in spec.edges where edge.kind == .delegate {
            guard let a = frames[edge.from], let b = frames[edge.to] else { continue }
            let start = CGPoint(x: a.maxX, y: a.midY - 4)
            let end = CGPoint(x: b.minX - 8, y: b.midY - 4)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            ctx.stroke(path, with: .linearGradient(
                Gradient(colors: [palette.accent.opacity(0.7), palette.accent.opacity(0.22)]),
                startPoint: start, endPoint: end),
                style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let angle = atan2(end.y - start.y, end.x - start.x)
            ctx.fill(arrowHead(at: end, angle: angle, size: 9), with: .color(palette.accent))

            // Travelling packet: a bright glowing dot that runs source → target,
            // fading in/out at the ends. Staggered so signals dispatch in sequence.
            let u = ((time * 0.55 + Double(index) * 0.34).truncatingRemainder(dividingBy: 1.0))
            let fade = sin(u * .pi)                // 0 at ends, 1 mid-flight
            if fade > 0.02 {
                let p = CGPoint(x: start.x + (end.x - start.x) * u,
                                y: start.y + (end.y - start.y) * u)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)),
                         with: .color(palette.accent.opacity(0.22 * fade)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(palette.accent.opacity(0.35 + 0.65 * fade)))
            }
            index += 1
        }
    }

    /// Control point for a curve that bows perpendicular to start→end (downward).
    private func bowControl(start: CGPoint, end: CGPoint, bow: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        let len = max(hypot(dx, dy), 1)
        var nx = -dy / len, ny = dx / len
        if ny < 0 { nx = -nx; ny = -ny }   // always bow downward
        return CGPoint(x: mid.x + nx * bow, y: mid.y + ny * bow)
    }

    // MARK: Self-loops

    private func drawLoops(spec: DiagramSpec, frames: [UUID: CGRect], ctx: inout GraphicsContext, palette: DiagramPalette) {
        for node in spec.allNodes {
            // A non-nil loopLabel means "draw a loop" (empty string = loop, no label).
            guard node.loopLabel != nil, let rect = frames[node.id] else { continue }

            var path = Path()
            let head: CGPoint
            let headAngle: CGFloat
            if node.isOrchestrator {
                // Loop on the LEFT side, curving out and down.
                let top = CGPoint(x: rect.minX + 4, y: rect.midY - 4)
                let bottom = CGPoint(x: rect.minX + 4, y: rect.midY + 22)
                path.move(to: top)
                path.addCurve(to: bottom,
                              control1: CGPoint(x: rect.minX - 38, y: rect.midY - 18),
                              control2: CGPoint(x: rect.minX - 38, y: rect.midY + 34))
                head = bottom
                headAngle = .pi / 2.4
            } else {
                // Loop on the RIGHT side.
                let top = CGPoint(x: rect.maxX - 4, y: rect.midY - 4)
                let bottom = CGPoint(x: rect.maxX - 4, y: rect.midY + 20)
                path.move(to: top)
                path.addCurve(to: bottom,
                              control1: CGPoint(x: rect.maxX + 36, y: rect.midY - 16),
                              control2: CGPoint(x: rect.maxX + 36, y: rect.midY + 32))
                head = bottom
                headAngle = .pi - .pi / 2.4
            }
            ctx.stroke(path, with: .color(palette.loop), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ctx.fill(arrowHead(at: head, angle: headAngle, size: 8), with: .color(palette.loop))
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

    // MARK: Nodes (drawn in Canvas)

    private func drawNodes(spec: DiagramSpec, frames: [UUID: CGRect], pulse: CGFloat, activeID: UUID?, ctx: inout GraphicsContext, palette: DiagramPalette) {
        for node in spec.allNodes {
            guard let rect = frames[node.id] else { continue }
            let live = node.id == activeID

            // Stacked cards behind (for collapsed ×N roles).
            if node.stackCount > 1 {
                for i in stride(from: 2, through: 1, by: -1) {
                    let off = CGFloat(6 * i)
                    var faint = ctx
                    faint.opacity = 0.5
                    drawBox(rect.offsetBy(dx: off, dy: off), node: node, pulse: pulse, live: false, ctx: &faint, palette: palette)
                }
            }
            drawBox(rect, node: node, pulse: pulse, live: live, ctx: &ctx, palette: palette)

            // Text — clipped to the node so long names/models never overflow the box.
            var tctx = ctx
            tctx.clip(to: Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 10))
            let cx = rect.midX
            let titleSize: CGFloat = compact ? 11 : 14
            let fitTitle = truncated(node.title, toWidth: rect.width - 8, fontSize: titleSize, weight: 0.60)
            let fitModel = truncated(node.model.uppercased(), toWidth: rect.width - 8, fontSize: compact ? 8.5 : 10, weight: 0.62)
            let title = Text(fitTitle).font(.system(size: titleSize, weight: .semibold))
            let modelT = Text(fitModel).font(.system(size: compact ? 8.5 : 10, weight: .semibold, design: .monospaced))

            if let subtitle = node.subtitle, !compact {
                drawText(&tctx, title, at: CGPoint(x: cx, y: rect.midY - 15), color: palette.text)
                drawText(&tctx, modelT, at: CGPoint(x: cx, y: rect.midY + 1), color: node.isAccent ? palette.accent : palette.secondary)
                drawText(&tctx, Text(truncated(subtitle, toWidth: rect.width - 8, fontSize: 9.5, weight: 0.55)).font(.system(size: 9.5)),
                         at: CGPoint(x: cx, y: rect.midY + 15), color: palette.secondary)
            } else {
                drawText(&tctx, title, at: CGPoint(x: cx, y: rect.midY - 8), color: palette.text)
                drawText(&tctx, modelT, at: CGPoint(x: cx, y: rect.midY + 9), color: node.isAccent ? palette.accent : palette.secondary)
            }

            // ×N badge.
            if node.stackCount > 1 {
                let cap = CGRect(x: rect.maxX - 36, y: rect.maxY - 22, width: 30, height: 16)
                ctx.fill(Path(roundedRect: cap, cornerRadius: 8), with: .color(palette.accent))
                drawText(&ctx, Text("×\(node.stackCount)").font(.system(size: 10, weight: .bold, design: .monospaced)),
                         at: CGPoint(x: cap.midX, y: cap.midY), color: Theme.onAccent)
            }
        }
    }

    /// All node boxes share the surface fill; the accent (top-tier / root) node is
    /// "lit" with a Voltage glow ring instead of a fill, like a powered component.
    private func drawBox(_ rect: CGRect, node: DiagramNode, pulse: CGFloat, live: Bool, ctx: inout GraphicsContext, palette: DiagramPalette) {
        let shape = Path(roundedRect: rect, cornerRadius: 12)
        if live {
            // The agent currently at work: a strong breathing green halo + fill tint,
            // on top of whatever the node normally looks like.
            let green = Theme.success
            let spread = 4.0 + 5.0 * pulse
            let halo = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread), cornerRadius: 12 + spread)
            ctx.fill(shape, with: .color(green.opacity(0.16)))
            ctx.stroke(halo, with: .color(green.opacity(0.28 + 0.30 * pulse)), lineWidth: 6)
            ctx.stroke(shape, with: .color(green), lineWidth: 2)
        } else if node.isAccent {
            ctx.fill(shape, with: .color(palette.surface))
            // Breathing glow ring around the powered node.
            let spread = 2.0 + 3.0 * pulse
            let halo = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread), cornerRadius: 12 + spread)
            ctx.stroke(halo, with: .color(palette.accent.opacity(0.20 + 0.25 * pulse)), lineWidth: 5)
            ctx.stroke(shape, with: .color(palette.accent), lineWidth: 1.6)
        } else {
            ctx.fill(shape, with: .color(palette.surface))
            ctx.stroke(shape, with: .color(palette.border), lineWidth: 1)
        }
    }

    // MARK: Labels (drawn in Canvas)

    private func drawLabels(spec: DiagramSpec, frames: [UUID: CGRect], size: CGSize, ctx: inout GraphicsContext, palette: DiagramPalette) {
        let font = Font.system(size: 11.5, weight: .medium).italic()

        for edge in spec.edges {
            guard let label = edge.label, let a = frames[edge.from], let b = frames[edge.to] else { continue }
            let mid = CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
            let dy: CGFloat = edge.kind == .delegate ? -16 : 16
            let color = edge.kind == .delegate ? palette.accent : palette.secondary
            drawText(&ctx, Text(label).font(font), at: CGPoint(x: mid.x, y: mid.y + dy), color: color)
        }

        // Main loop label — bottom-left, kept inside the canvas.
        if let rect = frames[spec.orchestrator.id], let l = spec.orchestrator.loopLabel, !l.isEmpty {
            drawText(&ctx, Text(l).font(font), at: CGPoint(x: rect.minX, y: min(rect.maxY + 12, size.height - 8)),
                     color: palette.secondary, anchor: .leading)
        }
        // Worker loop label — top-right of the first looped subagent.
        if let first = spec.subagents.first(where: { ($0.loopLabel ?? "").isEmpty == false }),
           let rect = frames[first.id] {
            drawText(&ctx, Text(first.loopLabel ?? "").font(font),
                     at: CGPoint(x: rect.maxX, y: max(rect.minY - 10, 10)),
                     color: palette.secondary, anchor: .trailing)
        }
    }

    /// Loose match between a diagram node title and a streamed agent name (which may
    /// be a subagent_type slug or a free-text description).
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }
        let na = norm(a), nb = norm(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        return na.contains(nb) || nb.contains(na)
    }

    /// Estimate-and-truncate a label so it fits within `width` at `fontSize`.
    private func truncated(_ s: String, toWidth width: CGFloat, fontSize: CGFloat, weight: CGFloat) -> String {
        let charW = max(1, fontSize * weight)
        let maxChars = max(1, Int(width / charW))
        guard s.count > maxChars else { return s }
        return String(s.prefix(max(1, maxChars - 1))) + "…"
    }

    private func drawText(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint, color: Color, anchor: UnitPoint = .center) {
        var resolved = ctx.resolve(text)
        resolved.shading = .color(color)
        ctx.draw(resolved, at: point, anchor: anchor)
    }
}

// MARK: - Thumbnail

/// A compact, static, label-less mini-topology for the strategy picker: hub on the
/// left, subagents stacked on the right, delegation wires between. Derived from the
/// same spec builder as the full diagram, so it stays faithful — just no text,
/// legend, or animation, so it reads cleanly at small sizes.
struct StrategyThumbnail: View {
    let strategy: Strategy
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let spec = DiagramSpecBuilder.build(from: strategy, t: { $0 })
        let palette = DiagramPalette.make(scheme)

        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                     with: .color(palette.canvas))

            // A shrunk version of the full diagram: a hub node on the left, N
            // subagent nodes on the right, delegate arrows out + dashed return
            // arrows back — the same visual language, just tiny and label-less.
            let subs = spec.subagents
            let solo = subs.isEmpty
            let shown = Array(subs.prefix(4))
            let k = max(shown.count, 1)

            let pad: CGFloat = 5
            let nodeW = min(max(size.width * 0.30, 16), 26)
            let nodeH = min(max((size.height - pad * 2) / CGFloat(k) - 4, 7), 14)
            let hubY = size.height / 2
            let hubRect = CGRect(x: solo ? (size.width - nodeW) / 2 : pad,
                                 y: hubY - nodeH / 2, width: nodeW, height: nodeH)
            let rightX = size.width - nodeW - pad
            let span = size.height - pad * 2
            let satRects: [CGRect] = shown.indices.map { i in
                let t = k == 1 ? 0.5 : CGFloat(i) / CGFloat(k - 1)
                return CGRect(x: rightX, y: pad + t * span - nodeH / 2, width: nodeW, height: nodeH)
            }

            func arrowHead(_ tip: CGPoint, _ angle: CGFloat, _ s: CGFloat) -> Path {
                var p = Path(); p.move(to: tip)
                p.addLine(to: CGPoint(x: tip.x + cos(angle + .pi - 0.5) * s, y: tip.y + sin(angle + .pi - 0.5) * s))
                p.addLine(to: CGPoint(x: tip.x + cos(angle + .pi + 0.5) * s, y: tip.y + sin(angle + .pi + 0.5) * s))
                p.closeSubpath(); return p
            }
            for r in satRects {
                // Return (dashed, quiet) slightly below.
                let rs = CGPoint(x: r.minX, y: r.midY + 2), re = CGPoint(x: hubRect.maxX, y: hubRect.midY + 2)
                var back = Path(); back.move(to: rs); back.addLine(to: re)
                ctx.stroke(back, with: .color(palette.returnArrow),
                           style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                // Delegate (solid accent) with arrowhead into the subagent.
                let ds = CGPoint(x: hubRect.maxX, y: hubRect.midY - 1), de = CGPoint(x: r.minX, y: r.midY - 1)
                var wire = Path(); wire.move(to: ds); wire.addLine(to: de)
                ctx.stroke(wire, with: .color(palette.accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                let ang = atan2(de.y - ds.y, de.x - ds.x)
                ctx.fill(arrowHead(de, ang, 3.2), with: .color(palette.accent.opacity(0.8)))
            }

            func box(_ rect: CGRect, accent: Bool) {
                let shape = Path(roundedRect: rect, cornerRadius: 3)
                ctx.fill(shape, with: .color(accent ? palette.accent.opacity(0.20) : palette.surface))
                ctx.stroke(shape, with: .color(accent ? palette.accent : palette.border), lineWidth: accent ? 1.2 : 0.8)
            }
            for (r, node) in zip(satRects, shown) { box(r, accent: node.isAccent) }
            box(hubRect, accent: true)   // orchestrator always highlighted
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Preview

private struct DiagramPreviewCard: View {
    let strategy: Strategy
    var language: AppLanguage = .system

    private var model: AppModel {
        let m = AppModel()
        m.settings.language = language
        return m
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(strategy.name).font(.headline)
            StrategyDiagramView(strategy: strategy)
                .frame(height: StrategyDiagramView.preferredHeight(for: strategy))
        }
        .padding()
        .frame(width: 680)
        .environment(model)
    }
}

#Preview("Fan-out") { DiagramPreviewCard(strategy: StrategyLibrary.orchestratorWorkers()) }
#Preview("Executor + Advisor") { DiagramPreviewCard(strategy: StrategyLibrary.executorAdvisor()) }
#Preview("Planner → Reviewer") { DiagramPreviewCard(strategy: StrategyLibrary.plannerImplementersReviewer()) }
#Preview("Domain Specialists") { DiagramPreviewCard(strategy: StrategyLibrary.domainSpecialists()) }
#Preview("Research Fan-out") { DiagramPreviewCard(strategy: StrategyLibrary.researchFanout()) }
#Preview("Debate / Consensus") { DiagramPreviewCard(strategy: StrategyLibrary.debateConsensus()) }
#Preview("Solo") { DiagramPreviewCard(strategy: StrategyLibrary.solo()) }
#Preview("Debate (ES)") { DiagramPreviewCard(strategy: StrategyLibrary.debateConsensus(), language: .es) }
