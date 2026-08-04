//
//  ThinkingOrbsLab.swift
//  StrategyForge
//
//  A faithful SwiftUI Canvas port of Jakub Antalík's "thinking-orbs"
//  (github.com/Jakubantalik/thinking-orbs, MIT) — nine dotted 3D "thought" orbs, each a
//  mode with its own motion: working (orbits), searching (globe scan), solving (rubik),
//  listening (wave), connecting (web), weaving (braid), composing (ribbon), breathing
//  (ring), shaping (morph). Same math as the original 2D-canvas engine; rendered here with
//  SwiftUI Canvas and tinted coral. A Lab gallery to pick one for the app's loaders.
//

import SwiftUI

// MARK: - Model

enum OrbState: String, CaseIterable, Identifiable {
    case working, searching, solving, listening, connecting, weaving, composing, breathing, shaping
    var id: String { rawValue }
    var mode: String {
        switch self {
        case .working: "orbits"; case .searching: "globe"; case .solving: "rubik"
        case .listening: "wave"; case .connecting: "web"; case .weaving: "braid"
        case .composing: "ribbon"; case .breathing: "ring"; case .shaping: "morph"
        }
    }
    var title: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .working: "particles on tilted orbits"
        case .searching: "a scan meridian sweeps a dotted globe"
        case .solving: "bands scramble, then click back solved"
        case .listening: "a waveform rolls through the rings"
        case .connecting: "a constellation wires itself"
        case .weaving: "three strands plait around the sphere"
        case .composing: "an undulating multi-band sash"
        case .breathing: "a ring slowly morphing"
        case .shaping: "circle → triangle → square"
        }
    }
}

private struct OrbDot { var x, y, z, r, white: Double; var a: Double = 1 }
private struct OrbLine { var x1, y1, x2, y2, white, a, w: Double }

// MARK: - Engine (ported from thinking-orbs/src/engine)

enum OrbEngine {
    typealias Opts = [String: Double]

    // --- core helpers ---
    static func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
    static func frac(_ x: Double) -> Double { x - floor(x) }
    static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }
    static func vnoise(_ x: Double, _ y: Double) -> Double {
        let xi = floor(x), yi = floor(y)
        var fx = x - xi, fy = y - yi
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        let a = hashD(xi, yi), b = hashD(xi + 1, yi), c = hashD(xi, yi + 1), d = hashD(xi + 1, yi + 1)
        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
    }
    static func fibDir(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - (2 * (Double(i) + 0.5)) / Double(n)
        let rad = (1 - y * y).squareRoot()
        let a = Double(i) * golden
        return (rad * cos(a), y, rad * sin(a))
    }
    static func angleDelta(_ a: Double, _ b: Double) -> Double { atan2(sin(a - b), cos(a - b)) }
    static func radiusScale(_ size: Double, _ p: Double) -> Double { Foundation.pow(size / 300, p) }

    /// yaw+tilt+orthographic projection → (px, py, depthZ).
    static func makeProj(_ yaw: Double, _ tilt: Double, _ cx: Double, _ cy: Double, _ scale: Double)
        -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    // MARK: preset resolution (ported from presets.ts, the "64" size)

    private static let base: [String: Opts] = [
        "globe": ["latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1.0, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        "orbits": ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3, "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3],
        "rubik": ["latRings": 15, "lonDensity": 40, "moveCount": 14, "rBase": 0.6, "rDepth": 1.7, "rActive": 0.3, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3],
        "wave": ["rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        "web": ["nodeN": 30, "thr": 0.72, "signals": 5, "nodeR": 1.4, "nodeRDepth": 1.8, "lineW": 0.8, "rsPow": 0.6, "rMin": 0.3],
        "braid": ["strandN": 52, "turns": 3.0, "ghostN": 150, "rBase": 1.2, "rDepth": 1.8, "rsPow": 0.6, "rMin": 0.3],
        "ribbon": ["lanes": 5, "segs": 88, "ghostN": 150, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        "ring": ["lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3],
        "morph": ["rDot": 0.021, "iconD": 1, "rMin": 0.25],
    ]
    // (speed, count, size, extra) — the shipped "64" preset per mode.
    private static let presets: [String: (speed: Double, count: Double, size: Double, extra: Opts)] = [
        "orbits": (1.885, 1, 1, [:]),
        "globe": (2.015, 0.42, 1.15, ["scanMul": 4.08, "dimBase": 0.45]),
        "rubik": (1.82, 0.35, 1.05, [:]),
        "wave": (4.388, 0.341, 1, [:]),
        "web": (3.315, 1.35, 0.95, [:]),
        "braid": (1.625, 0.5, 1, [:]),
        "ribbon": (2.34, 0.25, 0.85, ["spin": 0, "bandMul": 3.9, "wobMul": 1]),
        "ring": (3.24, 0.25, 0.956, ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]),
        "morph": (2.405, 0.702, 0.395, ["spread": 1.45]),
    ]

    private static func scaleCounts(_ opts: Opts, _ scale: Double) -> Opts {
        var out = opts; var done = Set<String>(); let rt = scale.squareRoot()
        for (a, b) in [("latRings", "lonDensity"), ("rings", "lonDensity"), ("lanes", "segs")] {
            if let va = out[a], let vb = out[b], !done.contains(a), !done.contains(b) {
                out[a] = max(2, (va * rt).rounded()); out[b] = max(2, (vb * rt).rounded())
                done.insert(a); done.insert(b)
            }
        }
        for k in ["orbitN", "ghostN", "nodeN", "strandN", "signals"] {
            if let v = out[k], v != 0, !done.contains(k) { out[k] = max(1, (v * scale).rounded()) }
        }
        if let v = out["iconD"] { out["iconD"] = max(0.02, v * scale) }
        return out
    }
    private static func scaleRadii(_ opts: Opts, _ scale: Double) -> Opts {
        var out = opts
        for k in ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR", "nodeRDepth"] {
            if let v = out[k] { out[k] = v * scale }
        }
        out["rSizeMul"] = (out["rSizeMul"] ?? 1) * scale
        return out
    }

    static func resolve(_ state: OrbState) -> (speed: Double, opts: Opts) {
        let mode = state.mode
        let p = presets[mode] ?? (1, 1, 1, [:])
        var opts = base[mode] ?? [:]
        if p.count != 1 { opts = scaleCounts(opts, p.count) }
        if p.size != 1 { opts = scaleRadii(opts, p.size) }
        for (k, v) in p.extra { opts[k] = v }
        return (p.speed, opts)
    }

    // MARK: frame builders — one per mode

    fileprivate static func frame(_ state: OrbState, size: Double, t: Double, opts o: Opts) -> ([OrbDot], [OrbLine]) {
        switch state.mode {
        case "orbits": return (orbits(size, t, o), [])
        case "globe": return (globe(size, t, o), [])
        case "rubik": return (rubik(size, t, o), [])
        case "wave": return (wave(size, t, o), [])
        case "web": return web(size, t, o)
        case "braid": return (braid(size, t, o), [])
        case "ribbon", "ring": return (ribbon(size, t, o), [])
        case "morph": return (morph(size, t, o), [])
        default: return ([], [])
        }
    }

    private static func orbits(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.82
        let pt = makeProj(t * 0.12, 0.3, cx, cy, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let orbitN = Int(o["orbitN"] ?? 12), ghostN = Int(o["ghostN"] ?? 40), particles = Int(o["particles"] ?? 3)
        for orb in 0..<max(0, orbitN) {
            let h1 = hashD(Double(orb), 1.7), h2 = hashD(Double(orb), 5.2), h3 = hashD(Double(orb), 8.9)
            let ro = R * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi, phi = acos(2 * h2 - 1)
            let nx = sin(phi) * cos(th), ny = cos(phi), nz = sin(phi) * sin(th)
            var ux = -ny, uy = nx; let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot()); ux /= ul; uy /= ul
            let vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
            for k in 0..<max(0, ghostN) {
                let a = (Double(k) / Double(ghostN)) * 2 * .pi
                let (px, py, z) = pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: (o["ghostR"] ?? 0.9) * rs, white: 0.72, a: (o["ghostA"] ?? 0.5) * (0.4 + 0.6 * depth)))
            }
            for m in 0..<max(0, particles) {
                let a = t * speed + (Double(m) / Double(particles)) * 2 * .pi + h2 * 6
                let (px, py, z) = pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: ((o["partR"] ?? 1.2) + (o["partRDepth"] ?? 1.6) * depth) * rs, white: 0.3 - 0.22 * depth))
            }
        }
        return dots
    }

    private static func globe(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let spin = 0.5, cx = size / 2, cy = size / 2, radius = (size / 2) * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let pt = makeProj(t * spin, tilt, cx, cy, radius)
        let scan = t * (spin + (1.7 - spin) * (o["scanMul"] ?? 1))
        let rs = radiusScale(size, o["rsPow"] ?? 0.6), dimBase = o["dimBase"] ?? 1
        var dots: [OrbDot] = []
        let latRings = Int(o["latRings"] ?? 17), lonDensity = o["lonDensity"] ?? 44
        for li in 0...max(1, latRings) {
            let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                let d = angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                dots.append(OrbDot(x: px, y: py, z: z,
                                   r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * boost) * rs,
                                   white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                                   a: dimBase + (1 - dimBase) * min(1, boost)))
            }
        }
        return dots
    }

    private static func rubik(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.82
        let pt = makeProj(t * 0.55, 0.35 + 0.1 * sin(t * 0.9), cx, cy, R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let moveCount = Int(o["moveCount"] ?? 14)
        let moves = makeMoves(moveCount)
        let sc = solveCycle(t, moveCount, 0.42, 1.2)
        var dots: [OrbDot] = []
        let latRings = Int(o["latRings"] ?? 15), lonDensity = o["lonDensity"] ?? 40
        for li in 0...max(1, latRings) {
            let lat = -Double.pi / 2 + (Double(li) / Double(latRings)) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (x, y, z, inActive) = applyMoves(cosLat * cos(lon), sinLat, cosLat * sin(lon), moves, sc)
                let (px, py, zr) = pt(x, y, z)
                let depth = (zr + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: zr,
                                   r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (inActive ? (o["rActive"] ?? 0.3) : 0)) * rs,
                                   white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth - (inActive ? 0.14 : 0)))
            }
        }
        return dots
    }

    private struct Move { let axis: Int; let lo: Double; let hi: Double; let ang: Double }
    private static func makeMoves(_ count: Int) -> [Move] {
        (0..<max(0, count)).map { i in
            let axis = min(2, Int(hashD(Double(i), 2.3) * 3))
            let lo = -1.0 + 0.5 * Double(min(3, Int(hashD(Double(i), 5.9) * 4)))
            let dir = hashD(Double(i), 7.7) < 0.5 ? 1.0 : -1.0
            return Move(axis: axis, lo: lo, hi: lo + 0.5, ang: dir * .pi / 2)
        }
    }
    private static func solveCycle(_ time: Double, _ count: Int, _ slotDur: Double, _ rest: Double) -> (amount: [Double], active: Int) {
        let cyc = 2 * Double(count) * slotDur + rest
        let tc = time.truncatingRemainder(dividingBy: cyc)
        var amount = [Double](repeating: 0, count: count); var active = -1
        if tc < 2 * Double(count) * slotDur {
            let slot = Int(tc / slotDur)
            let p = (tc - Double(slot) * slotDur) / slotDur
            let cl = min(1, p / 0.7)
            let ep = 1 - Foundation.pow(1 - cl, 3)
            if slot < count {
                for i in 0..<slot { amount[i] = 1 }; amount[slot] = ep; active = slot
            } else {
                let u = 2 * count - 1 - slot
                if u >= 0 && u < count { for i in 0..<u { amount[i] = 1 }; amount[u] = 1 - ep; active = u }
            }
        }
        return (amount, active)
    }
    private static func applyMoves(_ x0: Double, _ y0: Double, _ z0: Double, _ moves: [Move], _ sc: (amount: [Double], active: Int)) -> (Double, Double, Double, Bool) {
        var x = x0, y = y0, z = z0, inActive = false
        for i in 0..<moves.count {
            guard sc.amount[i] > 0 else { continue }
            let mv = moves[i]
            let coord = mv.axis == 0 ? x : (mv.axis == 1 ? y : z)
            if coord < mv.lo || coord >= mv.hi { continue }
            if i == sc.active { inActive = true }
            let a = mv.ang * sc.amount[i], ca = cos(a), sa = sin(a)
            if mv.axis == 0 { let y2 = y * ca - z * sa; z = y * sa + z * ca; y = y2 }
            else if mv.axis == 1 { let x2 = x * ca + z * sa; z = -x * sa + z * ca; x = x2 }
            else { let x2 = x * ca - y * sa; y = x * sa + y * ca; x = x2 }
        }
        return (x, y, z, inActive)
    }

    private static func wave(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.874
        let pt = makeProj(t * 0.18, 0.38, cx, cy, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let rings = Int(o["rings"] ?? 15), lonDensity = o["lonDensity"] ?? 40
        for ri in 0...max(1, rings) {
            let lat = -Double.pi / 2 + (Double(ri) / Double(rings)) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
            let rr = R * (0.88 + 0.105 * w)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = (Double(lj) / Double(lonCount)) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / R + 1) / 2, crest = max(0, w)
                dots.append(OrbDot(x: px, y: py, z: z,
                                   r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * crest) * rs,
                                   white: 0.66 - 0.56 * depth - 0.1 * crest))
            }
        }
        return dots
    }

    private static func web(_ size: Double, _ t: Double, _ o: Opts) -> ([OrbDot], [OrbLine]) {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.8 * (o["spread"] ?? 1)
        let pt = makeProj(t * 0.12, 0.32, cx, cy, R)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let nodeN = Int(o["nodeN"] ?? 30), thr = o["thr"] ?? 0.72
        let nodeR = o["nodeR"] ?? 1.4, nodeRDepth = o["nodeRDepth"] ?? 1.8
        var nodes: [(Double, Double, Double)] = []
        for i in 0..<max(0, nodeN) {
            let d = fibDir(i, nodeN)
            let x = d.0 + 0.3 * (vnoise(Double(i) * 0.31 + 9, t * 0.24) - 0.5) * 2
            let y = d.1 + 0.3 * (vnoise(Double(i) * 0.53 + 27, t * 0.21) - 0.5) * 2
            let z = d.2 + 0.3 * (vnoise(Double(i) * 0.77 + 55, t * 0.27) - 0.5) * 2
            let l = (x * x + y * y + z * z).squareRoot()
            nodes.append((x / l, y / l, z / l))
        }
        var lines: [OrbLine] = [], dots: [OrbDot] = []
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let dx = nodes[i].0 - nodes[j].0, dy = nodes[i].1 - nodes[j].1, dz = nodes[i].2 - nodes[j].2
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                if dist >= thr { continue }
                let (x1, y1, z1) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
                let (x2, y2, z2) = pt(nodes[j].0, nodes[j].1, nodes[j].2)
                let depth = ((z1 + z2) / 2 + 1) / 2
                lines.append(OrbLine(x1: x1, y1: y1, x2: x2, y2: y2, white: 0.42,
                                     a: (1 - dist / thr) * (0.3 + 0.55 * depth), w: max(0.6, (o["lineW"] ?? 0.8) * rs)))
            }
        }
        for i in 0..<nodes.count {
            let (px, py, z) = pt(nodes[i].0, nodes[i].1, nodes[i].2)
            let depth = (z + 1) / 2, pulse = 1 + 0.25 * sin(t * 1.4 + Double(i) * 2.7)
            dots.append(OrbDot(x: px, y: py, z: z, r: (nodeR + nodeRDepth * depth) * pulse * rs, white: 0.55 - 0.45 * depth))
        }
        let signals = Int(o["signals"] ?? 5)
        for s in 0..<max(0, signals) {
            let seg = floor(t * 0.55 + Double(s) * 7.31)
            let a = Int(hashD(seg, Double(s) * 3.1 + 1.7) * Double(nodeN))
            let b = Int(hashD(seg, Double(s) * 5.7 + 4.2) * Double(nodeN))
            if a == b || a >= nodes.count || b >= nodes.count { continue }
            let f = frac(t * 0.55 + Double(s) * 7.31)
            let x = lerp(nodes[a].0, nodes[b].0, f), y = lerp(nodes[a].1, nodes[b].1, f), z = lerp(nodes[a].2, nodes[b].2, f)
            let l = max(1e-6, (x * x + y * y + z * z).squareRoot())
            let (px, py, zr) = pt(x / l, y / l, z / l)
            let depth = (zr + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: zr, r: (nodeR * 1.5 + nodeRDepth * depth) * rs, white: 0.05, a: 0.5 + 0.5 * depth))
        }
        return (dots, lines)
    }

    private static func braid(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.76
        let pt = makeProj(t * 0.4, 0.3, cx, cy, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        var dots: [OrbDot] = []
        let ghostN = Int(o["ghostN"] ?? 150)
        for i in 0..<max(0, ghostN) {
            let d = fibDir(i, ghostN); let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let strandN = Int(o["strandN"] ?? 52), turns = o["turns"] ?? 3
        for s in 0..<3 {
            let phase = (Double(s) / 3) * 2 * .pi
            for i in 0..<max(0, strandN) {
                let u = (frac(Double(i) / Double(strandN) + t * 0.045) * 2 - 1) * 0.96
                let surf = max(0, 1 - u * u).squareRoot()
                let endFade = min(1, (1 - abs(u)) / 0.1)
                let a = u * .pi * turns + phase
                let weave = 1 + 0.075 * sin(u * .pi * turns * 2 + phase * 2 + t * 0.8)
                let rr = surf * R * weave
                let (px, py, zr) = pt(cos(a) * rr, u * R * weave, sin(a) * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: zr, r: ((o["rBase"] ?? 1.2) + (o["rDepth"] ?? 1.8) * depth) * rs,
                                   white: 0.55 - 0.45 * depth, a: endFade * (0.45 + 0.55 * depth)))
            }
        }
        return dots
    }

    private static func ribbon(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        let cx = size / 2, cy = size / 2, R = (size / 2) * 0.78
        let spin = o["spin"] ?? 1, camTilt = 0.3
        let pt = makeProj(t * 0.1 * spin, camTilt, cx, cy, 1)
        let rs = radiusScale(size, o["rsPow"] ?? 0.6)
        let faceOn = (o["faceOn"] ?? 0) != 0
        var dots: [OrbDot] = []
        let ghostN = Int(o["ghostN"] ?? 150)
        for i in 0..<max(0, ghostN) {
            let d = fibDir(i, ghostN); let (px, py, z) = pt(d.0 * R, d.1 * R, d.2 * R)
            let depth = (z / R + 1) / 2
            dots.append(OrbDot(x: px, y: py, z: z, r: 0.8 * rs, white: 0.78, a: 0.1 + 0.22 * depth))
        }
        let ya = t * 0.24 * spin
        let ta = faceOn ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
        let ux = cos(ya), uy = 0.0, uz = sin(ya)
        let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
        let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
        let wobAmp = 0.23 * (o["wobMul"] ?? 1)
        let baseR = faceOn ? R / (1 + 0.85 * wobAmp) : R
        let baseLanes = o["lanes"] ?? 5, segs = Int(o["segs"] ?? 88)
        let lanes = max(1, Int((baseLanes * (o["bandMul"] ?? 1)).rounded()))
        for w in 0..<lanes {
            let laneOff = (Double(w) - Double(lanes - 1) / 2) * 0.075
            let edge = abs(Double(w) - Double(lanes - 1) / 2) / max(1, Double(lanes - 1) / 2)
            for k in 0..<max(0, segs) {
                let a = (Double(k) / Double(segs)) * 2 * .pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * (o["wobMul"] ?? 1)
                let radial = faceOn ? 1 + wob : 1
                let off = faceOn ? laneOff : laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let rr = baseR * radial
                let (px, py, zr) = pt((x / l) * rr, (y / l) * rr, (z / l) * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: zr,
                                   r: ((o["rBase"] ?? 1.1) + (o["rDepth"] ?? 1.7) * depth) * (1 - 0.25 * edge) * rs,
                                   white: 0.52 - 0.44 * depth + 0.18 * edge, a: 0.4 + 0.6 * depth))
            }
        }
        return dots
    }

    private static func morph(_ size: Double, _ t: Double, _ o: Opts) -> [OrbDot] {
        func smoothE(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        let circle: (Double) -> (Double, Double) = { f in let a = -Double.pi / 2 + f * 2 * .pi; return (cos(a) * 0.24, sin(a) * 0.24) }
        let triangle = polyPath([(0, -0.26), (0.24, 0.16), (-0.24, 0.16)])
        let square = polyPath([(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)])
        let cycle: [(Double) -> (Double, Double)] = [circle, triangle, square]
        let hold = 1.4, morphT = 0.9, seg = hold + morphT, K = cycle.count
        let tc = t.truncatingRemainder(dividingBy: seg * Double(K))
        let k = Int(tc / seg), local = tc - Double(k) * seg
        let m = local > hold ? smoothE((local - hold) / morphT) : 0
        let sprd = o["spread"] ?? 1
        let pA = cycle[k], pB = cycle[(k + 1) % K]
        let M = 160
        var pts: [(Double, Double)] = []
        for i in 0..<M { let f = Double(i) / Double(M); let a = pA(f), b = pB(f)
            pts.append(((a.0 + (b.0 - a.0) * m) * sprd, (a.1 + (b.1 - a.1) * m) * sprd)) }
        var L = [Double](repeating: 0, count: M); var total = 0.0
        for i in 0..<M { let a = pts[i], b = pts[(i + 1) % M]; let l = (pow(b.0 - a.0, 2) + pow(b.1 - a.1, 2)).squareRoot(); L[i] = l; total += l }
        let n = max(6, Int((34 * (o["iconD"] ?? 1)).rounded()))
        let re = (o["rDot"] ?? 0.021) * 1.35 * sprd
        let pulse = 1 + 0.02 * sin(local * 3.1)
        var dots: [OrbDot] = []; let c2 = size / 2
        var segI = 0; var acc = 0.0
        for k2 in 0..<n {
            let target = (Double(k2) / Double(n)) * total
            while acc + L[segI] < target && segI < M - 1 { acc += L[segI]; segI += 1 }
            let a = pts[segI], b = pts[(segI + 1) % M]
            let f = L[segI] != 0 ? min(1, (target - acc) / L[segI]) : 0
            let x = (a.0 + (b.0 - a.0) * f) * pulse, y = (a.1 + (b.1 - a.1) * f) * pulse
            dots.append(OrbDot(x: c2 + x * size, y: c2 + y * size, z: 0, r: max(0.35, re * size), white: 0.1))
        }
        return dots
    }
    private static func polyPath(_ verts: [(Double, Double)]) -> (Double) -> (Double, Double) {
        let V = verts.count; var L = [Double](repeating: 0, count: V); var total = 0.0
        for i in 0..<V { let a = verts[i], b = verts[(i + 1) % V]; let l = (pow(b.0 - a.0, 2) + pow(b.1 - a.1, 2)).squareRoot(); L[i] = l; total += l }
        return { f in
            var target = f * total; var i = 0
            while target > L[i] && i < V - 1 { target -= L[i]; i += 1 }
            let a = verts[i], b = verts[(i + 1) % V]
            let ff = L[i] != 0 ? min(1, target / L[i]) : 0
            return (a.0 + (b.0 - a.0) * ff, a.1 + (b.1 - a.1) * ff)
        }
    }
}

// MARK: - View

/// One animated thinking orb. Renders the resolved mode with SwiftUI Canvas, tinted coral
/// (ink value → coral opacity, so near/dark dots read strongest).
struct ThinkingOrb: View {
    let state: OrbState
    var size: CGFloat = 120
    var tint: Color = Theme.coral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let resolved = OrbEngine.resolve(state)
        TimelineView(.animation(paused: reduceMotion)) { tl in
            let t = (reduceMotion ? 0.6 : tl.date.timeIntervalSince(start)) * resolved.speed
            Canvas { ctx, sz in
                let (dots, lines) = OrbEngine.frame(state, size: Double(min(sz.width, sz.height)), t: t, opts: resolved.opts)
                for l in lines where (l.a) >= 0.02 {
                    var p = Path(); p.move(to: CGPoint(x: l.x1, y: l.y1)); p.addLine(to: CGPoint(x: l.x2, y: l.y2))
                    ctx.stroke(p, with: .color(tint.opacity(l.a * (1 - min(1, max(0, l.white))))), lineWidth: l.w)
                }
                for d in dots.sorted(by: { $0.z < $1.z }) where d.a >= 0.02 {
                    let op = d.a * (1 - min(1, max(0, d.white)))
                    guard op >= 0.02 else { continue }
                    let r = max(0.3, d.r)
                    ctx.fill(Path(ellipseIn: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)),
                             with: .color(tint.opacity(op)))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The Lab gallery section: all nine orbs side by side to pick one for the app's loaders.
/// A plain section (no ScrollView) so it drops into the Lab's existing scroll.
struct ThinkingOrbsLabSection: View {
    var tint: Color = Theme.coral
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: Space.l)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Thinking Orbs").font(.sfCardTitle)
            Text("SwiftUI port of thinking-orbs (Jakub Antalík, MIT) — nine dotted 3D thought orbs. Tell me which you want to use.")
                .font(.sfCaption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: cols, spacing: Space.l) {
                ForEach(OrbState.allCases) { s in
                    VStack(spacing: Space.s) {
                        ThinkingOrb(state: s, size: 130, tint: tint)
                        Text(s.title).font(.sfBodyM.weight(.semibold))
                        Text(s.blurb).font(.sfCaption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }
}
