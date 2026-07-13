//
//  SphereLogoLab.swift
//  StrategyForge
//
//  LABS ONLY — five 3D Fibonacci-sphere logo concepts in the brand palette, from
//  the art-direction workflow ("Sun-Cut", "Carve", "Terminator", "Roles",
//  "Convener"). Each is the same golden-angle point cloud (matching the in-app
//  Particle3DSpinner) coloured a different way, so the mark still reads as *the
//  in-app globe*. Rendered frozen at hero + menu-bar sizes for side-by-side review.
//  Nothing here is wired into the rest of the app.
//

import SwiftUI

// Brand palette (kept file-private; mirrors IdentityLab's).
private enum SBrand {
    static let coral = Color(hex: 0xF0603A)
    static let coralDeep = Color(hex: 0xC7431F)
    static let coral300 = Color(hex: 0xF6906F)
    static let teal = Color(hex: 0x14C2AB)
    static let ink = Color(hex: 0x241E1A)
    static let paper = Color(hex: 0xF7F3EC)
    static let reefInk = Color(hex: 0x141A1E)
    static let foam = Color(hex: 0xEDE7DD)
}

private extension Color {
    init(hex: UInt) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Shared sphere math

private struct V3 {
    var x, y, z: Double
    static func dot(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    var normalized: V3 {
        let l = max((x * x + y * y + z * z).squareRoot(), 1e-9)
        return V3(x: x / l, y: y / l, z: z / l)
    }
}

/// One projected dot: its original (world) position, camera-space z for depth, the
/// screen point and the perspective scale. Concepts read `world`/`cam`/`depth`.
private struct ProjectedDot {
    let world: V3
    let cam: V3
    let screen: CGPoint
    let depth: Double   // (cam.z + 1) / 2
    let scale: Double   // perspective factor
}

/// Rotate about Y then X, project perspectively, and return dots sorted back-to-front.
private func fibonacciDots(n: Int, ax: Double, ay: Double, size: CGSize) -> [ProjectedDot] {
    let ga = Double.pi * (3 - 5.0.squareRoot())
    let cx = size.width / 2, cy = size.height / 2
    let R = 0.40 * min(size.width, size.height)
    var out: [ProjectedDot] = []
    out.reserveCapacity(n)
    for i in 0..<n {
        let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
        let r = max(0, 1 - y * y).squareRoot()
        let th = ga * Double(i)
        let world = V3(x: cos(th) * r, y: y, z: sin(th) * r)
        // Rotate about Y (ay) then X (ax).
        let x1 = world.x * cos(ay) + world.z * sin(ay)
        let z1 = -world.x * sin(ay) + world.z * cos(ay)
        let y2 = world.y * cos(ax) - z1 * sin(ax)
        let z2 = world.y * sin(ax) + z1 * cos(ax)
        let cam = V3(x: x1, y: y2, z: z2)
        let s = 1.7 / (1.7 - cam.z)
        let screen = CGPoint(x: cx + cam.x * s * R, y: cy - cam.y * s * R)
        out.append(ProjectedDot(world: world, cam: cam, screen: screen,
                                depth: (cam.z + 1) / 2, scale: s))
    }
    return out.sorted { $0.cam.z < $1.cam.z }   // back first
}

private func paint(_ ctx: inout GraphicsContext, _ p: CGPoint, _ radius: Double,
                   _ color: Color, opacity: Double = 1) {
    let r = CGFloat(radius)
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
             with: .color(color.opacity(opacity)))
}

// MARK: - The concepts

enum SphereConcept: String, CaseIterable, Identifiable {
    case sunCut, carve, terminator, roles, convener
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sunCut: return "A · Sun-Cut"
        case .carve: return "B · Carve (C-void)"
        case .terminator: return "C · Terminator"
        case .roles: return "D · Roles"
        case .convener: return "E · The Convener"
        }
    }
    var story: String {
        switch self {
        case .sunCut: return "Hard coral cap on a teal body — one great-circle split. Highest-contrast 16pt read; the art director's pick."
        case .carve: return "A C carved from the shadow hemisphere — the only mark that encodes the brand name in negative space."
        case .terminator: return "Coral day / teal night on a real-planet duotone; survives to a coral crescent at 16pt."
        case .roles: return "Latitude-banded team globe: teal coordinators at the poles, coral workers at the equator."
        case .convener: return "A 16pt-first orbit mark — equatorial ring + core, one teal agent-marker. Menu-bar native."
        }
    }
    /// Hero freeze pose (ax, ay), radians.
    var pose: (Double, Double) {
        switch self {
        case .sunCut: return (0.2, 0)
        case .carve: return (0.5, 0)
        case .terminator: return (0.5, 0.5)
        case .roles: return (0.5, 0.3)
        case .convener: return (0.55, 0.2)
        }
    }
    var heroN: Int { self == .sunCut ? 64 : 48 }
    var smallN: Int {
        switch self {
        case .sunCut: return 24
        case .carve: return 20
        case .terminator: return 16
        case .roles: return 18
        case .convener: return 12
        }
    }
    var palette: [Color] {
        switch self {
        case .sunCut, .terminator: return [SBrand.coral, SBrand.coral300, SBrand.teal, SBrand.reefInk]
        case .carve: return [SBrand.coral, SBrand.coral300, SBrand.coralDeep, SBrand.ink]
        case .roles: return [SBrand.teal, SBrand.coral300, SBrand.coral, SBrand.coralDeep]
        case .convener: return [SBrand.coral, SBrand.coral300, SBrand.teal, SBrand.coralDeep]
        }
    }
}

/// Renders a single concept, frozen at its hero pose.
struct SphereMark: View {
    let concept: SphereConcept
    var size: CGFloat = 120
    var onDark = false
    /// Override the point count (menu-bar previews pass the reduced `smallN`).
    var nOverride: Int?

    var body: some View {
        Canvas { ctx, sz in
            if concept == .convener { drawConvener(&ctx, sz); return }
            let n = nOverride ?? concept.heroN
            let (ax, ay) = concept.pose
            let dots = fibonacciDots(n: n, ax: ax, ay: ay, size: sz)
            let base = 0.034 * min(sz.width, sz.height)
            for d in dots {
                let (color, mul, op) = style(for: d)
                if op > 0.02 { paint(&ctx, d.screen, base * mul * d.scale, color, opacity: op) }
            }
        }
        .frame(width: size, height: size)
    }

    /// Per-dot colour + size-multiplier + opacity for the current concept.
    private func style(for d: ProjectedDot) -> (Color, Double, Double) {
        switch concept {
        case .sunCut:
            // Camera-vertical split reads cleanest frozen: coral cap over teal body.
            let dp = d.cam.y
            let szMul = 0.6 + 0.8 * d.depth
            let op = 0.6 + 0.4 * d.depth
            if dp < -0.78 { return (SBrand.reefInk, szMul, op) }
            if dp > 0.12 { return (SBrand.coral, szMul * 1.08, op) }
            if dp >= -0.08 { return (SBrand.coral300, szMul, op) }
            return (bright(SBrand.teal), szMul, op)
        case .carve:
            let lon = atan2(d.cam.x, d.cam.z)
            let front = d.cam.z > -0.15
            let carved = front && abs(d.cam.y) < 0.62 && lon >= -0.62 && lon <= 0.62
            let szMul = 0.55 + 0.9 * d.depth
            // Carved dots are dropped entirely — the gap is what reads as a C.
            if carved { return (SBrand.ink, 0.6, 0) }
            let c: Color = d.depth < 0.5 ? SBrand.coralDeep : (d.depth > 0.85 ? SBrand.coral300 : SBrand.coral)
            return (c, szMul, 1)
        case .terminator:
            let L = V3(x: 0.6, y: 0.35, z: 0.72).normalized
            let lam = V3.dot(d.world, L)
            let szMul = 0.55 + 0.9 * d.depth
            if lam < -0.7 { return (SBrand.reefInk, szMul, 1) }
            if lam > 0.25 { return (SBrand.coral, szMul, 1) }
            if lam > -0.15 { return (SBrand.coral300, szMul * 1.15, 1) }
            return (bright(SBrand.teal), szMul, 1)
        case .roles:
            let ay = abs(d.world.y)
            var c: Color = ay > 0.66 ? bright(SBrand.teal) : (ay > 0.25 ? SBrand.coral300 : SBrand.coral)
            if d.cam.z < 0 { c = Color.blend(c, SBrand.coralDeep, 0.4) }
            let szMul = (0.55 + 0.9 * d.depth) * (ay <= 0.18 ? 1.2 : 1)
            return (c, szMul, 1)
        case .convener:
            return (SBrand.coral, 1, 1)   // handled in drawConvener
        }
    }

    /// Slightly lift a colour on dark backgrounds so the shadow side glows.
    private func bright(_ c: Color) -> Color { onDark ? Color.blend(c, .white, 0.18) : c }

    /// The Convener is a bespoke equatorial-ring mark, not a full sphere.
    private func drawConvener(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let (ax, ay) = concept.pose
        let n = nOverride ?? concept.heroN
        let count = max(6, min(n, 12))
        let ga = Double.pi * (3 - 5.0.squareRoot())
        let cx = sz.width / 2, cy = sz.height / 2
        let R = 0.40 * min(sz.width, sz.height)
        let base = 0.034 * min(sz.width, sz.height)
        struct RD { let screen: CGPoint; let z: Double; let idx: Int; let scale: Double }
        var ring: [RD] = []
        for i in 0..<count {
            let a = ga * Double(i)
            let w = V3(x: cos(a) * 0.85, y: 0, z: sin(a) * 0.85)
            let x1 = w.x * cos(ay) + w.z * sin(ay)
            let z1 = -w.x * sin(ay) + w.z * cos(ay)
            let y2 = w.y * cos(ax) - z1 * sin(ax)
            let z2 = w.y * sin(ax) + z1 * cos(ax)
            let s = 1.7 / (1.7 - z2)
            ring.append(RD(screen: CGPoint(x: cx + x1 * s * R, y: cy - y2 * s * R),
                           z: z2, idx: i, scale: s))
        }
        // Front-most three get the highlight tint.
        let frontIdx = Set(ring.sorted { $0.z > $1.z }.prefix(3).map(\.idx))
        // Core dot, painted first (behind the ring).
        paint(&ctx, CGPoint(x: cx, y: cy), base * 1.6, SBrand.coralDeep)
        for d in ring.sorted(by: { $0.z < $1.z }) {
            let color: Color = d.idx == 0 ? bright(SBrand.teal)
                : (frontIdx.contains(d.idx) ? SBrand.coral300 : SBrand.coral)
            paint(&ctx, d.screen, base * (0.7 + 0.5 * (d.z + 1) / 2) * d.scale, color)
        }
    }
}

private extension Color {
    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func comp(_ c: Color) -> (Double, Double, Double) {
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
        }
        let (ar, ag, ab) = comp(a), (br, bg, bb) = comp(b)
        return Color(.sRGB, red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
    }
}

// MARK: - Labs section

struct SphereLogoLabSection: View {
    private let cols = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: Space.l)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sphere-logo variations").font(.sfDisplay)
                Text("Five ways to colour the in-app 3D Fibonacci sphere as a mark (art-director pick: “Sun-Cut”, paired with “Convener” as the menu-bar mark). Each is frozen at its hero pose; the small tiles show the 16–24pt read. Labs-only.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                ForEach(SphereConcept.allCases) { concept in card(concept) }
            }
        }
    }

    @ViewBuilder
    private func card(_ concept: SphereConcept) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(concept.title).font(.sfCardTitle)
            Text(concept.story).font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                markTile(bg: SBrand.paper) { SphereMark(concept: concept, size: 96, onDark: false) }
                markTile(bg: SBrand.reefInk) { SphereMark(concept: concept, size: 96, onDark: true) }
                // Menu-bar sizes, using the reduced small-N geometry.
                VStack(spacing: 10) {
                    SphereMark(concept: concept, size: 24, onDark: false, nOverride: concept.smallN)
                    SphereMark(concept: concept, size: 16, onDark: false, nOverride: concept.smallN)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(concept.palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 5).fill(c).frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.1)))
                }
            }
        }
        .padding(Space.l)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func markTile(bg: Color, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: 120, height: 120)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(bg))
    }
}

#Preview {
    ScrollView {
        HStack(spacing: 20) {
            ForEach(SphereConcept.allCases) { c in
                VStack(spacing: 8) {
                    Text(c.title).font(.system(size: 10))
                    SphereMark(concept: c, size: 110, onDark: false)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SBrand.paper))
                    SphereMark(concept: c, size: 110, onDark: true)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SBrand.reefInk))
                    HStack(spacing: 6) {
                        SphereMark(concept: c, size: 24, nOverride: c.smallN)
                        SphereMark(concept: c, size: 16, nOverride: c.smallN)
                    }
                }
            }
        }
        .padding(24)
    }
}
