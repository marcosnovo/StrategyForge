//
//  AdvisorInlineCard.swift
//  StrategyForge
//
//  The Advisor, inside the chat: a compact suggestion shown while the user composes
//  the FIRST message. It offers three cost/quality OPTIONS (Economy · Recommended ·
//  Max), makes the source (Apple Intelligence vs local engine) explicit, explains
//  itself on demand (the decision path), and applies the chosen team in one tap.
//  Purely presentational — the reasoning lives in AdvisorEngine, the wiring in ChatView.
//

import SwiftUI

struct AdvisorInlineCard: View {
    /// The cost/quality options for this task (Economy · Recommended · Max).
    let tiers: [AdvisorEngine.Tier]
    /// Which tier is selected.
    let selectedID: String
    let onSelectTier: (String) -> Void
    let onApplyTeam: () -> Void
    let onCreateLoop: () -> Void
    let onDismiss: () -> Void
    /// Open System Settings so the user can turn on Apple Intelligence.
    var onEnableAI: () -> Void = {}
    /// When the chat already has a team the user deliberately chose, its name — so the
    /// card frames itself as "you chose X, here's what I'd recommend" instead of a
    /// blank suggestion. nil when the team is still auto.
    var currentTeamName: String? = nil

    @Environment(AppModel.self) private var model
    @State private var showWhy = false

    private var selected: AdvisorEngine.Tier? {
        tiers.first { $0.id == selectedID } ?? tiers.first { $0.id == "balanced" } ?? tiers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            headerRow
            if let team = currentTeamName { chosenTeamRow(team) }
            tierRow
            if let sel = selected {
                selectionRow(sel)
                providerMixRow(sel)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: Space.s) {
            sourceBadge
            Text(model.t("advisor.inline.caption"))
                .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
            Spacer(minLength: Space.s)

            // Local only because Apple Intelligence is off → one tap to enable it.
            if !(selected?.advice.usedAI ?? false), StrategyGenerator.aiStatus == .notEnabled {
                Button(model.t("advisor.enableAI"), action: onEnableAI)
                    .buttonStyle(.plain).font(.sfCaption2.weight(.medium)).foregroundStyle(Theme.accent)
            }

            // "Why this?" — the decision path, on demand.
            if let sel = selected {
                Button { showWhy = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(model.t("advisor.inline.why"))
                .accessibilityLabel(model.t("advisor.inline.why"))
                .popover(isPresented: $showWhy, arrowEdge: .top) {
                    ScrollView {
                        DecisionPathView(steps: sel.advice.decisionPath,
                                         terminal: sel.advice.model.displayName)
                            .padding(Space.l)
                    }
                    .frame(width: 360).frame(maxHeight: 380)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(model.t("advisor.inline.dismiss"))
        }
    }

    /// "You chose {team} — here's what I'd recommend for this task." Frames the card
    /// as a comparison when the user already picked a team, rather than a blank pitch.
    private func chosenTeamRow(_ team: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.teal)
            Text(model.t("advisor.inline.youChose", team))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three cost/quality options as selectable chips (label + per-run cost).
    private var tierRow: some View {
        HStack(spacing: Space.xs) {
            ForEach(tiers) { tier in
                let on = tier.id == selectedID
                Button { onSelectTier(tier.id) } label: {
                    VStack(spacing: 1) {
                        Text(model.t(tier.labelKey))
                            .font(.sfCaption2.weight(.semibold))
                        // Tokens are the headline; the dollar figure rides in parens.
                        Text(tier.advice.estimatedCost.headline)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(on ? Theme.onAccent.opacity(0.9) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(on ? Theme.accent : Theme.hairline.opacity(0.5)))
                    .foregroundStyle(on ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(.primary))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.t(tier.noteKey))
            }
        }
    }

    /// The selected option's team + model + loop, with the apply actions.
    private func selectionRow(_ sel: AdvisorEngine.Tier) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: sel.advice.model.tierIcon)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(summary(sel)).font(.sfCallout).lineLimit(1).truncationMode(.tail)
                Text(model.t(sel.noteKey)).font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(summary(sel))
            Spacer(minLength: Space.s)
            Button(model.t(currentTeamName == nil ? "advisor.inline.applyTeam" : "advisor.inline.switchTeam"), action: onApplyTeam)
                .buttonStyle(.moon).controlSize(.small)
            // A loop is only offered when the engine actually found a repeat/verify
            // signal — for a plain turn-based chat it would be noise. "Apply team" is
            // then the single primary action.
            if sel.advice.loopKind != .turnBased {
                Button(model.t("advisor.inline.createLoop"), action: onCreateLoop)
                    .buttonStyle(.reefOutline).controlSize(.small)
            }
        }
    }

    /// The cross-provider mix for the selected tier — the flagship "best AI per role".
    /// Uses the real picks when ≥2 providers are connected; otherwise shows the IDEAL
    /// mix with the not-yet-connected providers dimmed + a one-tap connect nudge.
    @ViewBuilder private func providerMixRow(_ sel: AdvisorEngine.Tier) -> some View {
        let picks = displayPicks(sel)
        if !picks.isEmpty {
            let hasLocked = picks.contains { !$0.isConnected }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Space.m) {
                    ForEach(Array(picks.prefix(4)), id: \.self) { pick in
                        HStack(spacing: 4) {
                            Circle().fill(pick.provider.tint).frame(width: 7, height: 7)
                                .opacity(pick.isConnected ? 1 : 0.4)
                            Text(pick.roleName).font(.sfCaption2)
                                .foregroundStyle(pick.isConnected ? .primary : .secondary).lineLimit(1)
                            Text(pick.modelDisplayName).font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(1)
                            if !pick.isConnected {
                                Image(systemName: "lock.fill").font(.system(size: 7)).foregroundStyle(.tertiary)
                            }
                        }
                        .help(model.t(pick.reasonKey))
                    }
                    Spacer(minLength: 0)
                }
                if hasLocked {
                    Button { model.openConnectedServices() } label: {
                        Label(model.t("advisor.provider.connect"), systemImage: "link")
                            .font(.sfCaption2.weight(.medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Real picks when the run will actually mix providers; otherwise the aspirational
    /// (display-only) ideal mix, so the claim is visible even on a Claude-only setup.
    private func displayPicks(_ sel: AdvisorEngine.Tier) -> [AdvisorEngine.ProviderPick] {
        sel.advice.providerPicks.isEmpty
            ? AdvisorEngine.aspirationalPicks(for: sel.advice.strategy,
                                              connected: model.connectedProviders,
                                              bias: AdvisorEngine.TierBias.from(tierID: sel.id))
            : sel.advice.providerPicks
    }

    // MARK: - Bits

    /// Prominent, honest source: a filled coral "Apple Intelligence" pill vs a quiet
    /// "local engine" one, so it's obvious when the AI is driving the recommendation.
    private var sourceBadge: some View {
        let ai = selected?.advice.usedAI ?? false
        return Label(model.t(ai ? "advisor.source.ai.full" : "advisor.source.local.full"),
                     systemImage: ai ? "sparkles" : "cpu")
            .font(.sfCaption2.weight(.semibold))
            .foregroundStyle(ai ? Theme.onAccent : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(ai ? AnyShapeStyle(Theme.primaryFill) : AnyShapeStyle(Theme.inkDim.opacity(0.18))))
    }

    /// "Opus 4.8 · Domain Specialists · Turn-based" — the option, one line.
    private func summary(_ sel: AdvisorEngine.Tier) -> String {
        "\(sel.advice.model.displayName) · \(model.strategyDisplayName(sel.advice.strategy)) · \(model.t(sel.advice.loopKind.labelKey))"
    }
}
