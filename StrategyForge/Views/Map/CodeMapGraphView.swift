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
        let edges = graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }.prefix(maxEdges)
        let norm = Self.layout(nodes: nodes)                     // normalised positions
        let labelIDs = Set(nodes.sorted { $0.degree > $1.degree }.prefix(maxLabels).map { $0.id })

        Canvas { ctx, size in
            let frames = Self.fit(norm, in: size)
            drawClusterGlows(nodes: nodes, frames: frames, ctx: &ctx)
            // Intra-cluster wires first (faint), cross-cluster coral seams on top.
            for e in edges where byID[e.source]?.community == byID[e.target]?.community {
                stroke(e, frames: frames, color: color(byID[e.source]?.community ?? 0).opacity(0.16), width: 0.7, ctx: &ctx)
            }
            for e in edges where byID[e.source]?.community != byID[e.target]?.community {
                stroke(e, frames: frames, color: Theme.coral.opacity(0.22), width: 0.8, ctx: &ctx)
            }
            for node in nodes {
                guard let p = frames[node.id] else { continue }
                drawNode(node, at: p, selected: node.id == selectedNodeID, ctx: &ctx)
            }
            // Labels for the hubs (+ the selection), clipped so long symbol names don't bleed.
            for node in nodes where labelIDs.contains(node.id) || node.id == selectedNodeID {
                guard let p = frames[node.id] else { continue }
                let r = radius(node.degree)
                let text = Text(String(node.label.prefix(24))).font(.system(size: 9.5, weight: .medium))
                var tctx = ctx
                drawText(&tctx, text, at: CGPoint(x: p.x, y: p.y + r + 7),
                         color: node.id == selectedNodeID ? Theme.ink : Theme.secondaryOnMaterial)
            }
        }
        .overlay { tapTargets(nodes: nodes, norm: norm) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous))
    }

    // MARK: Drawing

    private func drawClusterGlows(nodes: [CodeGraph.Node], frames: [String: CGPoint], ctx: inout GraphicsContext) {
        // One soft radial wash behind each community's centroid — gives the map depth and
        // makes clusters read as places, not a uniform hairball. Cheap: one fill per cluster.
        var sum: [Int: (x: CGFloat, y: CGFloat, n: CGFloat)] = [:]
        for node in nodes {
            guard let p = frames[node.id] else { continue }
            let cur = sum[node.community] ?? (0, 0, 0)
            sum[node.community] = (cur.x + p.x, cur.y + p.y, cur.n + 1)
        }
        for (community, s) in sum where s.n > 0 {
            let c = CGPoint(x: s.x / s.n, y: s.y / s.n)
            let r = max(50, 26 * sqrt(s.n))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [color(community).opacity(0.10), .clear]),
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

    private func drawNode(_ node: CodeGraph.Node, at p: CGPoint, selected: Bool, ctx: inout GraphicsContext) {
        let r = radius(node.degree)
        let tint = color(node.community)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        // Lit dot: soft drop shadow, tint fill, a top inner-light highlight, thin white ring.
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1))
            layer.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.92)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.7, width: r, height: r)),
                 with: .color(.white.opacity(0.25)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.75)), lineWidth: 0.6)
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
        let communities = groups.keys.sorted()
        let C = max(communities.count, 1)
        let golden = 2.399963229728653   // radians — the sunflower angle

        var pos: [String: CGPoint] = [:]
        for (ci, community) in communities.enumerated() {
            // Cluster centroid on a big ring (single cluster → centre).
            let centroid: CGPoint
            if C == 1 {
                centroid = .zero
            } else {
                let a = 2 * Double.pi * Double(ci) / Double(C)
                centroid = CGPoint(x: cos(a), y: sin(a))
            }
            let members = groups[community]!.sorted { $0.degree > $1.degree }
            let spread = 0.16 + 0.5 / Double(C)   // tighter clusters when there are many
            for (k, node) in members.enumerated() {
                if k == 0 {
                    pos[node.id] = centroid   // the hub sits at the cluster centre
                    continue
                }
                let rr = spread * sqrt(Double(k))
                let th = Double(k) * golden
                pos[node.id] = CGPoint(x: centroid.x + rr * cos(th), y: centroid.y + rr * sin(th))
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
