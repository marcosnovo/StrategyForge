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
                    // Layered depth: teal halo → amber mid → coral core.
                    layer(color: Theme.teal, from: 0.55, to: 1.5, blur: 46, peak: 0.32, p: p, phase: 0.12)
                    layer(color: .init(red: 1.0, green: 0.66, blue: 0.30), from: 0.4, to: 1.1, blur: 30, peak: 0.5, p: p, phase: 0.04)
                    layer(color: Theme.coral, from: 0.22, to: 0.72, blur: 16, peak: 0.85, p: p, phase: 0.0)
                    // Hot core flash (fast spike then decay) — the "pop of light".
                    coreFlash(p: p)
                    // Expanding shockwave ring — a crisp light edge racing outward.
                    shockwave(p: p, color: Theme.coral, delay: 0.02)
                    shockwave(p: p, color: Theme.teal, delay: 0.12)
                    // Slow angular shimmer for a living, glassy sheen.
                    AngularGradient(colors: [.clear, Theme.coral.opacity(0.5), .clear, Theme.teal.opacity(0.4), .clear],
                                    center: .center, angle: .degrees(e * 90))
                        .frame(width: 230, height: 230).mask(Circle().stroke(lineWidth: 26)).blur(radius: 12)
                        .scaleEffect(0.6 + p * 0.9).opacity(sin(.pi * p) * 0.5)
                }
            }
            .compositingGroup()
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: token) { await play(token, duration: duration) { startDate = $0 } set: { active = $0 } }
    }

    private func layer(color: Color, from: CGFloat, to: CGFloat, blur: CGFloat, peak: Double, p: Double, phase: Double) -> some View {
        let t = min(max((p - phase) / (1 - phase), 0), 1)
        let scale = from + (to - from) * (1 - pow(1 - t, 3))
        let op = sin(.pi * t) * peak
        return Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: 95))
            .frame(width: 190, height: 190).scaleEffect(scale).opacity(op)
            .blur(radius: blur * CGFloat(1 - t * 0.4))
    }

    private func coreFlash(p: Double) -> some View {
        let t = min(p / 0.28, 1)                              // spikes in first 0.28
        let op = (1 - t) * (t < 0.06 ? t / 0.06 : 1)          // quick in, decay out
        return Circle()
            .fill(RadialGradient(colors: [.white, Theme.coral.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: 60))
            .frame(width: 120, height: 120).scaleEffect(0.4 + t * 0.9).opacity(op).blur(radius: 6)
    }

    private func shockwave(p: Double, color: Color, delay: Double) -> some View {
        let t = min(max((p - delay) / 0.7, 0), 1)
        let op = (1 - t) * 0.7 * (t > 0 ? 1 : 0)
        return Circle().stroke(color, lineWidth: 3 * CGFloat(1 - t) + 0.5)
            .frame(width: 90, height: 90).scaleEffect(0.4 + t * 2.4).opacity(op).blur(radius: 1.5)
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

    private let gatherEnd = 0.6
    /// Screen position + depth of particle `i` at time `e`.
    private func particle(_ i: Int, _ e: Double, _ center: CGPoint, _ R: CGFloat) -> (CGPoint, Double) {
        let p = min(e / duration, 1)
        let gather = min(max(p / gatherEnd, 0), 1)
        let ease = 1 - pow(1 - gather, 3)
        let ga = 2.399963, rot = e * 1.1
        let y = 1 - 2 * (Double(i) + 0.5) / Double(Self.n)
        let rr = (1 - y*y).squareRoot()
        let th = ga * Double(i)
        var vx = cos(th) * rr, vz = sin(th) * rr
        let x1 = vx * cos(rot) + vz * sin(rot), z1 = -vx * sin(rot) + vz * cos(rot)
        vx = x1; vz = z1
        let seed = Double((i &* 2654435761) % 997) / 997.0
        let sr = 3.2 + seed * 3.2
        let sx = cos(th * 1.7 + seed * 6) * sr, sy = (seed - 0.5) * 6.5, sz = sin(th * 1.3 + seed * 4) * sr
        let px = sx + (vx - sx) * ease, py = sy + (y - sy) * ease, pz = sz + (vz - sz) * ease
        let persp = 1.7 / (1.7 - min(pz, 1.5))
        return (CGPoint(x: center.x + CGFloat(px) * persp * R, y: center.y - CGFloat(py) * persp * R), (pz + 1.5) / 3.0)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ e: Double) {
        let p = min(e / duration, 1)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) * 0.20
        let alpha = p < 0.72 ? 1.0 : max(0, 1 - (p - 0.72) / 0.28)
        let converging = p < gatherEnd

        // Land beat: bright flash + expanding shock-ring + gem glow the instant the
        // cloud snaps together.
        var pulse = 1.0, glow = 0.0
        if p >= gatherEnd { let tau = p - gatherEnd; pulse = 1 + 0.18 * sin(.pi * tau / 0.2) * exp(-4 * tau); glow = 0.55 * exp(-3.5 * tau) }
        if glow > 0.01 {
            let gr = R * 2.8
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - gr, y: center.y - gr, width: gr*2, height: gr*2)),
                     with: .radialGradient(Gradient(colors: [Theme.coral.opacity(glow * alpha), .clear]), center: center, startRadius: 0, endRadius: gr))
            // expanding ring
            let rt = min((p - gatherEnd) / 0.35, 1)
            if rt < 1 {
                let rr = R * (0.8 + rt * 2.2)
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr*2, height: rr*2)),
                           with: .color(Theme.coral.opacity((1 - rt) * 0.6 * alpha)), lineWidth: 2.5 * (1 - rt) + 0.5)
            }
        }

        // Particles with motion-blur streaks while converging.
        var dots: [(CGPoint, Double)] = []
        for i in 0..<Self.n {
            let (cur, depth) = particle(i, e, center, R)
            if converging {
                let (prev, _) = particle(i, max(0, e - 0.045), center, R)
                var streak = Path(); streak.move(to: prev); streak.addLine(to: cur)
                let col = Color.blend(Theme.teal, Theme.coral, min(1, depth + 0.15))
                ctx.stroke(streak, with: .color(col.opacity(0.35 * (1 - p / gatherEnd) * alpha)),
                           style: StrokeStyle(lineWidth: (0.8 + 2.0 * depth), lineCap: .round))
            }
            dots.append((cur, depth))
        }
        for (scr, depth) in dots.sorted(by: { $0.1 < $1.1 }) {
            let col = Color.blend(Theme.teal, Theme.coral, min(1, depth + 0.15))
            let r = (1.6 + 3.2 * depth) * pulse
            // soft halo + core
            ctx.fill(Path(ellipseIn: CGRect(x: scr.x - r*2, y: scr.y - r*2, width: r*4, height: r*4)),
                     with: .color(col.opacity(0.12 * depth * alpha)))
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
