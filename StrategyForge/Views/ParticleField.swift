//
//  ParticleField.swift
//  StrategyForge
//
//  The app's motion identity: a quiet dot/particle system (inspired by
//  getthinkable.com) used for spinners, waiting/empty states, and ambient accents.
//  Pure SwiftUI Canvas + TimelineView (no SpriteKit — too heavy for a spinner). One
//  coherent language: a field of small dots with a soft coral glow that travels.
//  Honors accessibilityReduceMotion (falls back to a still frame).
//

import SwiftUI

/// A compact dot-ring spinner: 12 dots on a circle with a coral glow wave rotating
/// around them. The app's standard "working / waiting" indicator.
struct DotSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var dots: Int = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let radius = min(sz.width, sz.height) / 2 - sz.width * 0.13
                let base = max(1.3, sz.width * 0.085)
                let phase = (t * 1.15).truncatingRemainder(dividingBy: 1.0)
                for i in 0..<dots {
                    let frac = Double(i) / Double(dots)
                    let ang = frac * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + cos(ang) * radius, y: c.y + sin(ang) * radius)
                    // Circular distance of this dot from the travelling glow (0…0.5).
                    let d = abs(frac - phase)
                    let near = min(d, 1 - d)
                    let intensity = pow(max(0, 1 - near * 3.2), 2)   // sharp coral pulse
                    // Resting dot.
                    ctx.fill(dot(p, base),
                             with: .color(color.opacity(0.20 + 0.12 * intensity)))
                    // Glow + bright core for the ones the wave is passing.
                    if intensity > 0.04 {
                        let g = base * (1 + 2.4 * intensity)
                        ctx.fill(dot(p, g), with: .color(color.opacity(0.16 * intensity)))
                        ctx.fill(dot(p, base), with: .color(color.opacity(0.45 + 0.55 * intensity)))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func dot(_ p: CGPoint, _ d: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
}

/// A calm scattered dot field for large empty/ambient states: dots on a disc, a
/// slow coral glow wandering across a few of them. Deterministic (seeded), so it's
/// stable across redraws and testable-looking.
struct ParticleField: View {
    var color: Color = Theme.accent
    var density: Int = 90
    var reactive: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let R = min(sz.width, sz.height) / 2 - 6
                // Two slow glow centres wandering around the disc.
                let g1 = CGPoint(x: c.x + cos(t * 0.23) * R * 0.55,
                                 y: c.y + sin(t * 0.19) * R * 0.55)
                let g2 = CGPoint(x: c.x + cos(t * 0.17 + 2.1) * R * 0.5,
                                 y: c.y + sin(t * 0.27 + 1.3) * R * 0.5)
                for i in 0..<density {
                    // Deterministic golden-angle spiral placement (no RNG).
                    let f = Double(i) / Double(density)
                    let rr = R * CGFloat(sqrt(f))
                    let aa = Double(i) * 2.399963  // golden angle
                    let p = CGPoint(x: c.x + cos(aa) * rr, y: c.y + sin(aa) * rr)
                    let size = CGFloat(1.2 + 1.6 * ((Double(i) * 0.61803).truncatingRemainder(dividingBy: 1)))
                    // Nearness to a glow centre → coral highlight.
                    let near = min(hypot(p.x - g1.x, p.y - g1.y), hypot(p.x - g2.x, p.y - g2.y))
                    let lit = reactive ? pow(max(0, 1 - near / (R * 0.32)), 2.2) : 0
                    ctx.fill(dot(p, size + CGFloat(lit) * 2),
                             with: .color(color.opacity(0.14 + 0.55 * lit)))
                    if lit > 0.15 {
                        let g = (size + 3) * CGFloat(1 + lit * 2)
                        ctx.fill(dot(p, g), with: .color(color.opacity(0.14 * lit)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(_ p: CGPoint, _ d: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }
}

// MARK: - Shared drawing helpers

/// A filled dot of the given *diameter* centred on `p`.
private func pfDot(_ p: CGPoint, _ d: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
}

/// A 4-point sparkle (concave star) of outer radius `r`, centred on `c`.
private func pfSparkle(_ c: CGPoint, _ r: CGFloat, rotation: CGFloat = 0) -> Path {
    var p = Path()
    let inner = r * 0.32
    for i in 0..<8 {
        let ang = rotation + CGFloat(i) * (.pi / 4) - .pi / 2
        let rad = i.isMultiple(of: 2) ? r : inner
        let pt = CGPoint(x: c.x + cos(ang) * rad, y: c.y + sin(ang) * rad)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// MARK: - Sparkle spinner

/// A ring of 4-point sparkles that twinkle in and out at staggered phases — the
/// most literal "sparkles" take on the waiting state (getthinkable-style).
struct SparkleSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var count: Int = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let ring = min(sz.width, sz.height) / 2 - sz.width * 0.18
                for i in 0..<count {
                    let f = Double(i) / Double(count)
                    let ang = f * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + cos(ang) * ring, y: c.y + sin(ang) * ring)
                    let ph = reduceMotion ? 0.6 : (t * 0.9 + Double(i) * 0.63).truncatingRemainder(dividingBy: 1)
                    let tw = pow(max(0, sin(ph * .pi)), 1.6)   // 0…1 twinkle
                    let r = sz.width * 0.13 * (0.35 + 0.65 * tw)
                    ctx.fill(pfSparkle(p, r, rotation: CGFloat(t) * 0.6),
                             with: .color(color.opacity(0.25 + 0.75 * tw)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Orbit spinner

/// Three dots orbiting the centre on nested rings at different speeds.
struct OrbitSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let maxR = min(sz.width, sz.height) / 2 - sz.width * 0.12
                let dot = max(1.6, sz.width * 0.11)
                for i in 0..<3 {
                    let rr = maxR * (0.5 + 0.25 * Double(i))
                    let speed = 1.3 - 0.25 * Double(i)
                    let ang = t * speed + Double(i) * 2.09
                    let p = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr)
                    ctx.fill(pfDot(p, dot * 2.6), with: .color(color.opacity(0.14)))
                    ctx.fill(pfDot(p, dot), with: .color(color.opacity(0.9)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Pulse dots (typing-style, dot flavour)

/// A short row of dots that swell in a travelling wave — the classic "thinking"
/// indicator rendered in the app's dot language.
struct PulseDotsSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var count: Int = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let cy = sz.height / 2
                let dot = max(2, sz.height * 0.22)
                let gap = dot * 1.9
                let total = gap * Double(count - 1)
                let startX = sz.width / 2 - total / 2
                for i in 0..<count {
                    let ph = reduceMotion ? 0.5 : (sin(t * 3 - Double(i) * 0.6) * 0.5 + 0.5)
                    let d = dot * (0.6 + 0.7 * ph)
                    let p = CGPoint(x: startX + gap * Double(i), y: cy)
                    ctx.fill(pfDot(p, d), with: .color(color.opacity(0.35 + 0.65 * ph)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Bloom spinner

/// Rings of dots blooming outward from the centre and fading — a soft coral pulse.
struct BloomSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var petals: Int = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let maxR = min(sz.width, sz.height) / 2 - sz.width * 0.08
                let dot = max(1.4, sz.width * 0.08)
                let waves = 2
                for w in 0..<waves {
                    let u = reduceMotion ? 0.5
                        : (t * 0.6 + Double(w) / Double(waves)).truncatingRemainder(dividingBy: 1)
                    let rr = maxR * u
                    let fade = sin(u * .pi)
                    for i in 0..<petals {
                        let ang = Double(i) / Double(petals) * 2 * .pi + t * 0.3
                        let p = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr)
                        ctx.fill(pfDot(p, dot), with: .color(color.opacity(0.7 * fade)))
                    }
                }
                ctx.fill(pfDot(c, dot * 1.2), with: .color(color.opacity(0.9)))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Comet spinner

/// A bright dot circling a ring, trailing a fading tail of dots.
struct CometSpinner: View {
    var size: CGFloat = 20
    var color: Color = Theme.accent
    var trail: Int = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let ring = min(sz.width, sz.height) / 2 - sz.width * 0.14
                let head = t * 1.6
                for i in 0..<trail {
                    let k = Double(i) / Double(trail)
                    let ang = head - k * 1.3
                    let p = CGPoint(x: c.x + cos(ang) * ring, y: c.y + sin(ang) * ring)
                    let d = max(1, sz.width * 0.11) * (1 - 0.7 * k)
                    ctx.fill(pfDot(p, d), with: .color(color.opacity((1 - k) * 0.9)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 3D particle spinners

/// A point in 3D (normalized to roughly the unit cube).
private struct P3 { var x, y, z: Double }

/// A small rotating 3D figure rendered as depth-shaded dots — the "particles that
/// form a 3D figure" spinner. Points are rotated around two axes over time, given a
/// simple perspective projection, and drawn back-to-front so nearer dots are larger
/// and brighter. Pick a `Figure`; all share one renderer.
struct Particle3DSpinner: View {
    enum Figure: String, CaseIterable, Identifiable {
        case sphere, cube, helix, torus, ring
        var id: String { rawValue }
    }
    var size: CGFloat = 40
    var color: Color = Theme.accent
    var figure: Figure = .sphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let pts = Self.points(figure)
                let ax = 0.5 + t * 0.55        // tilt + spin
                let ay = t * 0.95
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let R = min(sz.width, sz.height) * 0.40
                let base = max(1.2, sz.width * 0.05)
                // Rotate + project, then paint back-to-front for depth.
                let projected = pts.map { p -> (CGPoint, Double) in
                    let r = Self.rotate(p, ax: ax, ay: ay)
                    let persp = 1.7 / (1.7 - r.z)                  // nearer → larger
                    let sp = CGPoint(x: c.x + CGFloat(r.x * persp) * R,
                                     y: c.y + CGFloat(r.y * persp) * R)
                    return (sp, r.z)
                }
                for (sp, z) in projected.sorted(by: { $0.1 < $1.1 }) {
                    let depth = (z + 1) / 2                        // 0 (back) … 1 (front)
                    let d = base * (0.55 + 0.9 * depth)
                    ctx.fill(pfDot(sp, d * 2.2), with: .color(color.opacity(0.10 * depth)))
                    ctx.fill(pfDot(sp, d), with: .color(color.opacity(0.28 + 0.62 * depth)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Rotate a point around the Y then X axes.
    private static func rotate(_ p: P3, ax: Double, ay: Double) -> P3 {
        let cy = cos(ay), sy = sin(ay)
        let x = p.x * cy + p.z * sy
        let z1 = -p.x * sy + p.z * cy
        let cx = cos(ax), sx = sin(ax)
        let y = p.y * cx - z1 * sx
        let z = p.y * sx + z1 * cx
        return P3(x: x, y: y, z: z)
    }

    /// Point clouds are size-independent, so compute each figure ONCE and reuse it
    /// every frame (this spinner is the app-wide waiting indicator — often several on
    /// screen at 30fps, so avoiding a per-frame rebuild matters).
    private static let cache: [Figure: [P3]] = {
        var d: [Figure: [P3]] = [:]
        for f in Figure.allCases { d[f] = computePoints(f) }
        return d
    }()
    private static func points(_ f: Figure) -> [P3] { cache[f] ?? [] }

    /// The point cloud for each figure, normalized to ~[-1, 1].
    private static func computePoints(_ f: Figure) -> [P3] {
        switch f {
        case .sphere:
            // Fibonacci sphere — evenly distributed dots on a globe. 48 reads the same
            // as 64 at the sizes we render but costs ~25% less per frame.
            let n = 48
            let ga = Double.pi * (3 - 5.0.squareRoot())
            return (0..<n).map { i in
                let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
                let r = (max(0, 1 - y * y)).squareRoot()
                let th = ga * Double(i)
                return P3(x: cos(th) * r, y: y, z: sin(th) * r)
            }
        case .cube:
            // 8 vertices + dots subdividing the 12 edges (wireframe of dots).
            let s = 0.72
            let v = [P3(x: -s, y: -s, z: -s), P3(x: s, y: -s, z: -s), P3(x: s, y: s, z: -s), P3(x: -s, y: s, z: -s),
                     P3(x: -s, y: -s, z: s), P3(x: s, y: -s, z: s), P3(x: s, y: s, z: s), P3(x: -s, y: s, z: s)]
            let edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
            var a: [P3] = []
            let steps = 4
            for (i, j) in edges {
                for k in 0...steps {
                    let u = Double(k) / Double(steps)
                    a.append(P3(x: v[i].x + (v[j].x - v[i].x) * u,
                                y: v[i].y + (v[j].y - v[i].y) * u,
                                z: v[i].z + (v[j].z - v[i].z) * u))
                }
            }
            return a
        case .helix:
            let n = 52, turns = 3.0
            return (0..<n).map { i in
                let u = Double(i) / Double(n)
                let ang = u * turns * 2 * .pi
                return P3(x: cos(ang) * 0.7, y: (u * 2 - 1) * 0.92, z: sin(ang) * 0.7)
            }
        case .torus:
            let nu = 10, nv = 8, rR = 0.62, rr = 0.28
            var a: [P3] = []
            for i in 0..<nu {
                for j in 0..<nv {
                    let u = Double(i) / Double(nu) * 2 * .pi
                    let v = Double(j) / Double(nv) * 2 * .pi
                    a.append(P3(x: (rR + rr * cos(v)) * cos(u),
                                y: rr * sin(v),
                                z: (rR + rr * cos(v)) * sin(u)))
                }
            }
            return a
        case .ring:
            // A tilted ring of dots — the simplest, calmest 3D figure.
            let n = 28
            return (0..<n).map { i in
                let ang = Double(i) / Double(n) * 2 * .pi
                return P3(x: cos(ang) * 0.9, y: 0, z: sin(ang) * 0.9)
            }
        }
    }
}

// MARK: - Wave dot grid

/// A grid of dots that stretch vertically in a diagonal travelling wave — at each
/// crest the dots elongate and merge into little bars, then relax back to dots. A
/// calm, hypnotic "processing" loop (inspired by the reference clip).
struct WaveDotGrid: View {
    var size: CGFloat = 40
    var color: Color = Theme.accent
    var cols: Int = 4
    var rows: Int = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let pad = sz.width * 0.14
                let cw = (sz.width - pad * 2) / CGFloat(cols)
                let ch = (sz.height - pad * 2) / CGFloat(rows)
                let base = min(cw, ch) * 0.34
                for r in 0..<rows {
                    for c in 0..<cols {
                        let cx = pad + (CGFloat(c) + 0.5) * cw
                        let cy = pad + (CGFloat(r) + 0.5) * ch
                        // Diagonal wave: later rows/cols lag, so the crest sweeps across.
                        let phase = t * 2.3 - (Double(r) * 0.5 + Double(c) * 0.85)
                        let amp = (sin(phase) + 1) / 2                     // 0…1
                        let h = base * 2 * (0.55 + 1.5 * amp)             // vertical stretch → merge at crest
                        let w = base * 2 * (0.9 + 0.15 * amp)
                        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2),
                                 with: .color(color.opacity(0.28 + 0.62 * amp)))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Coral "thinking" spinner (the brand mark, built from dots)

/// The app's signature "alive / thinking" indicator: the branching-coral logo drawn
/// as dots that GROW from the root out to the tips in a loop, with a gentle breath —
/// as if the mark is being built while the agent thinks.
struct CoralThinkingSpinner: View {
    var size: CGFloat = 40
    var color: Color = Theme.coral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Precomputed dots along the coral branches: (position 0…1, growth order 0…1).
    private static let dots: [(CGPoint, Double)] = buildDots()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            // Under Reduce Motion freeze the clock too — otherwise the "breath"
            // term below keeps pulsing at 30 fps (its siblings already do this).
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let base = max(1.2, sz.width * 0.05)
                // Growth cycles: sweep root→tips, hold, then fade + rebuild.
                let cycle = 2.6
                let phase = reduceMotion ? 1.0 : (t.truncatingRemainder(dividingBy: cycle)) / cycle
                let grow = reduceMotion ? 1.0 : min(1.0, phase * 1.55)   // full by ~2/3, then holds
                let fade = reduceMotion ? 1.0 : (phase > 0.86 ? max(0, 1 - (phase - 0.86) / 0.14) : 1)
                for (p01, order) in Self.dots {
                    let pos = CGPoint(x: p01.x * sz.width, y: p01.y * sz.height)
                    let d = grow - order
                    let lit = d < 0 ? 0 : min(1, d * 6)                  // soft leading edge
                    let breath = 0.82 + 0.18 * sin(t * 2 + order * 3)    // alive even when grown
                    let r = base * (0.45 + 0.7 * lit)
                    ctx.fill(pfDot(pos, r * 2.6), with: .color(color.opacity(0.12 * lit * fade)))
                    ctx.fill(pfDot(pos, r), with: .color(color.opacity((0.18 + 0.72 * lit) * breath * fade)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Sample dots along the coral mark's branches (root at the bottom), ordering them
    /// by depth so they light in sequence from the trunk out to the four tips.
    private static func buildDots() -> [(CGPoint, Double)] {
        // (startX,startY, ctrlX,ctrlY, endX,endY, depth) on a 0…100 canvas — matches CoralMark.
        let branches: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
            (50, 84, 50, 70, 50, 60, 0),
            (50, 60, 40, 52, 29, 40, 1),
            (29, 40, 24, 31, 21, 24, 2),
            (29, 40, 34, 31, 39, 25, 2),
            (50, 60, 60, 52, 71, 40, 1),
            (71, 40, 76, 31, 79, 24, 2),
            (71, 40, 66, 31, 61, 25, 2),
        ]
        func quad(_ a: CGFloat, _ c: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
            let mt = 1 - t; return mt * mt * a + 2 * mt * t * c + t * t * b
        }
        let k = 6
        var out: [(CGPoint, Double)] = []
        for br in branches {
            for i in 0..<k {
                let f = CGFloat(i) / CGFloat(k - 1)
                let x = quad(br.0, br.2, br.4, f) / 100
                let y = quad(br.1, br.3, br.5, f) / 100
                let order = (br.6 + Double(f)) / 3.0
                out.append((CGPoint(x: x, y: y), order))
            }
        }
        return out
    }
}

// MARK: - Particle Lab (a gallery of the motion system)

/// A gallery for previewing every spinner / waiting element and the ambient
/// particle field, at a few sizes and tints. Reached from a DEBUG-only nav entry.
struct ParticleLabView: View {
    @Environment(AppModel.self) private var model
    private let cols = [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: Space.l)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Particle Lab").font(.sfDisplay)
                    Text("Dot & sparkle motion system — spinners, waiting states and ambient identity.")
                        .font(.sfCallout).foregroundStyle(.secondary)
                }

                // Preview the first-run onboarding without reinstalling / clearing the
                // didOnboard flag — so the first-open experience can be reviewed here.
                HStack(spacing: Space.m) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("First-run onboarding").font(.sfCardTitle)
                        Text("See exactly what a new user sees the first time the app opens.")
                            .font(.sfCallout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview onboarding") { model.showOnboardingPreview = true }
                        .buttonStyle(.moon)
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.cardBg))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
                Divider()

                // Wow-moment candidates to choose from (rich, in motion).
                WowGalleryLabSection()
                Divider()

                // The Coral Assemble wow beat — replayable here.
                CoralAssembleLabSection()
                Divider()

                // Variations of the CURRENT mark (the preferred direction). Top billing.
                CoralMarkLabSection()
                Divider()

                // Logo & identity proposals (review-only).
                IdentityLabSection()
                Divider()

                // Sphere-logo variations (art-director workflow, review-only).
                SphereLogoLabSection()
                Divider()

                Text("Brand — thinking").font(.sfCardTitle)
                LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                    demo("CoralThinkingSpinner", "The coral mark builds from dots · alive") {
                        HStack(spacing: Space.l) {
                            CoralThinkingSpinner(size: 28)
                            CoralThinkingSpinner(size: 44)
                            CoralThinkingSpinner(size: 64)
                        }
                    }
                    demo("Teal / on dark", "Any tint") {
                        HStack(spacing: Space.l) {
                            CoralThinkingSpinner(size: 44, color: Theme.teal)
                            CoralThinkingSpinner(size: 44)
                        }
                    }
                }

                Text("3D particle figures").font(.sfCardTitle)
                LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                    demo("Sphere", "Fibonacci globe of dots") {
                        sizes { Particle3DSpinner(size: $0, figure: .sphere) }
                    }
                    demo("Cube", "Rotating wireframe of dots") {
                        sizes { Particle3DSpinner(size: $0, figure: .cube) }
                    }
                    demo("Helix", "Spinning dot helix") {
                        sizes { Particle3DSpinner(size: $0, figure: .helix) }
                    }
                    demo("Torus", "Dotted torus") {
                        sizes { Particle3DSpinner(size: $0, figure: .torus) }
                    }
                    demo("Ring", "Tilted dot ring · calmest") {
                        sizes { Particle3DSpinner(size: $0, figure: .ring) }
                    }
                    demo("Teal 3D", "3D figures accept a tint") {
                        HStack(spacing: Space.l) {
                            Particle3DSpinner(size: 34, color: Theme.teal, figure: .sphere)
                            Particle3DSpinner(size: 34, color: Theme.teal, figure: .cube)
                        }
                    }
                }

                Text("2D spinners").font(.sfCardTitle)
                LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                    demo("DotSpinner", "Ring + travelling glow · standard") {
                        sizes { DotSpinner(size: $0) }
                    }
                    demo("SparkleSpinner", "Twinkling 4-point sparkles") {
                        sizes { SparkleSpinner(size: $0) }
                    }
                    demo("OrbitSpinner", "Nested orbiting dots") {
                        sizes { OrbitSpinner(size: $0) }
                    }
                    demo("PulseDotsSpinner", "Travelling swell · thinking") {
                        sizes { PulseDotsSpinner(size: $0) }
                    }
                    demo("BloomSpinner", "Dots blooming outward") {
                        sizes { BloomSpinner(size: $0) }
                    }
                    demo("CometSpinner", "Orbiting head + fading trail") {
                        sizes { CometSpinner(size: $0) }
                    }
                    demo("WaveDotGrid", "Dots stretch + merge in a diagonal wave") {
                        sizes { WaveDotGrid(size: $0) }
                    }
                    demo("WorkingLogo", "The shared 'working' indicator") {
                        sizes { WorkingLogo(size: $0) }
                    }
                    demo("Teal tint", "Any spinner accepts a colour") {
                        HStack(spacing: Space.l) {
                            DotSpinner(size: 34, color: Theme.teal)
                            SparkleSpinner(size: 34, color: Theme.teal)
                            CometSpinner(size: 34, color: Theme.teal)
                        }
                    }
                }

                Text("Ambient field").font(.sfCardTitle)
                HStack(spacing: Space.l) {
                    demoBox { ParticleField(density: 90, reactive: true).frame(width: 200, height: 160) }
                    demoBox { ParticleField(density: 60, reactive: false).frame(width: 200, height: 160) }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
    }

    /// One spinner shown at 20 / 34 / 48 pt in a row.
    @ViewBuilder
    private func sizes<V: View>(@ViewBuilder _ make: (CGFloat) -> V) -> some View {
        HStack(spacing: Space.l) {
            make(20); make(34); make(48)
        }
    }

    private func demo<V: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: Space.m) {
            content().frame(height: 64)
            VStack(spacing: 2) {
                Text(title).font(.sfCallout.weight(.semibold)).monospaced()
                Text(subtitle).font(.sfCaption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
    }

    private func demoBox<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
            .clipShape(RoundedRectangle(cornerRadius: Theme.innerCorner))
    }
}

#Preview("Spinner") {
    HStack(spacing: 24) {
        DotSpinner(size: 20)
        DotSpinner(size: 32)
        DotSpinner(size: 48, color: Theme.teal)
    }
    .padding(40).background(Theme.appBg)
}
#Preview("Lab") { ParticleLabView().frame(width: 900, height: 680) }
#Preview("Field") {
    ParticleField().frame(width: 260, height: 260).padding().background(Theme.appBg)
}
