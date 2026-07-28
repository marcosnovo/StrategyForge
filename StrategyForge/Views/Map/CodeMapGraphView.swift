//
//  CodeMapGraphView.swift
//  StrategyForge
//
//  Native Canvas render of a `CodeGraph` (graphify's output): a clustered map of the
//  codebase. Nodes are laid out by Leiden community — each cluster gets its own coloured
//  region with a soft glow — sized by degree, wired by faint intra-cluster lines with
//  brighter coral cross-cluster links (the seams where modules talk to each other). It
//  reuses the drawing idioms of StrategyDiagramView (pure Canvas, clipped labels, the
//  coral accent) so the Map feels of a piece with the rest of the app. Full pan/zoom/
//  search lives in graphify's own interactive HTML; this is the glanceable, on-brand
//  overview. Big graphs are capped to the top nodes by degree (the caller shows how
//  many of how many) so the Canvas stays cheap and legible.
//

import SwiftUI

struct CodeMapGraphView: View {
    let graph: CodeGraph
    @Binding var selectedNodeID: String?

    /// Keep the Canvas cheap + legible: render the most-connected nodes, and cap edges.
    private let maxNodes = 240
    private let maxEdges = 900
    /// Roughly how many labels to show (the hubs) so text doesn't turn into a smudge.
    private let maxLabels = 26

    /// Vibrant but calm cluster palette — the first two are the brand tokens, the rest
    /// spread the hue wheel so adjacent communities stay distinguishable.
    private static let clusterColors: [Color] = [
        Theme.coral, Theme.teal, .purple, .orange, .green,
        .blue, .pink, .indigo, .mint, .brown, .cyan, .yellow
    ]
    private func color(_ community: Int) -> Color {
        Self.clusterColors[((community % Self.clusterColors.count) + Self.clusterColors.count) % Self.clusterColors.count]
    }

    /// The nodes we actually draw (top by degree), and a quick id→node lookup.
    private var rendered: [CodeGraph.Node] {
        graph.nodes.sorted { $0.degree > $1.degree }.prefix(maxNodes).map { $0 }
    }

    var body: some View {
        let nodes = rendered
        let ids = Set(nodes.map { $0.id })
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let edges = Array(graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }.prefix(maxEdges))
        let norm = Self.layout(nodes: nodes)                     // normalised positions
        let labelIDs = Set(nodes.sorted { $0.degree > $1.degree }.prefix(maxLabels).map { $0.id })

        // Selection focus: when a node is tapped, only it + its direct neighbours stay lit;
        // everything else dims. This is what turns the cross-cluster hairball into a legible
        // "who does this touch?" view — the single biggest readability win.
        let focus = selectedNodeID
        let neighbors = Self.neighborIDs(of: focus, in: edges)

        Canvas { ctx, size in
            let frames = Self.fit(norm, in: size)
            drawClusterGlows(nodes: nodes, frames: frames, dimmed: focus != nil, ctx: &ctx)

            // Edges. At rest they're a whisper (the topology is implied, not shouted); with a
            // selection, only the incident edges light up in coral and ride on top.
            if focus == nil {
                for e in edges {
                    let cross = byID[e.source]?.community != byID[e.target]?.community
                    let col = cross ? Theme.coral.opacity(0.10) : color(byID[e.source]?.community ?? 0).opacity(0.09)
                    stroke(e, frames: frames, color: col, width: cross ? 0.7 : 0.6, ctx: &ctx)
                }
            } else {
                for e in edges where e.source != focus && e.target != focus {
                    stroke(e, frames: frames, color: Color.gray.opacity(0.05), width: 0.5, ctx: &ctx)
                }
                for e in edges where e.source == focus || e.target == focus {
                    stroke(e, frames: frames, color: Theme.coral.opacity(0.8), width: 1.5, ctx: &ctx)
                }
            }

            for node in nodes {
                guard let p = frames[node.id] else { continue }
                let dim = focus != nil && node.id != focus && !neighbors.contains(node.id)
                drawNode(node, at: p, selected: node.id == focus, dim: dim, ctx: &ctx)
            }

            // Labels: hubs at rest; with a selection, the focus + its neighbours instead.
            for node in nodes {
                let show = focus == nil ? labelIDs.contains(node.id)
                                        : (node.id == focus || neighbors.contains(node.id))
                guard show, let p = frames[node.id] else { continue }
                let r = radius(node.degree)
                let text = Text(String(node.label.prefix(24))).font(.system(size: 9.5, weight: .medium))
                var tctx = ctx
                drawText(&tctx, text, at: CGPoint(x: p.x, y: p.y + r + 7),
                         color: node.id == focus ? Theme.ink : Theme.secondaryOnMaterial)
            }
        }
        .overlay { tapTargets(nodes: nodes, norm: norm) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous))
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

    // MARK: Drawing

    private func drawClusterGlows(nodes: [CodeGraph.Node], frames: [String: CGPoint], dimmed: Bool, ctx: inout GraphicsContext) {
        // One soft radial wash behind each community's centroid — gives the map depth and
        // makes clusters read as places, not a uniform hairball. Cheap: one fill per cluster.
        var sum: [Int: (x: CGFloat, y: CGFloat, n: CGFloat)] = [:]
        for node in nodes {
            guard let p = frames[node.id] else { continue }
            let cur = sum[node.community] ?? (0, 0, 0)
            sum[node.community] = (cur.x + p.x, cur.y + p.y, cur.n + 1)
        }
        let alpha = dimmed ? 0.05 : 0.12
        for (community, s) in sum where s.n > 0 {
            let c = CGPoint(x: s.x / s.n, y: s.y / s.n)
            let r = max(50, 26 * sqrt(s.n))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [color(community).opacity(alpha), .clear]),
                                           center: c, startRadius: 0, endRadius: r))
        }
    }

    private func stroke(_ e: CodeGraph.Edge, frames: [String: CGPoint], color: Color, width: CGFloat, ctx: inout GraphicsContext) {
        guard let a = frames[e.source], let b = frames[e.target] else { return }
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawNode(_ node: CodeGraph.Node, at p: CGPoint, selected: Bool, dim: Bool, ctx: inout GraphicsContext) {
        let r = radius(node.degree)
        let tint = color(node.community)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        let fillA = dim ? 0.18 : 0.92
        let ringA = dim ? 0.2 : 0.75
        // Lit dot: soft drop shadow, tint fill, a top inner-light highlight, thin white ring.
        // A dimmed node (not near the selection) fades back so the focus reads clearly.
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

    /// Node screen radius from its degree (hubs bigger), gently compressed so a very
    /// high-degree node doesn't dominate.
    private func radius(_ degree: Int) -> CGFloat {
        min(max(2.6 + sqrt(Double(degree)) * 1.7, 2.6), 15)
    }

    private func drawText(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint, color: Color) {
        var resolved = ctx.resolve(text)
        resolved.shading = .color(color)
        ctx.draw(resolved, at: point, anchor: .center)
    }

    // MARK: Tap targets

    @ViewBuilder
    private func tapTargets(nodes: [CodeGraph.Node], norm: [String: CGPoint]) -> some View {
        GeometryReader { geo in
            let frames = Self.fit(norm, in: geo.size)
            ForEach(nodes) { node in
                if let p = frames[node.id] {
                    let hit = max(radius(node.degree) + 5, 11)
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

    // MARK: Layout (deterministic — communities on a ring, nodes on a golden-angle spiral)

    /// Normalised node positions (~[-1, 1] range) grouped by community. Deterministic:
    /// no randomness, so the same graph always lays out identically.
    private static func layout(nodes: [CodeGraph.Node]) -> [String: CGPoint] {
        var groups: [Int: [CodeGraph.Node]] = [:]
        for n in nodes { groups[n.community, default: []].append(n) }
        // Biggest clusters first — they get the roomier inner positions.
        let communities = groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
        let C = communities.count
        let golden = 2.399963229728653   // radians — the sunflower angle
        if C == 0 { return [:] }

        // Per-cluster blob radius (bigger membership → bigger blob).
        let radius = communities.map { 0.6 + 0.5 * sqrt(Double(groups[$0]!.count)) }

        // Seed centroids on a golden-angle spiral so they start spread across 2D (NOT on a
        // ring — the ring was the hairball). Then relax to remove overlaps: a cheap
        // repulsion on the centroids only (deterministic; nodes are placed afterwards).
        var cx = [Double](repeating: 0, count: C)
        var cy = [Double](repeating: 0, count: C)
        let seed = 1.8 * (radius.reduce(0, +) / Double(C))
        for i in 0..<C {
            let rr = seed * sqrt(Double(i) + 0.5)
            cx[i] = rr * cos(Double(i) * golden)
            cy[i] = rr * sin(Double(i) * golden)
        }
        if C > 1 {
            let iters = C > 60 ? 40 : 160   // guard: keep it cheap even with many clusters
            for _ in 0..<iters {
                var dx = [Double](repeating: 0, count: C)
                var dy = [Double](repeating: 0, count: C)
                for a in 0..<C {
                    for b in (a + 1)..<C {
                        var ex = cx[a] - cx[b], ey = cy[a] - cy[b]
                        var dist = (ex * ex + ey * ey).squareRoot()
                        if dist < 0.0001 { ex = Double(a - b); ey = Double(a + 1); dist = (ex * ex + ey * ey).squareRoot() }
                        let target = radius[a] + radius[b] + 0.4   // desired gap between blobs
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

        // Place nodes: the hub at the centroid, the rest on a sunflower within the blob.
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

    /// Fit normalised positions into `size` with padding, preserving aspect.
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

/// A synthetic multi-cluster graph so the render can be eyeballed without running
/// graphify: 6 communities of hub-and-spoke nodes, wired within and (sparsely) across.
private func sampleGraph() -> CodeGraph {
    var nodes: [CodeGraph.Node] = []
    var edges: [CodeGraph.Edge] = []
    let sizes = [14, 10, 9, 7, 6, 5]
    for (c, n) in sizes.enumerated() {
        let hub = "c\(c)_hub"
        nodes.append(CodeGraph.Node(id: hub, label: "Module \(c)", kind: "file", community: c,
                                    file: "module\(c).swift", line: 1))
        for i in 0..<n {
            let id = "c\(c)_\(i)"
            nodes.append(CodeGraph.Node(id: id, label: "sym_\(c)_\(i)", kind: "function", community: c,
                                        file: "module\(c).swift", line: 10 + i * 7))
            edges.append(CodeGraph.Edge(source: hub, target: id, label: "calls"))
            if i > 0 { edges.append(CodeGraph.Edge(source: "c\(c)_\(i - 1)", target: id, label: nil)) }
        }
    }
    // A few cross-cluster seams (the coral links).
    for c in 1..<sizes.count { edges.append(CodeGraph.Edge(source: "c0_hub", target: "c\(c)_hub", label: "imports")) }
    edges.append(CodeGraph.Edge(source: "c2_hub", target: "c4_hub", label: "imports"))
    // Recompute degree so hubs render large.
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
