//
//  CodeMapGraphView.swift
//  StrategyForge
//
//  Native Canvas render of a `CodeGraph` (graphify's output): a clustered, LIVING map of the
//  codebase — a coral shaped like a graph. Two modes:
//   • Sphere (default): clusters become patches on a rotating 3D globe (the same Fibonacci-
//     sphere projection as the app's brand spinner), drag to ROTATE, depth-cued so the front
//     face is bright and large. Reads like the loader, but it's your code.
//   • Flat: separated cluster lobes on a plane, drag to pan.
//  Both breathe: nodes pulse, hub nodes carry a bioluminescent halo, cluster glows throb, and
//  faint coral motes drift along the veins between modules. Tap a node → it + its neighbours
//  stay lit, the rest dims. Pinch to zoom, double-tap to reset. Static under Reduce Motion.
//

import SwiftUI
import AppKit

/// A tiny 3D point for the sphere layout (kept local so the Map doesn't couple to the spinner).
private struct V3 { var x: Double; var y: Double; var z: Double }

/// Installs a scoped scroll-wheel monitor so the mouse wheel / two-finger scroll zooms the
/// graph when the cursor is over it — without stealing SwiftUI's tap/drag gestures (a
/// transparent overlay would swallow clicks; a local NSEvent monitor doesn't).
private struct ScrollZoomInstaller: NSViewRepresentable {
    let onZoom: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.host = v
        context.coordinator.onZoom = onZoom
        context.coordinator.install()
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onZoom = onZoom }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var host: NSView?
        var onZoom: ((CGFloat) -> Void)?
        private var monitor: Any?
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let host = self.host, let window = host.window, event.window === window
                else { return event }
                let p = host.convert(event.locationInWindow, from: nil)
                guard host.bounds.contains(p) else { return event }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
                if abs(delta) < 0.001 { return event }
                self.onZoom?(CGFloat(1 + delta * 0.006))
                return nil   // consume — don't scroll anything behind
            }
        }
        func remove() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
    }
}

struct CodeMapGraphView: View {
    let graph: CodeGraph
    @Binding var selectedNodeID: String?
    /// Nodes matching the toolbar search/filter; nil = no filter (everything active).
    var matchIDs: Set<String>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sphere = true
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    // Sphere rotation (radians): a gentle default tilt so it reads as a globe.
    @State private var rotX: Double = 0.5
    @State private var rotY: Double = 0
    @State private var lastRotX: Double = 0.5
    @State private var lastRotY: Double = 0
    // Memoised layouts so pan/zoom/rotate (which re-evaluate the body) don't recompute them.
    @State private var norm: [String: CGPoint] = [:]
    @State private var sphere3D: [String: V3] = [:]

    private let maxNodes = 240
    private let maxEdges = 650
    private let maxLabels = 26

    private func color(_ community: Int) -> Color { Self.clusterColor(community) }

    /// A DESIGNED categorical palette: coral leads the biggest cluster (the brand), and every
    /// other family gets a maximally-distinct hue via golden-angle spacing at a fixed, tasteful
    /// saturation/brightness — so families read as clearly different (like the old interactive)
    /// yet stay cohesive and premium (not a raw system rainbow). Shared with the legend/panel.
    static func clusterColor(_ community: Int) -> Color {
        if community <= 0 { return Theme.coral }
        let hue = (0.11 + Double(community) * 0.6180339887).truncatingRemainder(dividingBy: 1.0)
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    private var rendered: [CodeGraph.Node] {
        graph.nodes.sorted { $0.degree > $1.degree }.prefix(maxNodes).map { $0 }
    }

    var body: some View {
        let nodes = rendered
        let ids = Set(nodes.map { $0.id })
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let edges = Array(graph.edges.filter { ids.contains($0.source) && ids.contains($0.target) }.prefix(maxEdges))
        let labelIDs = Set(nodes.sorted { $0.degree > $1.degree }.prefix(maxLabels).map { $0.id })
        // Only the most-connected nodes ("congestion hubs") get the expensive glowing halo —
        // that both marks high-connectivity nodes AND keeps the frame cheap.
        let hubIDs = Set(nodes.filter { $0.degree >= 2 }.sorted { $0.degree > $1.degree }.prefix(40).map { $0.id })
        let focus = selectedNodeID
        let neighbors = Self.neighborIDs(of: focus, in: edges)

        ZStack {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    graphCanvas(time: tl.date.timeIntervalSinceReferenceDate,
                                nodes: nodes, byID: byID, edges: edges,
                                labelIDs: labelIDs, hubIDs: hubIDs, focus: focus, neighbors: neighbors)
                }
            } else {
                graphCanvas(time: 0, nodes: nodes, byID: byID, edges: edges,
                            labelIDs: labelIDs, hubIDs: hubIDs, focus: focus, neighbors: neighbors)
            }
            tapTargets(nodes: nodes)
        }
        .overlay(alignment: .topLeading) { modeToggle }
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .background(ScrollZoomInstaller { factor in setZoom(scale * factor) })
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { g in
                    if sphere {
                        rotY = lastRotY + Double(g.translation.width) * 0.01
                        rotX = min(max(lastRotX - Double(g.translation.height) * 0.01, -1.4), 1.4)
                    } else {
                        offset = CGSize(width: lastOffset.width + g.translation.width,
                                        height: lastOffset.height + g.translation.height)
                    }
                }
                .onEnded { _ in lastRotX = rotX; lastRotY = rotY; lastOffset = offset }
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
            sphere3D = Self.layout3D(nodes: nodes)
        }
    }

    /// Sphere ⇄ flat toggle, tucked in the corner.
    private var modeToggle: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { sphere.toggle() } } label: {
            Image(systemName: sphere ? "globe" : "square.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryOnMaterial)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(Space.m)
        .help(sphere ? "Flat" : "Sphere")
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
            rotX = 0.5; lastRotX = 0.5; rotY = 0; lastRotY = 0
        }
    }

    /// Zoom in/out buttons (for a mouse — pinch also works on a trackpad).
    private var zoomControls: some View {
        VStack(spacing: 6) {
            zoomButton("plus") { setZoom(scale * 1.3, animated: true) }
            zoomButton("minus") { setZoom(scale / 1.3, animated: true) }
        }
        .padding(Space.m)
    }
    private func zoomButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryOnMaterial)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
    private func setZoom(_ s: CGFloat, animated: Bool = false) {
        let clamped = min(max(s, 0.4), 6)
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { scale = clamped; lastScale = clamped }
        } else {
            scale = clamped; lastScale = clamped   // scroll: immediate, no animation stacking
        }
    }

    // MARK: Projection — screen position + depth (0 back … 1 front) per node.

    private func frames(nodes: [CodeGraph.Node], in size: CGSize, time: Double)
        -> (pos: [String: CGPoint], depth: [String: Double]) {
        var pos: [String: CGPoint] = [:]
        var depth: [String: Double] = [:]
        pos.reserveCapacity(nodes.count); depth.reserveCapacity(nodes.count)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        if sphere {
            let R = min(size.width, size.height) * 0.42 * scale
            for node in nodes {
                guard let p = sphere3D[node.id] else { continue }
                let r = Self.rot3(p, ax: rotX, ay: rotY)
                let persp = 1.7 / (1.7 - r.z)
                pos[node.id] = CGPoint(x: center.x + CGFloat(r.x * persp) * R,
                                       y: center.y + CGFloat(r.y * persp) * R)
                depth[node.id] = (r.z + 1) / 2
            }
        } else {
            let base = Self.fit(norm.isEmpty ? Self.layout(nodes: nodes) : norm, in: size)
            let sway: CGFloat = time == 0 ? 0 : 3.0
            for (i, node) in nodes.enumerated() {
                guard let bp = base[node.id] else { continue }
                let t = transform(bp, in: size)
                pos[node.id] = CGPoint(x: t.x + CGFloat(sin(time * 0.55 + Double(i) * 1.3)) * sway,
                                       y: t.y + CGFloat(cos(time * 0.5 + Double(i) * 0.9)) * sway)
                depth[node.id] = 1
            }
        }
        return (pos, depth)
    }

    // MARK: One frame

    private func graphCanvas(time: Double, nodes: [CodeGraph.Node], byID: [String: CodeGraph.Node],
                             edges: [CodeGraph.Edge], labelIDs: Set<String>, hubIDs: Set<String>,
                             focus: String?, neighbors: Set<String>) -> some View {
        Canvas { ctx, size in
            let (pos, depth) = frames(nodes: nodes, in: size, time: time)
            let dimming = focus != nil || matchIDs != nil
            let glowPulse = time == 0 ? 1.0 : (0.82 + 0.18 * sin(time * 0.5))

            drawClusterGlows(nodes: nodes, frames: pos, dimmed: dimming, pulse: glowPulse, ctx: &ctx)

            func edgeAlpha(_ e: CodeGraph.Edge, _ a: Double) -> Double {
                let d = ((depth[e.source] ?? 1) + (depth[e.target] ?? 1)) / 2
                return a * (0.35 + 0.65 * d)   // far edges recede
            }
            if focus == nil {
                for e in edges {
                    let cross = byID[e.source]?.community != byID[e.target]?.community
                    let c = cross ? Theme.coral : color(byID[e.source]?.community ?? 0)
                    curve(e, frames: pos, color: c.opacity(edgeAlpha(e, cross ? 0.10 : 0.09)),
                          width: cross ? 0.7 : 0.6, ctx: &ctx)
                }
                if time > 0 {
                    var count = 0
                    for e in edges where byID[e.source]?.community != byID[e.target]?.community {
                        drawParticles(e, frames: pos, time: time, ctx: &ctx, faint: true)
                        count += 1
                        if count >= 22 { break }
                    }
                }
            } else {
                for e in edges where e.source != focus && e.target != focus {
                    curve(e, frames: pos, color: Color.gray.opacity(0.05), width: 0.5, ctx: &ctx)
                }
                for e in edges where e.source == focus || e.target == focus {
                    curve(e, frames: pos, color: Theme.coral.opacity(0.85), width: 1.6, ctx: &ctx)
                    if time > 0 { drawParticles(e, frames: pos, time: time, ctx: &ctx) }
                }
            }

            // Nodes back-to-front so the sphere's near face sits on top.
            let ordered = sphere ? nodes.sorted { (depth[$0.id] ?? 1) < (depth[$1.id] ?? 1) } : nodes
            for (i, node) in ordered.enumerated() {
                guard let p = pos[node.id] else { continue }
                let breathe = time == 0 ? 1.0 : (1.0 + 0.06 * sin(time * 1.1 + Double(i) * 0.7))
                let d = depth[node.id] ?? 1
                // Size encodes DEGREE (connections). Depth only nudges it a little on the
                // sphere (front slightly bigger) — it must not out-shout the degree signal.
                let sizeMul: CGFloat = sphere ? CGFloat(0.78 + 0.35 * d) : 1
                let alphaMul = sphere ? (0.45 + 0.55 * d) : 1
                drawNode(node, at: p, selected: node.id == focus,
                         dim: isDim(node, focus: focus, neighbors: neighbors), hub: hubIDs.contains(node.id),
                         breathe: breathe, sizeMul: sizeMul, alphaMul: alphaMul, ctx: &ctx)
            }

            for node in nodes {
                let show = focus == nil ? labelIDs.contains(node.id)
                                        : (node.id == focus || neighbors.contains(node.id))
                // On the sphere, only label the front face so the back doesn't clutter.
                guard show, sphere ? (depth[node.id] ?? 1) > 0.55 : true, let p = pos[node.id] else { continue }
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

    /// Apply zoom + pan around the canvas centre (flat mode).
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

    /// A straight synaptic edge — the neural-network look, and cheaper than a bezier.
    private func curve(_ e: CodeGraph.Edge, frames: [String: CGPoint], color: Color, width: CGFloat, ctx: inout GraphicsContext) {
        guard let a = frames[e.source], let b = frames[e.target] else { return }
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// A pulse of light travelling along a synapse (the selection's + a few ambient veins).
    private func drawParticles(_ e: CodeGraph.Edge, frames: [String: CGPoint], time: Double, ctx: inout GraphicsContext, faint: Bool = false) {
        guard let a = frames[e.source], let b = frames[e.target] else { return }
        let dots = faint ? 2 : 3
        for d in 0..<dots {
            let phase = Double(d) / Double(dots)
            let u = CGFloat((time * (faint ? 0.28 : 0.5) + phase).truncatingRemainder(dividingBy: 1.0))
            let fade = sin(Double(u) * .pi)
            guard fade > 0.03 else { continue }
            let p = CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            let r: CGFloat = faint ? 1.7 : 2.4
            let base = faint ? 0.08 : 0.35, span = faint ? 0.28 : 0.55
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Theme.coral.opacity(base + span * fade)))
        }
    }

    private func drawNode(_ node: CodeGraph.Node, at p: CGPoint, selected: Bool, dim: Bool, hub: Bool,
                          breathe: Double, sizeMul: CGFloat, alphaMul: Double, ctx: inout GraphicsContext) {
        let r = radius(node.degree) * scale * CGFloat(breathe) * sizeMul
        let tint = color(node.community)
        let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
        let fillA = (dim ? 0.30 : 0.85) * alphaMul
        // A NEURON, not a bubble: a soft coloured glow, a coloured body, and a bright core
        // that reads as a firing synapse. Cheap — solid discs only; the pricier radial-gradient
        // halo is reserved for the top hubs (capped), which doubles as the congestion marker.
        if hub && !dim {
            let hr = r + 3 + 3 * CGFloat(breathe)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - hr, y: p.y - hr, width: 2 * hr, height: 2 * hr)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.26 * alphaMul), .clear]),
                                           center: p, startRadius: r * 0.5, endRadius: hr))
        } else if !dim {
            // Cheap soft glow for the rest: one low-alpha disc (no gradient).
            let gr = r * 1.7
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr, width: 2 * gr, height: 2 * gr)),
                     with: .color(tint.opacity(0.10 * alphaMul)))
        }
        // Body.
        ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(fillA)))
        // Bright firing core.
        if !dim {
            let cr = r * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: 2 * cr, height: 2 * cr)),
                     with: .color(.white.opacity(0.75 * alphaMul)))
        }
        if selected {
            let ring = rect.insetBy(dx: -3.5, dy: -3.5)
            ctx.stroke(Path(ellipseIn: ring), with: .color(Theme.coral), lineWidth: 2)
        }
    }

    /// Node radius encodes DEGREE (number of connections) — leaves are small, hubs large,
    /// gently compressed so a super-hub doesn't dominate. This is the "congestion" signal.
    private func radius(_ degree: Int) -> CGFloat {
        min(max(2.2 + sqrt(Double(degree)) * 2.0, 2.2), 16)
    }

    private func drawText(_ ctx: inout GraphicsContext, _ text: Text, at point: CGPoint, color: Color) {
        var resolved = ctx.resolve(text)
        resolved.shading = .color(color)
        ctx.draw(resolved, at: point, anchor: .center)
    }

    private static func neighborIDs(of focus: String?, in edges: [CodeGraph.Edge]) -> Set<String> {
        guard let f = focus else { return [] }
        var n = Set<String>()
        for e in edges {
            if e.source == f { n.insert(e.target) }
            if e.target == f { n.insert(e.source) }
        }
        return n
    }

    // MARK: Tap targets (use the same projection so hits line up)

    @ViewBuilder
    private func tapTargets(nodes: [CodeGraph.Node]) -> some View {
        GeometryReader { geo in
            let (pos, depth) = frames(nodes: nodes, in: geo.size, time: 0)
            ForEach(nodes) { node in
                if let p = pos[node.id] {
                    let front = !sphere || (depth[node.id] ?? 1) > 0.45
                    let hit = max(radius(node.degree) * scale + 5, 11)
                    Circle()
                        .fill(.clear)
                        .contentShape(Circle())
                        .frame(width: hit * 2, height: hit * 2)
                        .position(p)
                        .allowsHitTesting(front)
                        .onTapGesture { selectedNodeID = (selectedNodeID == node.id) ? nil : node.id }
                        .help(node.label)
                }
            }
        }
    }

    // MARK: Layout — flat lobes

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

    // MARK: Layout — 3D sphere (clusters as patches on a globe)

    private static func layout3D(nodes: [CodeGraph.Node]) -> [String: V3] {
        var groups: [Int: [CodeGraph.Node]] = [:]
        for n in nodes { groups[n.community, default: []].append(n) }
        let communities = groups.keys.sorted { (groups[$0]?.count ?? 0) > (groups[$1]?.count ?? 0) }
        let C = communities.count
        if C == 0 { return [:] }
        let golden = 2.399963229728653
        let ga = Double.pi * (3 - 5.0.squareRoot())

        var out: [String: V3] = [:]
        for i in 0..<C {
            let members = groups[communities[i]]!.sorted { $0.degree > $1.degree }
            let n = members.count
            // Cluster centroid: a Fibonacci-sphere direction (unit vector).
            let cy = 1 - 2 * (Double(i) + 0.5) / Double(C)
            let cr = (max(0, 1 - cy * cy)).squareRoot()
            let cth = ga * Double(i)
            let c = V3(x: cos(cth) * cr, y: cy, z: sin(cth) * cr)
            // Tangent basis at the centroid.
            let up: V3 = abs(c.y) > 0.99 ? V3(x: 1, y: 0, z: 0) : V3(x: 0, y: 1, z: 0)
            let t1 = normalize(cross(c, up))
            let t2 = cross(c, t1)
            let patch = min(0.28 + 0.06 * sqrt(Double(n)), 0.8)   // angular radius of the patch
            for (k, node) in members.enumerated() {
                if k == 0 { out[node.id] = c; continue }
                let ang = Double(k) * golden
                let rad = patch * sqrt(Double(k) / Double(max(n - 1, 1)))
                // A tangent direction, then rotate the centroid toward it by `rad` (stays on the sphere).
                let dir = V3(x: t1.x * cos(ang) + t2.x * sin(ang),
                             y: t1.y * cos(ang) + t2.y * sin(ang),
                             z: t1.z * cos(ang) + t2.z * sin(ang))
                out[node.id] = V3(x: c.x * cos(rad) + dir.x * sin(rad),
                                  y: c.y * cos(rad) + dir.y * sin(rad),
                                  z: c.z * cos(rad) + dir.z * sin(rad))
            }
        }
        return out
    }

    /// Rotate a 3D point around Y then X (same convention as the brand spinner).
    private static func rot3(_ p: V3, ax: Double, ay: Double) -> V3 {
        let cy = cos(ay), sy = sin(ay)
        let x = p.x * cy + p.z * sy
        let z1 = -p.x * sy + p.z * cy
        let cx = cos(ax), sx = sin(ax)
        let y = p.y * cx - z1 * sx
        let z = p.y * sx + z1 * cx
        return V3(x: x, y: y, z: z)
    }

    private static func cross(_ a: V3, _ b: V3) -> V3 {
        V3(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
    }
    private static func normalize(_ v: V3) -> V3 {
        let len = max((v.x * v.x + v.y * v.y + v.z * v.z).squareRoot(), 1e-9)
        return V3(x: v.x / len, y: v.y / len, z: v.z / len)
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
