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
    /// The team role this box represents, so a tap can select/edit it.
    var roleID: UUID?
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

    static func build(from strategy: Strategy, compact: Bool = false, t: (String) -> String) -> DiagramSpec {
        let topTier = strategy.roles.map { tier($0.model) }.max() ?? 3

        // Orchestrator (or the single solo agent).
        let orchRole = strategy.orchestrator
        let orchestrator = DiagramNode(
            roleID: orchRole?.id,
            title: titleCase(orchRole?.name ?? "orchestrator"),
            model: orchRole?.modelDisplayName ?? "—",
            subtitle: t(orchestratorSubtitleKey(strategy)),
            isAccent: tier(orchRole?.model ?? .fable5) >= topTier,
            loopLabel: nil,
            isOrchestrator: true,
            slot: 0, slotCount: 1, stackCount: 1
        )

        // Expand subagent roles into drawn boxes; collapse if it would get crowded.
        // In compact mode (grid thumbnails, activity panel) we NEVER expand a
        // multi-count role into separate boxes — it always renders as one stacked
        // "×N" card — so the small canvases stay to a handful of legible boxes
        // instead of a tall stack that overlaps.
        let roles = strategy.subagentRoles
        let maxIndividual = compact ? 1 : 5
        var expanded = roles.reduce(0) { $0 + (min($1.count, maxIndividual + 1) <= maxIndividual ? $1.count : 1) }
        let collapse = expanded > (compact ? 4 : 7) || roles.contains { $0.count > maxIndividual }
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
                roleID: box.role.id,
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
    /// Drives ambient motion even when not live (picker, onboarding, editor). The
    /// activity panel passes `false` for the compact idle diagram to stay calm and
    /// cheap when many other things move; anything live always animates.
    var ambient: Bool = true
    /// When set, tapping a node calls this with the role's id — so the diagram
    /// doubles as a selector: click a box to edit that agent in the detail panel.
    var onSelectNode: ((UUID) -> Void)? = nil
    /// The currently-selected role's id — its box gets a highlighted ring so the
    /// diagram and the detail panel always agree on which agent is being edited.
    var selectedRoleID: UUID? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model

    var body: some View {
        let palette = DiagramPalette.make(scheme)
        let spec = DiagramSpecBuilder.build(from: strategy, compact: compact, t: { model.t($0) })
        // Which node (if any) is the one currently working.
        let activeID: UUID? = {
            guard isLive else { return nil }
            if let a = activeAgent {
                return spec.subagents.first { Self.titlesMatch($0.title, a) }?.id
            }
            return spec.orchestrator.id
        }()
        // Which node maps to the role currently open in the detail panel.
        let selectedNodeID: UUID? = selectedRoleID.flatMap { rid in
            spec.allNodes.first { $0.roleID == rid }?.id
        }

        // Motion is the diagram's identity: the coral signal dots always drift along
        // the delegation edges (unless the user asked to reduce motion). A live agent
        // additionally gets a breathing green halo. We still fall back to a single
        // static Canvas when reduceMotion is on, or when a caller opts out of ambient
        // motion (e.g. a wall of idle picker cards) so scrolling never stutters.
        let animate = !reduceMotion && (isLive || ambient)
        // Live diagrams animate at 30fps; idle/ambient ones (e.g. the wall of picker
        // cards) drift at a calmer 20fps so many at once don't stutter the scroll.
        let interval = isLive ? 1.0 / 30.0 : 1.0 / 20.0
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: interval)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    // At rest the halo shouldn't breathe — only the live node pulses.
                    let pulse: CGFloat = isLive ? CGFloat(0.5 + 0.5 * sin(t * 1.7)) : 0.6
                    canvas(spec: spec, palette: palette, activeID: activeID,
                           selectedID: selectedNodeID, time: t, pulse: pulse)
                }
            } else {
                canvas(spec: spec, palette: palette, activeID: activeID,
                       selectedID: selectedNodeID, time: 0, pulse: 0.6)
            }
        }
        // Tap a box to select/edit that agent (only when a caller opts in). Sits above
        // the Canvas as invisible hit targets aligned to the same computed layout.
        .overlay { tapTargets(spec: spec) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Force a fresh Canvas when the strategy changes so the drawing can never
        // lag behind the picker selection.
        .id(strategy.name)
    }

    /// One frame of the diagram. Pure drawing from `size`; no GeometryReader.
    private func canvas(spec: DiagramSpec, palette: DiagramPalette, activeID: UUID?,
                        selectedID: UUID?, time t: Double, pulse: CGFloat) -> some View {
        Canvas { ctx, size in
            let frames = layout(spec: spec, in: size)
            // No opaque canvas fill, no engineering dot-grid — the diagram sits
            // directly on its card surface for a clean, modern, minimal look.
            drawBackground(spec: spec, frames: frames, size: size, pulse: pulse, ctx: &ctx, palette: palette)
            drawEdges(spec: spec, frames: frames, time: t, ctx: &ctx, palette: palette)
            drawNodes(spec: spec, frames: frames, pulse: pulse, activeID: activeID,
                      selectedID: selectedID, ctx: &ctx, palette: palette)
            if !compact {
                drawLabels(spec: spec, frames: frames, size: size, ctx: &ctx, palette: palette)
            }
        }
    }

    /// Invisible tap targets over each node, aligned to the same layout the Canvas
    /// draws, so clicking a box selects that agent. No-op unless `onSelectNode` is set.
    @ViewBuilder
    private func tapTargets(spec: DiagramSpec) -> some View {
        if let onSelectNode {
            GeometryReader { geo in
                let frames = layout(spec: spec, in: geo.size)
                ForEach(spec.allNodes) { node in
                    if let rect = frames[node.id], let rid = node.roleID {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .onTapGesture { onSelectNode(rid) }
                            .help(node.title)
                    }
                }
            }
        }
    }

    // MARK: Layout

    /// Preferred height for a strategy's diagram, so nodes never overlap.
    static func preferredHeight(for strategy: Strategy) -> CGFloat {
        let n = DiagramSpecBuilder.build(from: strategy, t: { $0 }).subagents.count
        return min(max(CGFloat(n) * 66 + 96, 190), 380)
    }

    /// Preferred height for a COMPACT diagram (grid thumbnails): scales with the
    /// number of drawn boxes so cards with many distinct roles get the vertical room
    /// to stay legible, instead of squashing every node into a fixed 148pt.
    static func compactHeight(for strategy: Strategy) -> CGFloat {
        let n = DiagramSpecBuilder.build(from: strategy, compact: true, t: { $0 }).subagents.count
        return min(max(CGFloat(n) * 40 + 76, 132), 260)
    }

    private func nodeWidth(in size: CGSize) -> CGFloat {
        compact ? min(max(size.width * 0.30, 84), 120)
                : min(max(size.width * 0.22, 104), 180)
    }

    private func layout(spec: DiagramSpec, in size: CGSize) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        let w = nodeWidth(in: size)
        let k = max(spec.subagents.count, 1)

        // Fit node height to the available space so boxes NEVER overlap. Each node
        // gets a vertical "slot" (available height / node count); its height is the
        // slot minus a gap, capped by a max so a lone box isn't huge. Crucially there
        // is NO lower floor: a floor taller than the slot is exactly what made boxes
        // stack on top of each other. With many nodes the boxes simply shrink (text
        // is clipped to the box), which reads far better than an overlapping pile.
        let topPad: CGFloat = compact ? 14 : 24
        let availH = max(size.height - topPad * 2, 1)
        let slotSpan = availH / CGFloat(k)
        let gap: CGFloat = min(compact ? 10 : 12, slotSpan * 0.22)
        let nodeH = min(slotSpan - gap, compact ? 54 : 80)

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

        // Subagents evenly stacked on the right (slotSpan computed above). Clamp the
        // vertical position so a node never bleeds past the top/bottom edge (which was
        // clipping the first/last box in tight cards).
        let minY: CGFloat = 3
        let maxY = size.height - nodeH - 3
        for node in spec.subagents {
            let slotCenter = topPad + (CGFloat(node.slot) + 0.5) * slotSpan
            let y = min(max(slotCenter - nodeH / 2, minY), max(minY, maxY))
            frames[node.id] = CGRect(x: rightX, y: y, width: w, height: nodeH)
        }
        return frames
    }

    // MARK: Background (powered-root glow)

    private func drawBackground(spec: DiagramSpec, frames: [UUID: CGRect], size: CGSize, pulse: CGFloat, ctx: inout GraphicsContext, palette: DiagramPalette) {
        // A single soft coral glow behind the orchestrator — just enough warmth to
        // anchor the topology on the card. No dot grid (that read as "lab software").
        if let rect = frames[spec.orchestrator.id] {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r: CGFloat = compact ? 90 : 140
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(colors: [palette.accent.opacity(0.07 + 0.05 * pulse), .clear]),
                    center: c, startRadius: 0, endRadius: r))
        }
    }

    // MARK: Edges

    private func drawEdges(spec: DiagramSpec, frames: [UUID: CGRect], time: Double, ctx: inout GraphicsContext, palette: DiagramPalette) {
        // One clean connection per subagent: a softly-curved coral wire from the
        // orchestrator, carrying a drifting train of coral signal dots (the app's
        // particle identity) toward an arrowhead at the subagent. The old gray dashed
        // "return" arrows and legend are gone — they made the diagram read like lab
        // software; the flowing dots already imply the working relationship.
        var index = 0
        for edge in spec.edges where edge.kind == .delegate {
            guard let a = frames[edge.from], let b = frames[edge.to] else { continue }
            let start = CGPoint(x: a.maxX, y: a.midY)
            let end = CGPoint(x: b.minX - 7, y: b.midY)
            // A gentle S-curve so parallel fan-out wires read as separate strands
            // instead of a crossing bundle.
            let dx = end.x - start.x
            let c1 = CGPoint(x: start.x + dx * 0.5, y: start.y)
            let c2 = CGPoint(x: start.x + dx * 0.5, y: end.y)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: c1, control2: c2)
            ctx.stroke(path, with: .linearGradient(
                Gradient(colors: [palette.accent.opacity(0.55), palette.accent.opacity(0.18)]),
                startPoint: start, endPoint: end),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            let angle = atan2(end.y - c2.y, end.x - c2.x)
            ctx.fill(arrowHead(at: end, angle: angle, size: 8), with: .color(palette.accent.opacity(0.9)))

            // Signal dots riding the curve, phase-staggered per edge so the fan-out
            // ripples in sequence. `time == 0` (reduce-motion / opted-out) collapses to
            // one mid-flight dot so the wire still reads without motion.
            let dotCount = compact ? 2 : 3
            for d in 0..<dotCount {
                let phase = Double(d) / Double(dotCount) + Double(index) * 0.18
                let u = time == 0 ? 0.5 : ((time * 0.30 + phase).truncatingRemainder(dividingBy: 1.0))
                let fade = sin(u * .pi)            // 0 at ends, 1 mid-flight
                guard fade > 0.03 else { continue }
                let p = pointOnCubic(start, c1, c2, end, CGFloat(u))
                let r: CGFloat = compact ? 2.0 : 2.6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.2, y: p.y - r * 2.2,
                                                width: r * 4.4, height: r * 4.4)),
                         with: .color(palette.accent.opacity(0.14 * fade)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(palette.accent.opacity(0.30 + 0.60 * fade)))
                if time == 0 { break }
            }
            index += 1
        }
    }

    /// Point at parameter `u` (0…1) along a cubic Bézier — for placing signal dots.
    private func pointOnCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: CGFloat) -> CGPoint {
        let v = 1 - u
        let a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
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

    private func drawNodes(spec: DiagramSpec, frames: [UUID: CGRect], pulse: CGFloat, activeID: UUID?, selectedID: UUID?, ctx: inout GraphicsContext, palette: DiagramPalette) {
        for node in spec.allNodes {
            guard let rect = frames[node.id] else { continue }
            let live = node.id == activeID

            // A collapsed ×N role is ONE clean box (no messy stacked cards behind it —
            // those overlapped and hid the model text); the count rides a small badge.
            drawBox(rect, node: node, pulse: pulse, live: live, ctx: &ctx, palette: palette)

            // The box open in the detail panel gets a crisp accent selection ring, so
            // clicking a node and editing it on the right always feel connected.
            if node.id == selectedID && !live {
                let ring = Path(roundedRect: rect.insetBy(dx: -2.5, dy: -2.5), cornerRadius: 13)
                ctx.stroke(ring, with: .color(palette.accent), lineWidth: 2)
            }

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

            // ×N badge — a small pill hugging the top-right CORNER (outside the box),
            // so it never sits on the title/model text.
            if node.stackCount > 1 {
                let w: CGFloat = compact ? 22 : 26, h: CGFloat = compact ? 14 : 16
                let cap = CGRect(x: rect.maxX - w * 0.55, y: rect.minY - h * 0.45, width: w, height: h)
                ctx.fill(Path(roundedRect: cap, cornerRadius: h / 2), with: .color(palette.accent))
                drawText(&ctx, Text("×\(node.stackCount)").font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced)),
                         at: CGPoint(x: cap.midX, y: cap.midY), color: Theme.onAccent)
            }
        }
    }

    /// All node boxes share the surface fill; the accent (top-tier / root) node is
    /// "lit" with a Voltage glow ring instead of a fill, like a powered component.
    private func drawBox(_ rect: CGRect, node: DiagramNode, pulse: CGFloat, live: Bool, ctx: inout GraphicsContext, palette: DiagramPalette) {
        let shape = Path(roundedRect: rect, cornerRadius: 11)
        if live {
            // The agent currently at work: a soft breathing green halo + fill tint.
            let green = Theme.success
            let spread = 3.0 + 4.0 * pulse
            let halo = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread), cornerRadius: 11 + spread)
            ctx.fill(shape, with: .color(green.opacity(0.14)))
            ctx.stroke(halo, with: .color(green.opacity(0.22 + 0.26 * pulse)), lineWidth: 5)
            ctx.stroke(shape, with: .color(green), lineWidth: 1.6)
        } else if node.isAccent {
            // The top-tier node: a quiet coral-tinted card with a coral edge — no
            // pulsing "powered" ring (that read as sci-fi lab UI).
            ctx.fill(shape, with: .color(Theme.accentSoft))
            ctx.stroke(shape, with: .color(palette.accent.opacity(0.85)), lineWidth: 1.4)
        } else {
            ctx.fill(shape, with: .color(palette.surface))
            ctx.stroke(shape, with: .color(palette.border), lineWidth: 1)
        }
    }

    // MARK: Labels (drawn in Canvas)

    private func drawLabels(spec: DiagramSpec, frames: [UUID: CGRect], size: CGSize, ctx: inout GraphicsContext, palette: DiagramPalette) {
        let font = Font.system(size: 11.5, weight: .medium).italic()

        // Horizontal centre of the empty gap between the two columns — the only place
        // wide enough for a label. We centre the wire-fan labels here and lift the
        // delegate label above the fan / drop the return label below it, so they never
        // land on top of the wires or on each other (the previous midpoint placement
        // put both in the densest part of the fan and they collided).
        guard let orch = frames[spec.orchestrator.id],
              let firstSub = spec.subagents.first.flatMap({ frames[$0.id] }) else { return }
        let gapMidX = (orch.maxX + firstSub.minX) / 2
        let topY = max(orch.minY - 4, 12)
        let bottomY = min(orch.maxY + 4, size.height - 12)
        // Keep the label inside the canvas even when the estimated text is wide.
        func clampX(_ label: String) -> CGFloat {
            let half = estimatedWidth(label, fontSize: 11.5) / 2
            return min(max(gapMidX, half + 6), size.width - half - 6)
        }

        for edge in spec.edges {
            guard let label = edge.label else { continue }
            let color = edge.kind == .delegate ? palette.accent : palette.secondary
            let y = edge.kind == .delegate ? topY : bottomY
            drawText(&ctx, Text(label).font(font), at: CGPoint(x: clampX(label), y: y), color: color)
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

    /// Rough width of a string at a font size (same heuristic as `truncated`), used
    /// to keep centred edge labels inside the canvas without a full text measure.
    private func estimatedWidth(_ s: String, fontSize: CGFloat) -> CGFloat {
        CGFloat(s.count) * fontSize * 0.55
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
