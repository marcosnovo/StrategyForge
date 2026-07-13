//
//  WowLab.swift
//  StrategyForge
//
//  LABS-ONLY: three RICH turn-completion "wow" candidates to review in motion and
//  pick from — Liquid Light (Metal caustics), Color Bloom (layered gradient glow),
//  and Sphere Resolve (the 3D particle cloud condensing into a glowing gem). Each is
//  token-triggered, self-terminating, non-blocking, Reduce-Motion aware. The winner
//  gets promoted to the real chat overlay.
//

import SwiftUI

// MARK: - 1) Liquid Light (Metal shader)

struct WowLiquidLight: View {
    var token: Int
    private let duration: Double = 1.6
    @State private var startDate: Date?
    @State private var active = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
                let e = startDate.map { tl.date.timeIntervalSince($0) } ?? -1
                let prog = e >= 0 ? min(e / duration, 1) : (reduceMotion ? -1 : -1)
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.liquidLight(
                        .float2(geo.size.width, geo.size.height),
                        .float(max(0, e)),
                        .float(max(0, prog))))
                    .opacity(active && prog >= 0 ? 1 : 0)
                    .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: token) { await play(token, duration: duration) { startDate = $0 } set: { active = $0 } }
    }
}

// MARK: - 2) Color Bloom (layered gradient glow — pure SwiftUI, rich)

struct WowColorBloom: View {
    var token: Int
    private let duration: Double = 1.7
    @State private var startDate: Date?
    @State private var active = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
            let e = startDate.map { tl.date.timeIntervalSince($0) } ?? -1
            let p = e >= 0 ? min(e / duration, 1) : -1
            ZStack {
                if p >= 0 {
                    layer(color: Theme.teal, from: 0.5, to: 1.35, blur: 42, peak: 0.34, p: p, phase: 0.10)
                    layer(color: .init(red: 1.0, green: 0.42, blue: 0.33), from: 0.35, to: 1.05, blur: 30, peak: 0.5, p: p, phase: 0.0)
                    layer(color: Theme.coral, from: 0.2, to: 0.7, blur: 14, peak: 0.85, p: p, phase: 0.0)
                }
            }
            .compositingGroup()
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: token) { await play(token, duration: duration) { startDate = $0 } set: { active = $0 } }
    }

    private func layer(color: Color, from: CGFloat, to: CGFloat, blur: CGFloat, peak: Double, p: Double, phase: Double) -> some View {
        // Ease the scale out; opacity rises then falls (a soft breath).
        let t = min(max((p - phase) / (1 - phase), 0), 1)
        let scale = from + (to - from) * (1 - pow(1 - t, 3))
        let op = sin(.pi * t) * peak
        return Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: 90))
            .frame(width: 180, height: 180)
            .scaleEffect(scale)
            .opacity(op)
            .blur(radius: blur * CGFloat(1 - t * 0.4))
    }
}

// MARK: - 3) Sphere Resolve (particle cloud → glowing gem)

struct WowSphereResolve: View {
    var token: Int
    private let duration: Double = 1.7
    @State private var startDate: Date?
    @State private var active = false

    private static let n = 90
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !active)) { tl in
            Canvas { ctx, size in
                guard let s = startDate else { return }
                let e = tl.date.timeIntervalSince(s); guard e >= 0, e <= duration else { return }
                draw(&ctx, size, e)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: token) { await play(token, duration: duration) { startDate = $0 } set: { active = $0 } }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ e: Double) {
        let p = min(e / duration, 1)
        let gather = min(max(p / 0.62, 0), 1)                 // scatter → sphere
        let ease = 1 - pow(1 - gather, 3)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) * 0.20
        let ga = 2.399963
        let rot = e * 1.1
        let alpha = p < 0.72 ? 1.0 : max(0, 1 - (p - 0.72) / 0.28)

        // Land pulse when the cloud has gathered.
        var pulse = 1.0, glow = 0.0
        if p >= 0.62 { let tau = p - 0.62; pulse = 1 + 0.16 * sin(.pi * tau / 0.2) * exp(-4 * tau); glow = 0.5 * exp(-4 * tau) }
        if glow > 0.01 {
            let gr = R * 2.6
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - gr, y: center.y - gr, width: gr*2, height: gr*2)),
                     with: .radialGradient(Gradient(colors: [Theme.coral.opacity(glow * alpha), .clear]), center: center, startRadius: 0, endRadius: gr))
        }

        struct P { let x, y, z: Double }
        var dots: [(CGPoint, Double, Color, Double)] = []   // point, depth, color, size
        for i in 0..<Self.n {
            let y = 1 - 2 * (Double(i) + 0.5) / Double(Self.n)
            let r = (1 - y*y).squareRoot()
            let th = ga * Double(i)
            // sphere target
            var vx = cos(th) * r, vy = y, vz = sin(th) * r
            // rotate Y
            let x1 = vx * cos(rot) + vz * sin(rot), z1 = -vx * sin(rot) + vz * cos(rot)
            vx = x1; vz = z1
            // scattered start: push far out along a seeded direction
            let seed = Double((i &* 2654435761) % 997) / 997.0
            let sr = 3.0 + seed * 3.0
            let sx = cos(th * 1.7 + seed * 6) * sr, sy = (seed - 0.5) * 6, sz = sin(th * 1.3 + seed * 4) * sr
            let px = sx + (vx - sx) * ease
            let py = sy + (vy - sy) * ease
            let pz = sz + (vz - sz) * ease
            let persp = 1.7 / (1.7 - min(pz, 1.5))
            let scr = CGPoint(x: center.x + CGFloat(px) * persp * R, y: center.y - CGFloat(py) * persp * R)
            let depth = (pz + 1.5) / 3.0
            let col = Color.blend(Theme.teal, Theme.coral, min(1, depth + 0.15))
            dots.append((scr, depth, col, (1.6 + 3.0 * depth) * pulse))
        }
        for (scr, depth, col, sz) in dots.sorted(by: { $0.1 < $1.1 }) {
            let r = sz
            ctx.fill(Path(ellipseIn: CGRect(x: scr.x - r, y: scr.y - r, width: r*2, height: r*2)),
                     with: .color(col.opacity((0.45 + 0.55 * depth) * alpha)))
        }
    }
}

// MARK: - Shared play helper

/// Start the clock on a token bump and auto-stop after `duration`.
@MainActor private func play(_ token: Int, duration: Double,
                             start: @escaping (Date?) -> Void, set: @escaping (Bool) -> Void) async {
    guard token > 0 else { return }
    start(Date()); set(true)
    try? await Task.sleep(for: .seconds(duration + 0.15))
    set(false); start(nil)
}

private extension Color {
    static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        func c(_ x: Color) -> (Double, Double, Double) {
            let n = NSColor(x).usingColorSpace(.sRGB) ?? .black
            return (Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
        }
        let (ar, ag, ab) = c(a), (br, bg, bb) = c(b)
        return Color(.sRGB, red: ar+(br-ar)*t, green: ag+(bg-ag)*t, blue: ab+(bb-ab)*t)
    }
}

// MARK: - Labs gallery

struct WowGalleryLabSection: View {
    @State private var t1 = 0
    @State private var t2 = 0
    @State private var t3 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wow moment — pick one").font(.sfDisplay)
                Text("Three rich turn-completion candidates. Tap Play on each and tell me which one you love; I'll promote it to the chat and drop the others.")
                    .font(.sfCallout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: Space.l) {
                candidate("1 · Liquid Light", "Metal caustic light, coral↔teal") { WowLiquidLight(token: t1) } play: { t1 += 1 }
                candidate("2 · Color Bloom", "Layered gradient glow, soft depth") { WowColorBloom(token: t2) } play: { t2 += 1 }
                candidate("3 · Sphere Resolve", "3D cloud condenses into a gem") { WowSphereResolve(token: t3) } play: { t3 += 1 }
            }
        }
    }

    @ViewBuilder
    private func candidate(_ title: String, _ sub: String, @ViewBuilder _ overlay: () -> some View, play: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(.sfCardTitle)
            Text(sub).font(.sfCaption2).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner).fill(Color(red: 0.078, green: 0.102, blue: 0.118))
                overlay()
            }
            .frame(width: 240, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
            Button("Play", action: play).buttonStyle(.moon).controlSize(.small)
        }
    }
}
