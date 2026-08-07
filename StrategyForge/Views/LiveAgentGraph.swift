//
//  LiveAgentGraph.swift
//  StrategyForge
//
//  A live, "engine at work" visualization of a running team: the orchestrator is a
//  glowing coral core, subagents are nodes on a ring around it. As a role starts
//  (fan-out) a lit edge streams particles core→node; while it works the node breathes;
//  when it finishes (fan-in) a return burst flows node→core and the node settles. The
//  core's intensity tracks how many agents run *right now* — the parallel "pulse".
//
//  Performance budget on purpose: ONE TimelineView (paused when idle → fully static),
//  ONE Canvas, deterministic layout, particle counts capped and scaled to the node
//  count (never a literal 1,000). Reduce-Motion drops all flow to a static state graph.
//
//  It's driven by a plain `LiveGraphSnapshot` value — so it's honest: in a real run the
//  snapshot maps 1:1 from `ChatViewModel` (rolesInProgress / roleTasks / roleStartedAt /
//  tokens); in the Lab a scripted simulation feeds the exact same shape.
//

import SwiftUI

// MARK: - Snapshot model (the honest seam)

enum LiveNodeState: Equatable { case idle, running, done, failed }

struct LiveGraphNode: Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String?          // the orchestrator's assigned task (shown while running)
    var model: String?             // short model/provider label, shown under the node
    var state: LiveNodeState = .idle
    var tint: Color = Theme.accent // provider tint
    var startedAt: Date?
    var endedAt: Date?
}

struct LiveGraphSnapshot: Equatable {
    var orchestratorTitle: String = "Orchestrator"
    var nodes: [LiveGraphNode] = []
    var phase: String = ""         // terminal-strip status ("SYNTHESIZING…")
    var tokens: Int = 0
    var elapsed: TimeInterval = 0
    var running: Bool = false

    var activeCount: Int { nodes.reduce(0) { $0 + ($1.state == .running ? 1 : 0) } }
    var doneCount: Int { nodes.reduce(0) { $0 + ($1.state == .done ? 1 : 0) } }
}

// MARK: - The view

struct LiveAgentGraphView: View {
    let snapshot: LiveGraphSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let reef = Color(red: 0.070, green: 0.094, blue: 0.110)

    var body: some View {
        ZStack {
            // Canvas carries the graph; a light SwiftUI strip carries the crisp mono HUD.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !snapshot.running && !reduceMotion)) { tl in
                let clock = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    draw(&ctx, size, clock)
                }
            }
            .background(Self.reef)
            statusStrip
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(a11ySummary)
    }

    // MARK: Layout

    private func center(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.54) }
    private func layoutRadius(_ size: CGSize) -> CGFloat { min(size.width, size.height) * 0.34 }

    /// Deterministic node position: evenly spaced on a circle, starting at the top and
    /// going clockwise. A single node sits to the right so the edge reads horizontally.
    private func position(_ i: Int, _ n: Int, _ size: CGSize) -> CGPoint {
        let c = center(size), R = layoutRadius(size)
        guard n > 1 else { return CGPoint(x: c.x + R, y: c.y) }
        let a = -.pi / 2 + (2 * .pi) * Double(i) / Double(n)
        return CGPoint(x: c.x + R * CGFloat(cos(a)), y: c.y + R * CGFloat(sin(a)))
    }

    // MARK: Draw

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ clock: Double) {
        let c = center(size)
        let n = snapshot.nodes.count
        let flow = !reduceMotion

        // Stage atmosphere: a faint ADDITIVE coral glow pooled at the core so the dark
        // viewport reads as deep water with light in it, not flat black.
        var wash = ctx; wash.blendMode = .plusLighter
        wash.fill(Path(CGRect(origin: .zero, size: size)),
                  with: .radialGradient(Gradient(colors: [Theme.coral.opacity(0.07), .clear]),
                                        center: c, startRadius: 0, endRadius: max(size.width, size.height) * 0.55))

        // Edges first (behind nodes).
        for (i, node) in snapshot.nodes.enumerated() {
            drawEdge(&ctx, from: c, to: position(i, n, size), node: node, clock: clock, flow: flow)
        }
        // Orchestrator core.
        drawCore(&ctx, at: c, clock: clock, flow: flow)
        // Nodes on top.
        for (i, node) in snapshot.nodes.enumerated() {
            drawNode(&ctx, at: position(i, n, size), node: node, clock: clock, flow: flow)
        }
    }

    private func drawEdge(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint,
                          node: LiveGraphNode, clock: Double, flow: Bool) {
        // Base line — brightness by state.
        let baseOp: Double = switch node.state {
        case .running: 0.26
        case .done: 0.12
        case .failed: 0.14
        case .idle: 0.06
        }
        var line = Path(); line.move(to: a); line.addLine(to: b)
        ctx.stroke(line, with: .color(Theme.accent.opacity(baseOp)), lineWidth: 1)

        guard flow else { return }

        // Fan-OUT: while running, particles stream core → node.
        if node.state == .running {
            let dots = 5
            for j in 0..<dots {
                let frac = (clock * 0.55 + Double(j) / Double(dots)).truncatingRemainder(dividingBy: 1)
                let p = lerp(a, b, frac)
                let fade = sin(.pi * frac)
                dot(&ctx, p, r: 1.4 + 1.0 * fade, color: node.tint, op: 0.85 * fade)
            }
        }
        // Fan-IN: brief return burst node → core right after it finishes.
        if node.state == .done, let end = node.endedAt {
            let age = clock - end.timeIntervalSinceReferenceDate
            if age >= 0, age < 1.1 {
                let dots = 4
                for j in 0..<dots {
                    let frac = min((age / 1.1) + Double(j) / Double(dots) * 0.25, 1)
                    let p = lerp(b, a, frac)
                    dot(&ctx, p, r: 1.6, color: Theme.teal, op: (1 - age / 1.1) * 0.8)
                }
            }
        }
    }

    private func drawCore(_ ctx: inout GraphicsContext, at c: CGPoint, clock: Double, flow: Bool) {
        let active = Double(snapshot.activeCount)
        let breathe = flow ? 1 + 0.05 * sin(clock * 2.0) : 1
        let R0 = (18 + active * 3) * breathe
        let intensity = min(0.30 + active * 0.12, 0.74)

        // Outer bloom — ADDITIVE so it reads as emitted light, not a painted disc.
        var bloom = ctx; bloom.blendMode = .plusLighter
        bloom.fill(Path(ellipseIn: CGRect(x: c.x - R0 * 2.4, y: c.y - R0 * 2.4, width: R0 * 4.8, height: R0 * 4.8)),
                   with: .radialGradient(Gradient(colors: [Theme.coral.opacity(intensity), Theme.coral.opacity(0)]),
                                         center: c, startRadius: 0, endRadius: R0 * 2.4))
        // Orbiting swarm — a subtle additive coral mist (denser while agents run).
        if flow {
            var mist = ctx; mist.blendMode = .plusLighter
            let count = min(16 + snapshot.activeCount * 8, 48)
            let ga = 2.399963, rot = clock * 0.4
            for i in 0..<count {
                let t = Double(i) / Double(count)
                let rad = R0 * (0.55 + t * 1.1)
                let ang = ga * Double(i) + rot
                let p = CGPoint(x: c.x + CGFloat(cos(ang)) * rad, y: c.y + CGFloat(sin(ang)) * rad)
                dot(&mist, p, r: 1.2, color: Theme.coral, op: 0.14 + 0.26 * (1 - t))
            }
        }
        // Rim ring — a thin coral halo that thickens as more agents run (the "pulse").
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R0, y: c.y - R0, width: R0 * 2, height: R0 * 2)),
                   with: .color(Theme.coral.opacity(0.5)), lineWidth: 1.5 + active * 0.6)
        // The heart — a small disc with a slowly rotating coral→deep gradient (it visibly
        // "spins" while thinking) + a crisp specular so it reads as a lit gem, not a flat dot.
        let hr = 6.5 * breathe
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                 with: .conicGradient(Gradient(colors: [Theme.coral, Theme.coralDeep, Theme.coral]),
                                      center: c, angle: Angle(radians: flow ? clock * 0.5 : 0)))
        var spec = ctx; spec.blendMode = .plusLighter
        let sr = hr * 0.28
        spec.fill(Path(ellipseIn: CGRect(x: c.x - hr * 0.32 - sr, y: c.y - hr * 0.32 - sr, width: sr * 2, height: sr * 2)),
                  with: .color(.white.opacity(0.85)))
        // Orchestrator label.
        ctx.draw(Text(snapshot.orchestratorTitle.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.coral.opacity(0.9)),
                 at: CGPoint(x: c.x, y: c.y + R0 + 14))
    }

    private func drawNode(_ ctx: inout GraphicsContext, at p: CGPoint, node: LiveGraphNode,
                          clock: Double, flow: Bool) {
        let running = node.state == .running
        let breathe = (flow && running) ? 1 + 0.12 * sin(clock * 3.2 + p.x) : 1
        let r = (running ? 8.0 : 6.0) * breathe

        // Halo while running.
        if running {
            let hr = r * 2.6
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - hr, y: p.y - hr, width: hr * 2, height: hr * 2)),
                     with: .radialGradient(Gradient(colors: [node.tint.opacity(0.28), node.tint.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: hr))
        }
        // Body.
        let body: Color = switch node.state {
        case .running: node.tint
        case .done: Theme.success
        case .failed: Theme.danger
        case .idle: Self.reef
        }
        let bodyOp: Double = switch node.state {
        case .running: 1.0
        case .done: 0.72
        case .failed: 0.9
        case .idle: 1.0
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(body.opacity(bodyOp)))
        // Ring: idle nodes get a faint outline so they read as "waiting", not absent.
        let ring: Color = node.state == .idle ? Theme.accent.opacity(0.35) : body
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(ring), lineWidth: 1)

        // Title always; then the model (video-style provider label); then the live task for the
        // active node only (avoids clutter).
        ctx.draw(Text(node.title)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.ink.opacity(0.85)),
                 at: CGPoint(x: p.x, y: p.y + r + 9))
        var below = p.y + r + 20
        if let m = node.model, !m.isEmpty {
            ctx.draw(Text(m.uppercased())
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .foregroundColor(node.tint.opacity(running ? 0.95 : 0.6)),
                     at: CGPoint(x: p.x, y: below))
            below += 10
        }
        if running, let sub = node.subtitle, !sub.isEmpty {
            ctx.draw(Text(sub)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary),
                     at: CGPoint(x: p.x, y: below))
        }
    }

    // MARK: HUD

    private var statusStrip: some View {
        VStack {
            HStack(spacing: Space.s) {
                Circle().fill(snapshot.running ? Theme.accent : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(snapshot.phase.isEmpty ? "IDLE" : snapshot.phase.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                // The currently-routed model(s) — the video's "ROUTE → …" read.
                if let route = activeRoute {
                    Text("→ \(route)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(hud)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(.ultraThinMaterial)
            Spacer()
        }
    }

    private var hud: String {
        let mins = Int(snapshot.elapsed) / 60, secs = Int(snapshot.elapsed) % 60
        let k = snapshot.tokens >= 1000 ? String(format: "%.1fk", Double(snapshot.tokens) / 1000) : "\(snapshot.tokens)"
        return String(format: "AGENTS %d · TOKENS %@ · %02d:%02d", snapshot.activeCount, k, mins, secs)
    }

    /// The model(s) currently doing the work — for the "→ model" route in the HUD. Distinct
    /// model names of the running nodes (deduped), or nil when none are active.
    private var activeRoute: String? {
        let models = snapshot.nodes.filter { $0.state == .running }.compactMap { $0.model }
        guard !models.isEmpty else { return nil }
        var seen = Set<String>(); let uniq = models.filter { seen.insert($0).inserted }
        return uniq.prefix(2).joined(separator: ", ") + (uniq.count > 2 ? "…" : "")
    }

    private var a11ySummary: String {
        "\(snapshot.activeCount) agents running, \(snapshot.doneCount) done. \(snapshot.phase)"
    }

    // MARK: Primitives

    private func dot(_ ctx: inout GraphicsContext, _ p: CGPoint, r: CGFloat, color: Color, op: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                 with: .color(color.opacity(op)))
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

// MARK: - Labs candidate (scripted simulation → same snapshot shape a live run feeds)

struct LiveGraphLabSection: View {
    @State private var snapshot = LiveGraphSnapshot(
        orchestratorTitle: "Orchestrator",
        nodes: LiveGraphLabSection.seed,
        phase: "", running: false)
    @State private var runToken = 0

    private static let seed: [LiveGraphNode] = [
        LiveGraphNode(id: "backend",  title: "backend",  model: "Opus 4.8", tint: Theme.accent),
        LiveGraphNode(id: "frontend", title: "frontend", model: "GPT-5.2", tint: Color(red: 0.26, green: 0.52, blue: 0.96)),
        LiveGraphNode(id: "tests",    title: "tests",    model: "Sonnet 5", tint: Color(red: 0.10, green: 0.72, blue: 0.60)),
        LiveGraphNode(id: "security", title: "security", model: "Gemini 3 Pro", tint: Theme.accent),
        LiveGraphNode(id: "docs",     title: "docs",     model: "Haiku 4.5", tint: Color(red: 0.55, green: 0.35, blue: 0.80)),
        LiveGraphNode(id: "reviewer", title: "reviewer", model: "Grok 4.5", tint: Color(red: 0.10, green: 0.72, blue: 0.60)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live agent graph").font(.sfDisplay)
                Text("The team executing in real time — orchestrator core, subagents lighting up as they run (fan-out), returning as they finish (fan-in). One TimelineView + one Canvas; paused when idle. Tap Run.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LiveAgentGraphView(snapshot: snapshot)
                .frame(height: 360)
                .frame(maxWidth: 560)
            Button("Run", action: { runToken += 1 }).buttonStyle(.moon).controlSize(.small)
        }
        .task(id: runToken) { if runToken > 0 { await simulate() } }
    }

    /// Walk a plausible run, mutating the snapshot exactly as ChatViewModel would:
    /// plan → workers ignite staggered → finish staggered → reviewer verifies → synthesize.
    private func simulate() async {
        func reset() {
            snapshot.nodes = Self.seed
            snapshot.tokens = 0; snapshot.elapsed = 0; snapshot.running = true
        }
        func idx(_ id: String) -> Int? { snapshot.nodes.firstIndex { $0.id == id } }
        func set(_ id: String, _ s: LiveNodeState) {
            guard let i = idx(id) else { return }
            snapshot.nodes[i].state = s
            if s == .running { snapshot.nodes[i].startedAt = Date() }
            if s == .done || s == .failed { snapshot.nodes[i].endedAt = Date() }
        }
        // A background token/elapsed ticker for the HUD.
        let ticker = Task { @MainActor in
            while snapshot.running {
                try? await Task.sleep(for: .milliseconds(200))
                snapshot.tokens += Int.random(in: 400...1400)
                snapshot.elapsed += 0.2
            }
        }
        defer { ticker.cancel() }

        reset()
        snapshot.phase = "planning"
        try? await Task.sleep(for: .milliseconds(900))

        // Fan-out: workers ignite one after another.
        snapshot.phase = "delegating"
        let workers = ["backend", "frontend", "tests", "security", "docs"]
        for w in workers {
            set(w, .running)
            try? await Task.sleep(for: .milliseconds(320))
        }
        snapshot.phase = "working"

        // Finish staggered (each after its own little while).
        for w in workers.shuffled() {
            try? await Task.sleep(for: .milliseconds(.random(in: 500...1100)))
            set(w, .done)
        }

        // Verify: the reviewer runs read-only over the results.
        snapshot.phase = "verifying"
        set("reviewer", .running)
        try? await Task.sleep(for: .milliseconds(1200))
        set("reviewer", .done)

        // Synthesize: the core flares as the orchestrator combines.
        snapshot.phase = "synthesizing"
        try? await Task.sleep(for: .milliseconds(1000))

        snapshot.phase = "done"
        snapshot.running = false
    }
}

#Preview("Live graph — mid-run") {
    LiveAgentGraphView(snapshot: LiveGraphSnapshot(
        orchestratorTitle: "Orchestrator",
        nodes: [
            LiveGraphNode(id: "backend", title: "backend", subtitle: "auditing routes", model: "Opus 4.8", state: .running, tint: Theme.accent, startedAt: Date()),
            LiveGraphNode(id: "frontend", title: "frontend", model: "GPT-5.2", state: .done, tint: Color(red: 0.26, green: 0.52, blue: 0.96), endedAt: Date()),
            LiveGraphNode(id: "tests", title: "tests", subtitle: "running suite", model: "Sonnet 5", state: .running, tint: Color(red: 0.10, green: 0.72, blue: 0.60), startedAt: Date()),
            LiveGraphNode(id: "security", title: "security", model: "Gemini 3 Pro", state: .idle, tint: Theme.accent),
            LiveGraphNode(id: "docs", title: "docs", model: "Haiku 4.5", state: .done, tint: Color(red: 0.55, green: 0.35, blue: 0.80), endedAt: Date()),
            LiveGraphNode(id: "reviewer", title: "reviewer", model: "Grok 4.5", state: .idle, tint: Color(red: 0.10, green: 0.72, blue: 0.60)),
        ],
        phase: "working", tokens: 48200, elapsed: 74, running: true))
    .frame(width: 560, height: 360)
    .padding()
}
