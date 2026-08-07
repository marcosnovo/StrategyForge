//
//  WorkingLogo.swift
//  StrategyForge
//
//  The "working / waiting" indicator — the app's BRAND loader: a rotating 3D
//  Fibonacci sphere of coral dots (see Particle3DSpinner in ParticleField). Every
//  waiting state in the app routes through this so they all share one identity.
//  Honors Reduce Motion (the sphere freezes to a static frame).
//

import SwiftUI

struct WorkingLogo: View {
    var size: CGFloat = 18
    var color: Color = Theme.accent
    var body: some View { Particle3DSpinner(size: size, color: color, figure: .sphere) }
}

/// A self-timing "Xs" / "Nm Ss" counter that starts when it appears — drop next to any
/// existing spinner that lacks an elapsed readout, so a long wait always shows movement.
struct ElapsedText: View {
    @State private var start = Date()
    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(start)))
            Text(s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s")
                .font(.sfCaption2.monospacedDigit()).foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }
}

/// A subtle, segmented request-progress bar — "how much is left for my request?" — modelled
/// on the reference video's quiet tick meter. `progress` nil = indeterminate (a soft highlight
/// sweeps the ticks); a value fills ticks proportionally. Coral fill on a hairline track.
struct RequestProgressBar: View {
    /// 0…1, or nil for an indeterminate run (no known step count).
    var progress: Double?
    var segments: Int = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let w = max(1, (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments))
            if let p = progress {
                let filled = Int((Double(segments) * min(max(p, 0), 1)).rounded())
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { i in
                        Capsule().fill(i < filled ? Theme.coral : Theme.hairline)
                            .frame(width: w)
                            .animation(.easeOut(duration: 0.3), value: filled)
                    }
                }
            } else if reduceMotion {
                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { _ in Capsule().fill(Theme.coral.opacity(0.3)).frame(width: w) }
                }
            } else {
                // Indeterminate: a soft coral highlight sweeps left→right across the ticks.
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let head = (t * 0.6).truncatingRemainder(dividingBy: 1.0)   // 0…1 sweep
                    HStack(spacing: gap) {
                        ForEach(0..<segments, id: \.self) { i in
                            let d = abs(Double(i) / Double(segments - 1) - head)
                            Capsule().fill(Theme.coral.opacity(max(0.12, 0.9 - d * 3)))
                                .frame(width: w)
                        }
                    }
                }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// A drop-in "we're working" line: the brand spinner + a status label + a LIVE elapsed
/// counter that ticks every second. Self-timing — it starts counting the moment it appears
/// (so callers just do `if busy { WorkingLine("Generating…") }`, no start-date bookkeeping).
/// This is the app-wide antidote to "looks frozen": every long op should show one of these.
struct WorkingLine: View {
    let label: String
    var size: CGFloat = 16
    /// After this many seconds, add a gentle "taking a while" reassurance.
    var slowAfter: Int = 45
    @Environment(AppModel.self) private var model
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(start)))
            HStack(spacing: Space.s) {
                WorkingLogo(size: size)
                Text(label).font(.sfCaption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Text(s < 60 ? "· \(s)s" : "· \(s / 60)m \(s % 60)s")
                    .font(.sfCaption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                if s >= slowAfter {
                    Text(model.t("working.slow")).font(.sfCaption2).foregroundStyle(Theme.warningText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
