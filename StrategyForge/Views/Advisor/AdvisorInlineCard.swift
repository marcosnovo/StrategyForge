//
//  AdvisorInlineCard.swift
//  StrategyForge
//
//  The Advisor, inside the chat: a compact one-row suggestion shown while the
//  user composes the FIRST message. It shows the recommended model + team +
//  loop at a glance, explains itself on demand (the full decision path in a
//  popover), and offers one-tap apply actions. Purely presentational — the
//  reasoning lives in AdvisorEngine, the wiring in ChatView.
//

import SwiftUI

struct AdvisorInlineCard: View {
    let advice: AdvisorEngine.Advice
    /// Display name of the RECOMMENDED strategy (the caller resolves it via
    /// AppModel.strategyDisplayName so this view stays presentation-only).
    let strategyName: String
    let onApplyTeam: () -> Void
    let onCreateLoop: () -> Void
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var model
    @State private var showWhy = false

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.accentSoft))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                FieldLabel(text: model.t("advisor.inline.caption"))
                HStack(spacing: Space.xs) {
                    Image(systemName: advice.model.tierIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text(summary)
                        .font(.sfCallout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .help(summary)   // the untruncated summary lives in the tooltip

            Spacer(minLength: Space.s)

            // "Why this?" — the decision path, on demand instead of in the way.
            Button { showWhy = true } label: {
                Image(systemName: "info.circle").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.t("advisor.inline.why"))
            .accessibilityLabel(model.t("advisor.inline.why"))
            .popover(isPresented: $showWhy, arrowEdge: .top) {
                ScrollView {
                    DecisionPathView(steps: advice.decisionPath,
                                     terminal: advice.model.displayName)
                        .padding(Space.l)
                }
                .frame(width: 360)
                .frame(maxHeight: 380)
            }

            Button(model.t("advisor.inline.applyTeam"), action: onApplyTeam)
                .buttonStyle(.moon)
                .controlSize(.small)

            Button(model.t("advisor.inline.createLoop"), action: onCreateLoop)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(model.t("advisor.inline.dismiss"))
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.insetBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        // Slide in gently from the composer's edge; fade out on dismiss.
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
    }

    /// "Fable 5 · Planner → Reviewer · Goal loop" — the whole advice, one line.
    private var summary: String {
        "\(advice.model.displayName) · \(strategyName) · \(model.t(advice.loopKind.labelKey))"
    }
}
