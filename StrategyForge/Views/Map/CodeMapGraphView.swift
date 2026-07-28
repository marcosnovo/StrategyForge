//
//  CodeMapGraphView.swift
//  StrategyForge
//
//  Native Canvas render of a `CodeGraph` (graphify's output): a clustered, interactive map
//  of the codebase. Nodes are laid out by Leiden community into separated lobes (not a ring),
//  sized by degree, coloured per cluster. Interaction is the point:
//   • tap a node → only it + its direct neighbours stay lit (coral edges with flowing
//     particles); everything else dims — the "what does this touch?" view.
//   • pinch to zoom, drag to pan, double-tap to reset.
//   • a search/filter match set (from the toolbar) dims everything that doesn't match.
//  Full pan/zoom/search also lives in graphify's own HTML ("Interactive"); this is the
//  on-brand, glanceable native view. Big graphs are capped to the top nodes by degree.
//

import SwiftUI

struct CodeMapGraphView: View {
    let graph: CodeGraph
    @Binding var selectedNodeID: String?
    /// Nodes matching the toolbar search/filter; nil = no filter (everything active).
    var matchIDs: Set<String>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// Memoised layout so panning/zooming (which re-evaluate the body) don't recompute it.
    @State private var norm: [String: CGPoint] = [:]

    private let maxNodes = 240
    private let maxEdges = 900
    private let maxLabels = 26

    private static let clusterColors: [Color] = [
        Theme.coral, Theme.teal, .purple, .orange, .green,
        .blue, .pink, .indigo, .mint, .brown, .cyan, .yellow
    ]
    private func color(_ community: Int) -> Color { Self.clusterColor(community) }

    /// Shared so the cluster legend uses the exact same colours as the graph.
    static func clusterColor(_ community: Int) -> Color {
        clusterColors[((community % clusterColors.count) + clusterColors.count) % clusterColors.count]
    }

    private var rendered: [CodeGraph.Node] {
        graph.nodes.sorted { $0.degree > $1.degree }.prefix(maxNodes).map { $0 }
    }

    var body: some View {
        let nodes = rendered
        let ids = Set(nodes.map { $0.id })
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let edges = Array(graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }.prefix(maxEdges))
        let liveNorm = norm.isEmpty ? Self.layout(nodes: nodes) : norm
        let labelIDs = Set(nodes.sorted { $0.degree > $1.degree }.prefix(maxLabels).map { $0.id })
        let focus = selectedNodeID
        let neighbors = Self.neighborIDs(of: focus, in: edges)

        ZStack {
            // The map is ALIVE (a coral-shaped graph): nodes breathe and drift, cluster
            // glows pulse, and faint coral particles flow along the veins between modules —
            // continuously, not just on selection. Calm 24fps; static under Reduce Motion.
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { tl in
                    graphCanvas(time: tl.date.timeIntervalSinceReferenceDate,
                                nodes: nodes, byID: byID, edges: edges, norm: liveNorm,
                                labelIDs: labelIDs, focus: focus, neighbors: neighbors)
                }
            } else {
                graphCanvas(time: 0, nodes: nodes, byID: byID, edges: edges, norm: liveNorm,
                            labelIDs: labelIDs, focus: focus, neighbors: neighbors)
            }
            tapTargets(nodes: nodes, norm: liveNorm)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { offset = CGSize(width: lastOffset.width + $0.translation.width,
                                             height: lastOffset.height + $0.translation.height) }
                .onEnded { _ in lastOffset = offset }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale = min(max(lastScale * $0, 0.4), 6) }
                .onEnded { _ in lastScale = scale }
        )
        .onTapGesture(count: 2) { resetView() }
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous))
        .task(id: graph.nodes.count &* 1000 &+ graph.edges.count) {
            norm = Self.layout(nodes: nodes)
        }
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        }
    }

    // MARK: One frame

    private func graphCanvas(time: Double, nodes: [CodeGraph.Node], byID: [String: CodeGraph.Node],
                             edges: [CodeGraph.Edge], norm: [String: CGPoint], labelIDs: Set<String>,
                             focus: String?, neighbors: Set<String>) -> some View {
        Canvas { ctx, size in
            let base = Self.fit(norm, in: size)
            // Living drift: each node sways on its own gentle sine, so the whole graph
            // undulates like coral in a current. Small amplitude so it reads as "alive",
            // not chaotic (and tap targets, which use the un-swayed layout, still line up).
            let sway: CGFloat = time == 0 ? 0 : 3.0
            var frames: [String: CGPoint] = [:]
            frames.reserveCapacity(nodes.count)
            for (i, node) in nodes.enumerated() {
                guard let bp = base[node.id] else { continue }
                let p = transform(bp, in: size)
                let ph = Double(i)
                frames[node.id] = CGPoint(x: p.x + CGFloat(sin(time * 0.55 + ph * 1.3)) * sway,
                                          y: p.y + CGFloat(cos(time * 0.5 + ph * 0.9)) * sway)
            }
            let dimming = focus != nil || matchIDs != nil
            let glowPulse = time == 0 ? 1.0 : (0.82 + 0.18 * sin(time * 0.5))

            drawClusterGlows(nodes: nodes, frames: frames, dimmed: dimming, pulse: glowPulse, ctx: &ctx)

            if focus == nil {
                for e in edges {
                    let cross = byID[e.source]?.community != byID[e.target]?.community
                    let col = cross ? Theme.coral.opacity(0.10) : color(byID[e.source]?.community ?? 0).opacity(0.09)
                    curve(e, frames: frames, color: col, width: cross ? 0.7 : 0.6, ctx: &ctx)
                }
                // Ambient bioluminescence: a few coral motes always drifting along the veins
                // between clusters — the "alive" signal, capped so it stays cheap.
                if time > 0 {
                    var count = 0
                    for e in edges where byID[e.source]?.community != byID[e.target]?.community {
                        drawParticles(e, frames: frames, time: time, ctx: &ctx, faint: true)
                        count += 1
                        if count >= 40 { break }
                    }
                }
            } else {
                for e in edges where e.source != focus && e.target != focus {
                    curve(e, frames: frames, color: Color.gray.opacity(0.05), width: 0.5, ctx: &ctx)
                }
                for e in edges where e.source == focus || e.target == focus {
                    curve(e, frames: frames, color: Theme.coral.opacity(0.85), width: 1.6, ctx: &ctx)
                    if time > 0 { drawParticles(e, frames: frames, time: time, ctx: &ctx) }
                }
            }

            for (i, node) in nodes.enumerated() {
                guard let p = frames[node.id] else { continue }
                // Breathing: each node's radius pulses on its own phase, like a polyp.
                let breathe = time == 0 ? 1.0 : (1.0 + 0.06 * sin(time * 1.1 + Double(i) * 0.7))
                drawNode(node, at: p, selected: node.id == focus,
                         dim: isDim(node, focus: focus, neighbors: neighbors),
                         breathe: breathe, ctx: &ctx)
            }

            for node in nodes {
                let show = focus == nil ? labelIDs.contains(node.id)
                                        : (node.id == focus || neighbors.contains(node.id))
                guard show, let p = frames[node.id] else { continue }
                let r = radius(node.degree) * scale
                let text = Text(String(node.label.prefix(24))).font(.system(size: 9.5, weight: .medium))
                var tctx = ctx
                drawText(&tctx, text, at: CGPoint(x: p.x, y: p.y + r + 7),
                         color: node.id == focus ? Theme.ink : Theme.secondaryOnMaterial)
            }
        }
    }

    private func isDim(_ node: CodeGraph.Node, focus: String?, neighbors: Set<String>) -> Bool {
        if let f = focus { return node.id != f && !neighbors.contains(node.id) }
        if let m = matchIDs { return !m.contains(node.id) }
        return false
    }

    /// Apply zoom + pan around the canvas centre.
    private func transform(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: (p.x - cx) * scale + cx + offset.width,
                       y: (p.y - cy) * scale + cy + offset.height)
    }

    // MARK: Drawing

    private func drawClusterGlows(nodes: [CodeGraph.Node], frames: [String: CGPoint], dimmed: Bool, pulse: Double, ctx: inout GraphicsContext) {
        var sum: [Int: (x: CGFloat, y: CGFloat, n: CGFloat)] = [:]
        for node in nodes {
            guard let p = frames[node.id] else { continue }
            let cur = sum[node.community] ?? (0, 0, 0)
            sum[node.community] = (cur.x + p.x, cur.y + p.y, cur.n + 1)
        }
        let alpha = (dimmed ? 0.05 : 0.13) * pulse   // the reef breathes
        for (community, s) in sum where s.n > 0 {
            let c = CGPoint(x: s.x / s.n, y: s.y / s.n)
            let r = max(50, 26 * sqrt(s.n)) * scale
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [color(community).opacity(alpha), .clear]),
                                           center: c, startRadius: 0, endRadius: r))
        }
    }

    /// A gently bowed edge (quadratic curve) — reads as separate strands, not a straight mesh.
    private func curve(_ e: CodeGraph.Edge, frames: [String: CGPoint], color: Color, width: CGFloat, ctx: inout GraphicsContext) {
        guard let a = frames[e.source], let b = frames[e.target] else { return }
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: Self.controlPoint(a, b))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// Coral particles drifting along a lit edge (only shown for the selection's edges, so
    /// the count is tiny and cheap). Phase-staggered so they ripple outward.
    private func drawParticles(_ e: CodeGraph.Edge, frames: [String: CGPoint], time: Double, ctx: inout GraphicsContext, faint: Bool = false) {
        guard let a = frames[e.source], let b = frames[e.target] else { return }
        let c = Self.controlPoint(a, b)
        let dots = faint ? 2 : 3
        for d in 0..<dots {
            let phase = Double(d) / Double(dots)
            let u = (time * (faint ? 0.28 : 0.5) + phase).truncatingRemainder(dividingBy: 1.0)
            let fade = sin(u * .pi)
            guard fade > 0.03 else { continue }
            let p = Self.pointOnQuad(a, c, b, CGFloat(u))
            let r: CGFloat = faint ? 1.7 : 2.4
            let base = faint ? 0.08 : 0.35, span = faint ? 0.28 : 0.55
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Theme.coral.opacity(base + span * fade)))
        }
    }

    private static func controlPoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let bow: CGFloat = min(len * 0.12, 30)
        return CGPoint(x: mid.x - dy / len * bow, y: mid.y + dx / len * bow)
    }

    private static func pointOnQuad(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let v = 1 - t
        return CGPoint(x: v * v * p0.x + 2 * v * t * p1.x + t * t * p2.x,
                       y: v * v * p0.y + 2 * v * t * p1.y + t * t * p2.y)
    }

    private func drawNode(_ node: CodeGraph.Node, at p: CGPoint, selected: Bool, dim: Bool, breathe: Double, ctx: inout GraphicsContext) {
        let r = radius(node.degree) * scale * CGFloat(breathe)
        let tint = color(node.community)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        let fillA = dim ? 0.18 : 0.92
        let ringA = dim ? 0.2 : 0.75
        // Bioluminescent halo: a soft tinted glow around the HUBS (degree ≥ 2) that swells
        // with the breath — the coral's living light. Skipped on leaves and when dimmed, so
        // it reads as glowing polyps, not a uniform blur.
        if !dim && node.degree >= 2 {
            let hr = r + 3 + 3 * CGFloat(breathe)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - hr, y: p.y - hr, width: 2 * hr, height: 2 * hr)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.22), .clear]),
                                           center: p, startRadius: r * 0.6, endRadius: hr))
        }
        ctx.drawLayer { layer in
            if !dim { layer.addFilter(.shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)) }
            layer.fill(Path(ellipseIn: rect), with: .color(tint.opacity(fillA)))
        }
        if !dim {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.7, width: r, height: r)),
                     with: .color(.white.opacity(0.25)))
        }
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(ringA)), lineWidth: 0.6)
        if selected {
            let ring = rect.insetBy(dx: -3.5, dy: -3.5)
            ctx.stroke(Path(ellipseIn: ring), with: .color(Theme.coral), lineWidth: 2)
        }
    }

    private func radius(_ degree: Int) -> CGFloat {
        min(max(2.6 + sqrt(Double(degree)) * 1.7, 2.6), 15)
    }

    private func drawText(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint, color: Color) {
        var resolved = ctx.resolve(text)
        resolved.shading = .color(color)
        ctx.draw(resolved, at: point, anchor: .center)
    }

    /// Ids directly connected to `focus` (both directions), for the selection-focus dim.
    private static func neighborIDs(of focus: String?, in edges: [CodeGraph.Edge]) -> Set<String> {
        guard let f = focus else { return [] }
        var n = Set<String>()
        for e in edges {
            if e.source == f { n.insert(e.target) }
            if e.target == f { n.insert(e.source) }
        }
        return n
    }

    // MARK: Tap targets

    @ViewBuilder
    private func tapTargets(nodes: [CodeGraph.Node], norm: [String: CGPoint]) -> some View {
        GeometryReader { geo in
            let base = Self.fit(norm, in: geo.size)
            ForEach(nodes) { node in
                if let bp = base[node.id] {
                    let p = transform(bp, in: geo.size)
                    let hit = max(radius(node.degree) * scale + 5, 11)
                    Circle()
                        .fill(.clear)
                        .contentShape(Circle())
                        .frame(width: hit * 2, height: hit * 2)
                        .position(p)
                        .onTapGesture { selectedNodeID = (selectedNodeID == node.id) ? nil : node.id }
                        .help(node.label)
                }
            }
        }
    }

    // MARK: Layout (deterministic — cluster lobes)

    private static func layout(nodes: [CodeGraph.Node]) -> [String: CGPoint] {
        var groups: [Int: [CodeGraph.Node]] = [:]
        for n in nodes { groups[n.community, default: []].append(n) }
        let communities = groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
        let C = communities.count
        let golden = 2.399963229728653
        if C == 0 { return [:] }

        let radius = communities.map { 0.6 + 0.5 * sqrt(Double(groups[$0]!.count)) }

        var cx = [Double](repeating: 0, count: C)
        var cy = [Double](repeating: 0, count: C)
        let seed = 1.8 * (radius.reduce(0, +) / Double(C))
        for i in 0..<C {
            let rr = seed * sqrt(Double(i) + 0.5)
            cx[i] = rr * cos(Double(i) * golden)
            cy[i] = rr * sin(Double(i) * golden)
        }
        if C > 1 {
            let iters = C > 60 ? 40 : 160
            for _ in 0..<iters {
                var dx = [Double](repeating: 0, count: C)
                var dy = [Double](repeating: 0, count: C)
                for a in 0..<C {
                    for b in (a + 1)..<C {
                        var ex = cx[a] - cx[b], ey = cy[a] - cy[b]
                        var dist = (ex * ex + ey * ey).squareRoot()
                        if dist < 0.0001 { ex = Double(a - b); ey = Double(a + 1); dist = (ex * ex + ey * ey).squareRoot() }
                        let target = radius[a] + radius[b] + 0.4
                        if dist < target {
                            let push = (target - dist) / dist * 0.5
                            dx[a] += ex * push; dy[a] += ey * push
                            dx[b] -= ex * push; dy[b] -= ey * push
                        }
                    }
                }
                for i in 0..<C { cx[i] += dx[i]; cy[i] += dy[i] }
            }
        }

        var pos: [String: CGPoint] = [:]
        for i in 0..<C {
            let members = groups[communities[i]]!.sorted { $0.degree > $1.degree }
            let n = members.count
            let blob = radius[i]
            for (k, node) in members.enumerated() {
                if k == 0 { pos[node.id] = CGPoint(x: cx[i], y: cy[i]); continue }
                let rr = blob * sqrt(Double(k) / Double(max(n - 1, 1)))
                let th = Double(k) * golden
                pos[node.id] = CGPoint(x: cx[i] + rr * cos(th), y: cy[i] + rr * sin(th))
            }
        }
        return pos
    }

    private static func fit(_ norm: [String: CGPoint], in size: CGSize) -> [String: CGPoint] {
        guard !norm.isEmpty else { return [:] }
        let xs = norm.values.map { $0.x }, ys = norm.values.map { $0.y }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let spanX = max(maxX - minX, 0.0001), spanY = max(maxY - minY, 0.0001)
        let pad: CGFloat = 40
        let scale = min((size.width - 2 * pad) / spanX, (size.height - 2 * pad) / spanY)
        let dataCenter = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let screenCenter = CGPoint(x: size.width / 2, y: size.height / 2)
        var out: [String: CGPoint] = [:]
        out.reserveCapacity(norm.count)
        for (id, p) in norm {
            out[id] = CGPoint(x: screenCenter.x + (p.x - dataCenter.x) * scale,
                              y: screenCenter.y + (p.y - dataCenter.y) * scale)
        }
        return out
    }
}

// MARK: - Preview

private func sampleGraph() -> CodeGraph {
    var nodes: [CodeGraph.Node] = []
    var edges: [CodeGraph.Edge] = []
    let sizes = [14, 10, 9, 7, 6, 5]
    for (c, n) in sizes.enumerated() {
        let hub = "c\(c)_hub"
        nodes.append(CodeGraph.Node(id: hub, label: "Module \(c)", kind: "file", community: c,
                                    communityName: "Module \(c)", file: "module\(c).swift", line: 1))
        for i in 0..<n {
            let id = "c\(c)_\(i)"
            nodes.append(CodeGraph.Node(id: id, label: "sym_\(c)_\(i)", kind: "function", community: c,
                                        communityName: "Module \(c)", file: "module\(c).swift", line: 10 + i * 7))
            edges.append(CodeGraph.Edge(source: hub, target: id, label: "calls"))
            if i > 0 { edges.append(CodeGraph.Edge(source: "c\(c)_\(i - 1)", target: id, label: nil)) }
        }
    }
    for c in 1..<sizes.count { edges.append(CodeGraph.Edge(source: "c0_hub", target: "c\(c)_hub", label: "imports")) }
    edges.append(CodeGraph.Edge(source: "c2_hub", target: "c4_hub", label: "imports"))
    var degree: [String: Int] = [:]
    for e in edges { degree[e.source, default: 0] += 1; degree[e.target, default: 0] += 1 }
    for i in nodes.indices { nodes[i].degree = degree[nodes[i].id] ?? 0 }
    return CodeGraph(nodes: nodes, edges: edges, communityCount: sizes.count)
}

#Preview("Code map") {
    CodeMapGraphView(graph: sampleGraph(), selectedNodeID: .constant("c1_hub"))
        .frame(width: 720, height: 520)
        .padding()
        .background(Theme.appBg)
}
