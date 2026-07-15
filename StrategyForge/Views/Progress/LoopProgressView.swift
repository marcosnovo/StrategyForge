//
//  LoopProgressView.swift
//  StrategyForge
//
//  The ONE simple visual language for loop progress: iteration dots, a tiny
//  Act → Verify → Done stage strip, and a pass/fail verdict badge. Reused by
//  LoopRunPanel and (via ProgressDotsRow) the chat's running progress strip.
//

import SwiftUI

struct LoopProgressView: View {
    let iteration: Int          // 1-based; 0 when idle
    let maxTurns: Int
    let stage: LoopStage
    let verdicts: [Bool]        // one entry per completed iteration
    var compact: Bool = false
    @Environment(AppModel.self) private var model

    private var counter: String { "\(max(iteration, verdicts.count))/\(maxTurns)" }
    private var running: Bool { stage == .act || stage == .verify }

    var body: some View {
        if compact {
            HStack(spacing: Space.s) {
                dotsRow(cap: 8, size: 6, spacing: 3)
                Text(counter).font(.sfFieldLabel).foregroundStyle(.secondary)
                Text(stageLabel).font(.sfFieldLabel)
                    .foregroundStyle(running ? Theme.teal : Theme.accent).tracking(0.8)
                if stage == .done || stage == .failed { verdictBadge }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                dotsRow(cap: 20, size: 10, spacing: 6)
                HStack(spacing: Space.m) {
                    stageStrip
                    Spacer(minLength: Space.s)
                    if stage == .done || stage == .failed { verdictBadge }
                    Text(counter.replacingOccurrences(of: "/", with: " / "))
                        .font(.sfMono).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Iteration dots

    /// Past = filled green/red by verdict, current = pulsing coral, future = hollow.
    private func dotsRow(cap: Int, size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<min(maxTurns, cap), id: \.self) { i in
                if i < verdicts.count {
                    Circle().fill(verdicts[i] ? Theme.success : Theme.danger)
                        .frame(width: size, height: size)
                } else if i == iteration - 1 && running {
                    PulsingDot(size: size)
                } else {
                    Circle().strokeBorder(Theme.hairline, lineWidth: 1)
                        .frame(width: size, height: size)
                }
            }
            if maxTurns > cap {
                Text("+\(maxTurns - cap)").font(.sfCaption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counter) — \(stageLabel)")
    }

    // MARK: Stage strip (Act → Verify → Done)

    private var stageStrip: some View {
        HStack(spacing: Space.xs) {
            // Act / Verify are live work → teal; Done resolves to success (pass)
            // or coral (stopped/attention).
            stageSegment("progress.stage.act", active: stage == .act, tint: Theme.teal)
            arrow
            stageSegment("progress.stage.verify", active: stage == .verify, tint: Theme.teal)
            arrow
            stageSegment("progress.stage.done", active: stage == .done || stage == .failed,
                         tint: stage == .failed ? Theme.accent : Theme.success)
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .semibold)).foregroundStyle(.quaternary)
    }

    private func stageSegment(_ key: String, active: Bool, tint: Color) -> some View {
        Text(model.t(key).uppercased())
            .font(.sfFieldLabel).tracking(0.8)
            .foregroundStyle(active ? tint : Theme.tertiaryOnMaterial)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(active ? tint.opacity(0.14) : Color.clear))
    }

    private var stageLabel: String {
        switch stage {
        case .verify: return model.t("progress.stage.verify")
        case .done, .failed: return model.t("progress.stage.done")
        default: return model.t("progress.stage.act")
        }
    }

    // MARK: Verdict

    /// "PASS ✓" / "STOPPED ✗" capsule, shown once the loop is done or failed.
    private var verdictBadge: some View {
        let pass = stage == .done
        return Text(model.t(pass ? "progress.verdict.pass" : "progress.verdict.fail"))
            .font(.sfFieldLabel).tracking(0.8)
            .foregroundStyle(pass ? Theme.success : Theme.danger)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill((pass ? Theme.success : Theme.danger).opacity(0.14)))
    }
}

// MARK: - Pulsing "current" dot

/// The current-iteration dot: coral with a subtle expanding ring. Static under
/// Reduce Motion. No TimelineView — a repeatForever scale started on appear.
private struct PulsingDot: View {
    var size: CGFloat = 10
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(Theme.teal)
            .frame(width: size, height: size)
            .background(
                Circle().stroke(Theme.teal.opacity(0.55), lineWidth: 1.5)
                    .scaleEffect(pulsing ? 1.8 : 1)
                    .opacity(pulsing ? 0 : 0.8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Task dots (shared with the chat's running progress strip)

/// A compact done/current/pending dot row for task progress: done = green filled,
/// current = pulsing coral, pending = hollow. Internal so ChatView can reuse it.
struct ProgressDotsRow: View {
    let done: Int
    let total: Int
    var maxDots: Int = 10

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(total, maxDots), id: \.self) { i in
                if i < done {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                } else if i == done {
                    PulsingDot(size: 6)
                } else {
                    Circle().strokeBorder(Theme.hairline, lineWidth: 1).frame(width: 6, height: 6)
                }
            }
            if total > maxDots {
                Text("+\(total - maxDots)").font(.sfCaption2).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)   // the adjacent "n/m tasks" label carries the value
    }
}
