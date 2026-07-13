//
//  IdentityLab.swift
//  StrategyForge
//
//  LABS ONLY — three logo / visual-identity proposals from the design workflow
//  (Chief Product Designer synthesis), rendered from their exact 1024-grid
//  geometry so they can be reviewed side by side before anything ships app-wide.
//  Nothing here is used by the rest of the app.
//

import SwiftUI

// Brand palette (from the proposals).
private enum Brand {
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
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func comp(_ c: Color) -> (Double, Double, Double) {
            let n = NSColor(c).usingColorSpace(.sRGB) ?? .black
            return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
        }
        let (ar, ag, ab) = comp(a), (br, bg, bb) = comp(b)
        return Color(.sRGB, red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
    }
}

// MARK: - The three marks (Canvas, from 1024-grid geometry)

/// Proposal 1 — "Reef Ring C": a broken ring of dots (teal→coral bloom) that reads
/// as a C, a reef and a team; largest top dot is the teal orchestrator.
struct ReefRingMark: View {
    var size: CGFloat = 120
    var onDark = false
    var body: some View {
        Canvas { ctx, sz in
            let f = sz.width / 1024
            for i in 0...12 {
                let th = (40 + Double(i) * 23.333) * .pi / 180
                let x = (512 + 340 * cos(th)) * f
                let y = (512 - 340 * sin(th)) * f
                let r = (14 + Double(i) / 12 * 34) * f
                let color = i == 12 ? Brand.teal : Color.mix(Brand.teal, onDark ? Color(hex: 0xFF6E45) : Brand.coral, Double(i) / 12)
                dot(&ctx, x, y, r, color)
            }
            // Seed dot entering the gap (the prompt).
            dot(&ctx, 662 * f, 512 * f, 20 * f, Brand.coral)
        }
        .frame(width: size, height: size)
    }
}

/// Proposal 2 — "Delegation Graph": one hub delegating to many; teal packets in
/// flight jump the wire gaps. The app's live topology as the mark.
struct DelegationGraphMark: View {
    var size: CGFloat = 120
    var onDark = false
    private let nodes: [(CGFloat, CGFloat, CGFloat)] = [
        (512, 880, 20), (512, 690, 18), (410, 560, 14), (330, 470, 11), (270, 410, 8),
        (620, 560, 14), (700, 455, 11), (760, 390, 8), (525, 470, 13), (560, 360, 10),
        (600, 285, 7), (215, 470, 6), (655, 320, 6),
    ]
    private let edges: [(Int, Int)] = [(0,1),(1,2),(2,3),(3,4),(3,11),(1,5),(5,6),(6,7),(1,8),(8,9),(9,10),(9,12)]
    var body: some View {
        Canvas { ctx, sz in
            let f = sz.width / 1024
            let wire = onDark ? Color(hex: 0x33424B) : Color(hex: 0xC9BEB0)
            for (a, b) in edges {
                let pa = CGPoint(x: nodes[a].0 * f, y: nodes[a].1 * f)
                var pb = CGPoint(x: nodes[b].0 * f, y: nodes[b].1 * f)
                // Stop 8 grid-units short of the child so the packet visibly jumps.
                let dx = pb.x - pa.x, dy = pb.y - pa.y, len = max(hypot(dx, dy), 1)
                pb = CGPoint(x: pb.x - dx / len * 8 * f, y: pb.y - dy / len * 8 * f)
                var p = Path(); p.move(to: pa); p.addLine(to: pb)
                ctx.stroke(p, with: .color(wire), style: StrokeStyle(lineWidth: 1.5 * f, lineCap: .round))
                // Teal packet mid-flight.
                let t = 0.62
                dot(&ctx, pa.x + (pb.x - pa.x) * t, pa.y + (pb.y - pa.y) * t, 4 * f,
                    onDark ? Color(hex: 0x2BE0C8) : Brand.teal)
            }
            for n in nodes { dot(&ctx, n.0 * f, n.1 * f, n.2 * f, Brand.coral) }
        }
        .frame(width: size, height: size)
    }
}

/// Proposal 3 — "Polyp Bloom": a coral polyp made of dots — a core throwing curved
/// arms of graduated particles. Marketing / splash hero.
struct PolypBloomMark: View {
    var size: CGFloat = 120
    var onDark = false
    var body: some View {
        Canvas { ctx, sz in
            let f = sz.width / 1024
            let O = CGPoint(x: 512 * f, y: 512 * f)
            func place(_ radius: Double, _ deg: Double) -> CGPoint {
                let th = deg * .pi / 180
                return CGPoint(x: O.x + radius * cos(th) * f, y: O.y - radius * sin(th) * f)
            }
            dot(&ctx, O.x, O.y, 26 * f, onDark ? Color(hex: 0x2BE0C8) : Brand.teal)   // core
            for k in 0..<6 { let p = place(70, Double(k) * 60); dot(&ctx, p.x, p.y, 16 * f, Brand.coral) }
            for k in 0..<12 { let p = place(130, 15 + Double(k) * 30); dot(&ctx, p.x, p.y, 11 * f, Brand.coral) }
            // Six tentacle arms, curling +7° per successive dot.
            let radii: [Double] = [210, 300, 400, 510, 630]
            let taper: [Double] = [15, 13, 11, 8.5, 6]
            for axis in 0..<6 {
                for (j, rad) in radii.enumerated() {
                    let p = place(rad, Double(axis) * 60 + Double(j) * 7)
                    let c = Color.mix(Brand.coral, Brand.coral300, Double(j) / 4)
                    dot(&ctx, p.x, p.y, taper[j] * f, c)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private func dot(_ ctx: inout GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color))
}

// MARK: - Variations of the CURRENT branching mark (art-director workflow)

/// A CoralMark-style glyph from a spec: quad-bezier branches + graded node dots on a
/// 0…100 canvas. Used to render the three modern variations of the current logo.
struct CoralVariantMark: View {
    let branches: [[CGFloat]]     // [sx,sy,cx,cy,ex,ey]
    let nodes: [[CGFloat]]        // [x,y,r]
    let strokeFactor: CGFloat
    var nodeColors: [Color] = []
    var color: Color = Brand.coral
    var size: CGFloat = 96
    /// When set, all strokes + nodes render in this single color (dark-bg / mono).
    var monoColor: Color? = nil

    var body: some View {
        Canvas { ctx, sz in
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 100 * sz.width, y: y / 100 * sz.height)
            }
            let stroke = monoColor ?? color
            var path = Path()
            for b in branches { path.move(to: pt(b[0], b[1])); path.addQuadCurve(to: pt(b[4], b[5]), control: pt(b[2], b[3])) }
            ctx.stroke(path, with: .color(stroke),
                       style: StrokeStyle(lineWidth: sz.width * strokeFactor, lineCap: .round, lineJoin: .round))
            for (i, n) in nodes.enumerated() {
                let r = n[2] / 100 * sz.width, c = pt(n[0], n[1])
                let col = monoColor ?? (i < nodeColors.count ? nodeColors[i] : color)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(col))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The three finalists (exact specs from the workflow), plus the current mark.
enum CoralVariant: String, CaseIterable, Identifiable {
    case current, monoline, orgHubFork, polyp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .current: return "Current (shipping)"
        case .monoline: return "1 · Coral Monoline"
        case .orgHubFork: return "2 · Coral Org — Hub-Fork"
        case .polyp: return "3 · Coral Polyp — Alive"
        }
    }
    var story: String {
        switch self {
        case .current: return "The mark you have today — for side-by-side comparison."
        case .monoline: return "Ruthless mirror symmetry, straight trunk, three nodes. Linear/Stripe-era restraint."
        case .orgHubFork: return "Same silhouette, but the two forks become hub nodes: a 3-tier orchestrator→hubs→workers graph, one teal signal dot."
        case .polyp: return "Controlled asymmetry + size-graded tips — the mark feels grown, not drawn."
        }
    }
    var branches: [[CGFloat]] {
        switch self {
        case .current: return [[50,84,50,70,50,60],[50,60,40,52,29,40],[29,40,24,31,21,24],[29,40,34,31,39,25],[50,60,60,52,71,40],[71,40,76,31,79,24],[71,40,66,31,61,25]]
        case .monoline: return [[50,86,50,72,50,58],[50,58,38,46,26,22],[50,58,62,46,74,22],[50,58,36,40,40,30],[50,58,64,40,60,30]]
        case .orgHubFork: return [[50,84,50,70,50,60],[50,60,40,52,29,40],[29,40,24,31,21,24],[29,40,34,31,39,24],[50,60,60,52,71,40],[71,40,76,31,79,24],[71,40,66,31,61,24]]
        case .polyp: return [[50,84,51.5,71,49,58],[49,58,39,51,27,41],[27,41,22,32,19,25],[27,41,32,32,37,27],[49,58,60,50,72,43],[72,43,78,34,81,26],[72,43,66,32,60,23]]
        }
    }
    var nodes: [[CGFloat]] {
        switch self {
        case .current: return [[50,84,7.6],[21,24,5.6],[39,25,5.6],[61,25,5.6],[79,24,5.6]]
        case .monoline: return [[50,86,7.2],[26,22,5.4],[74,22,5.4]]
        case .orgHubFork: return [[50,84,7.8],[29,40,5.9],[71,40,5.9],[21,24,4.6],[39,24,4.6],[61,24,4.6],[79,24,4.6],[50,60,2.6]]
        case .polyp: return [[50,84,7.8],[19,25,4.8],[37,27,5.4],[60,23,6.2],[81,26,5.1]]
        }
    }
    var strokeFactor: CGFloat { self == .monoline ? 0.058 : 0.062 }
    var nodeColors: [Color] {
        self == .orgHubFork
            ? [Brand.coral, Brand.coral, Brand.coral, Brand.coral300, Brand.coral300, Brand.coral300, Brand.coral300, Brand.teal]
            : []
    }
}

// MARK: - Labs section

struct IdentityLabSection: View {
    private let cols = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: Space.l)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brand identity — proposals").font(.sfDisplay)
                Text("Three logo + palette directions from the design workflow (Chief Product Designer pick: “Reef Ring C”). Labs-only — review before shipping.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                proposalCard("1 · Reef Ring C", "Chief's pick — a dotted broken ring that's a C, a reef and a team.",
                             palette: [Brand.coral, Brand.teal, Brand.coralDeep, Brand.ink],
                             primary: "Assemble team", secondary: "Preview") { ReefRingMark(size: $0, onDark: $1) }
                proposalCard("2 · Delegation Graph", "The live hub→many topology; teal packets in flight. In-app hero.",
                             palette: [Brand.coral, Brand.teal, Color(hex: 0xC9BEB0), Brand.ink],
                             primary: "Run team", secondary: "Add agent") { DelegationGraphMark(size: $0, onDark: $1) }
                proposalCard("3 · Polyp Bloom", "A coral polyp of dots that breathes and grows. Marketing / splash.",
                             palette: [Brand.coral, Brand.teal, Brand.coral300, Brand.ink],
                             primary: "Start a reef", secondary: "See how it works") { PolypBloomMark(size: $0, onDark: $1) }
            }
        }
    }

    @ViewBuilder
    private func proposalCard(_ title: String, _ story: String, palette: [Color],
                              primary: String, secondary: String,
                              @ViewBuilder mark: @escaping (CGFloat, Bool) -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.sfCardTitle)
            Text(story).font(.sfCaption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // Mark on paper + on reef-ink.
            HStack(spacing: Space.m) {
                markTile(bg: Brand.paper) { mark(96, false) }
                markTile(bg: Brand.reefInk) { mark(96, true) }
                VStack(spacing: 8) { mark(22, false); mark(16, false) }   // menu-bar sizes
            }
            // Palette swatches.
            HStack(spacing: 6) {
                ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 5).fill(c).frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.1)))
                }
            }
            // CTAs.
            HStack(spacing: Space.s) {
                Text(primary).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.foam)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Brand.coral))
                Text(secondary).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.teal)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(Brand.teal, lineWidth: 1.5))
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

// MARK: - Current-mark variations section (what the client actually wanted)

/// Three modern variations OF the current branching mark (the client prefers the
/// current glyph over the sphere concepts). Review-only, in Labs.
struct CoralMarkLabSection: View {
    private let cols = [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: Space.l)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Logo — variations of the current mark").font(.sfDisplay)
                Text("You preferred the current branching mark over the sphere concepts, so a fresh panel of designers evolved IT — three modern, unique takes that keep the one-root-to-four-tips DNA. Frozen on paper, reef-ink and at menu-bar sizes. Labs-only.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: cols, alignment: .leading, spacing: Space.l) {
                ForEach(CoralVariant.allCases) { v in card(v) }
            }
        }
    }

    @ViewBuilder
    private func card(_ v: CoralVariant) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(v.title).font(.sfCardTitle)
            Text(v.story).font(.sfCaption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                markTile(bg: Brand.paper) {
                    CoralVariantMark(branches: v.branches, nodes: v.nodes, strokeFactor: v.strokeFactor,
                                     nodeColors: v.nodeColors, size: 96)
                }
                markTile(bg: Brand.reefInk) {
                    CoralVariantMark(branches: v.branches, nodes: v.nodes, strokeFactor: v.strokeFactor,
                                     size: 96, monoColor: .white)
                }
                VStack(spacing: 12) {
                    CoralVariantMark(branches: v.branches, nodes: v.nodes, strokeFactor: v.strokeFactor, nodeColors: v.nodeColors, size: 26)
                    CoralVariantMark(branches: v.branches, nodes: v.nodes, strokeFactor: v.strokeFactor, nodeColors: v.nodeColors, size: 16)
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
