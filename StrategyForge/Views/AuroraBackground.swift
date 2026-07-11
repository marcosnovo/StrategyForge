//
//  AuroraBackground.swift
//  StrategyForge
//
//  Ambient aurora: a slow-drifting coral/teal MeshGradient wash, the app's
//  "alive" backdrop for hero moments. Very low opacity — it must never compete
//  with content. Static under Reduce Motion (one still mesh frame, no
//  TimelineView at all).
//
//  MOUNTING (important): this view redraws continuously via TimelineView.
//  Continuously-redrawing TimelineViews layered over materials have caused
//  hangs in this app when their INSERTION was animated. Mount AuroraBackground
//  statically — a permanent background layer — and never insert/remove it
//  inside `withAnimation` or an animated transition. To fade it in/out, keep
//  it mounted and animate `intensity` (or an outer `.opacity`) instead.
//

import SwiftUI

struct AuroraBackground: View {
    var intensity: Double = 1.0   // 0…1 multiplies opacity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion || intensity <= 0 {
                wash(at: 0)   // one still frame — no clock running
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                    wash(at: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .opacity(max(0, min(intensity, 1)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Frame

    private func wash(at t: TimeInterval) -> some View {
        MeshGradient(width: 4, height: 3, points: points(at: t), colors: Self.colors)
            .overlay(cornerGlow)
            .drawingGroup()   // rasterize the mesh + glow in one Metal pass
    }

    /// A soft coral bloom near the top-leading corner — the aurora's anchor.
    private var cornerGlow: some View {
        RadialGradient(colors: [Theme.coral.opacity(0.10), .clear],
                       center: UnitPoint(x: 0.12, y: 0.02),
                       startRadius: 0, endRadius: 420)
    }

    // MARK: Mesh geometry

    /// 4×3 control grid. Interior points (and edge points along their edge)
    /// drift on slow phase-offset sine paths — 8–14 s periods, so the wash
    /// never visibly loops. `t == 0` yields the Reduce Motion still frame.
    private func points(at t: TimeInterval) -> [SIMD2<Float>] {
        // Base (x, y) + amplitudes (ax, ay) + periods in seconds (px, py) + phase.
        func drift(_ x: Double, _ y: Double, _ ax: Double, _ ay: Double,
                   _ px: Double, _ py: Double, _ phase: Double) -> SIMD2<Float> {
            SIMD2(Float(x + ax * sin(t * 2 * .pi / px + phase)),
                  Float(y + ay * sin(t * 2 * .pi / py + phase * 1.7)))
        }
        return [
            // Top edge — x wanders a touch, y pinned to the border.
            [0, 0],
            drift(0.35, 0, 0.06, 0, 11, 1, 0.0),
            drift(0.68, 0, 0.05, 0, 13, 1, 2.1),
            [1, 0],
            // Middle row — the aurora's moving heart.
            drift(0.00, 0.50, 0, 0.08, 1, 9, 1.2),
            drift(0.32, 0.48, 0.10, 0.12, 12, 9, 0.6),
            drift(0.66, 0.55, 0.11, 0.10, 10, 14, 3.4),
            drift(1.00, 0.50, 0, 0.07, 1, 8, 4.2),
            // Bottom edge.
            [0, 1],
            drift(0.36, 1, 0.05, 0, 14, 1, 1.9),
            drift(0.70, 1, 0.06, 0, 9, 1, 5.0),
            [1, 1],
        ]
    }

    /// Coral and teal at whisper opacities. Corners fade through *transparent
    /// brand hues* (not `.clear`) so the interpolation never goes muddy; the
    /// wash reads on warm paper and reef ink alike.
    private static let colors: [Color] = [
        Theme.coral.opacity(0.14), Theme.coral.opacity(0.10), Theme.teal.opacity(0.00), Theme.teal.opacity(0.07),
        Theme.coral.opacity(0.05), Theme.coral.opacity(0.13), Theme.teal.opacity(0.09), Theme.teal.opacity(0.06),
        Theme.teal.opacity(0.00),  Theme.coral.opacity(0.06), Theme.teal.opacity(0.08), Theme.coral.opacity(0.00),
    ]
}

#Preview("Aurora over app bg") {
    ZStack {
        Theme.appBg
        AuroraBackground()
        Text("Content must stay king").font(.sfDisplay).foregroundStyle(Theme.ink)
    }
    .frame(width: 640, height: 420)
}
