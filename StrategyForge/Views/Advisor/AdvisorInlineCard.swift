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
    /// Set when the draft is a text-to-image request: the card then offers "Generate image"
    /// directly (a single-model job) instead of "Apply team", so image tasks don't pretend to
    /// need a fleet a coding CLI couldn't run anyway.
    var onGenerateImage: (() -> Void)? = nil
    /// When the chat already has a team the user deliberately chose, its name — so the
    /// card frames itself as "you chose X, here's what I'd recommend" instead of a
    /// blank suggestion. nil when the team is still auto.
    var currentTeamName: String? = nil

    @Environment(AppModel.self) private var model
    @State private var showWhy = false
    /// The compact tier picker popover (Claude-effort-style: smooth 5-stop dial + per-tier orb).
    @State private var showTier = false
    /// Continuous slider position (0…count-1) — smooth drag; the SELECTION snaps to the nearest.
    @State private var sliderPos: Double = 0
    /// Resting = one recommendation line + primary button; the visual agent roster lives behind
    /// "See the team" (founder: minimal, but the tier choice stays visible via the chip).
    @State private var showDetails = false

    private var selected: AdvisorEngine.Tier? {
        tiers.first { $0.id == selectedID } ?? tiers.first { $0.id == "balanced" } ?? tiers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            headerRow
            if let team = currentTeamName { chosenTeamRow(team) }
            if let sel = selected {
                // ONE compact line: the recommended pick + a small tier CHIP (name · cost) that
                // opens the Claude-style slider popover + the primary action. No fat chip row.
                recommendationRow(sel)
                // The team roster stays tucked behind a toggle (the detail, not the decision).
                if onGenerateImage == nil {
                    detailsToggle
                    if showDetails {
                        Divider().opacity(0.5)
                        agentCards(sel)
                        if sel.advice.loopKind != .turnBased { loopHintRow(sel) }
                    }
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Airy translucent glass so the composer's suggestion reads as a floating pane.
        .glassPanel(cornerRadius: Theme.innerCorner)
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
                Image(systemName: "xmark").scaledFont(9, weight: .semibold)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel(model.t("advisor.inline.dismiss"))
        }
    }

    /// "You chose {team} — here's what I'd recommend for this task." Frames the card
    /// as a comparison when the user already picked a team, rather than a blank pitch.
    private func chosenTeamRow(_ team: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.tealText)
            Text(model.t("advisor.inline.youChose", team))
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The recommendation on ONE line: model·team·loop + the tier chip (switcher) + the primary
    /// action. Compact — the three fat chips are gone; switching lives in the tier popover.
    private func recommendationRow(_ sel: AdvisorEngine.Tier) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: sel.advice.model.tierIcon)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(summary(sel)).font(.sfCallout).lineLimit(1).truncationMode(.tail)
                .help(summary(sel))
            Spacer(minLength: Space.s)
            // The switcher: a small chip showing the current tier NAME + cost (discoverable),
            // opening the compact slider. Hidden for a single-model / image task.
            if onGenerateImage == nil, tiers.count > 1 { tierChip(sel) }
            if let onGenerateImage {
                Button(model.t("images.generate"), action: onGenerateImage)
                    .buttonStyle(.moon).controlSize(.small)
            } else {
                Button(model.t(currentTeamName == nil ? "advisor.inline.applyTeam" : "advisor.inline.switchTeam"), action: onApplyTeam)
                    .buttonStyle(.moon).controlSize(.small)
            }
        }
    }

    /// The tier chip — now unmistakably a control: a bordered coral pill with a slider glyph, the
    /// current tier NAME + cost, and a chevron. (Founder: "no se entiende que se puede tocar ahí".)
    private func tierChip(_ sel: AdvisorEngine.Tier) -> some View {
        Button { showTier = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold))
                Text(model.t(sel.labelKey)).font(.sfCaption2.weight(.semibold))
                Text(sel.advice.estimatedCost.headline).font(.sfCaption2).foregroundStyle(Theme.accent.opacity(0.85))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accentSoft))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(model.t("advisor.tier.title"))
        .popover(isPresented: $showTier, arrowEdge: .bottom) { tierPopover(sel) }
    }

    // MARK: - Tier popover (smooth 5-stop dial, with a per-tier Coral orb)

    private func tierIndex(_ id: String) -> Int { max(0, tiers.firstIndex { $0.id == id } ?? 0) }
    private func tierID(at i: Int) -> String { tiers[min(max(i, 0), tiers.count - 1)].id }

    /// Each stop gets its own Coral thinking-orb, cheapest→strongest (founder's mapping):
    /// working · listening · searching · solving · connecting.
    private func orbState(forIndex i: Int) -> OrbState {
        switch i {
        case 0:  return .working
        case 1:  return .listening
        case 2:  return .searching
        case 3:  return .solving
        default: return .connecting
        }
    }

    private func tierPopover(_ sel: AdvisorEngine.Tier) -> some View {
        let idx = tierIndex(selectedID)
        let lastIndex = max(tiers.count - 1, 1)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                // A living Coral orb whose "mood" is the current tier — always present, per the
                // founder's per-state mapping. It IS the flourish now (no shimmer needed).
                ThinkingOrb(state: orbState(forIndex: idx), size: 30, tint: Theme.accent)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.t("advisor.tier.title")).font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
                    Text(model.t(sel.labelKey)).font(.sfCardTitle).foregroundStyle(Theme.accent)
                }
                Spacer()
            }
            HStack {
                Text(model.t("advisor.tier.faster")).font(.sfCaption2).foregroundStyle(.secondary)
                Spacer()
                Text(model.t("advisor.tier.max")).font(.sfCaption2)
                    .foregroundStyle(idx == lastIndex ? Theme.accent : .secondary)
            }
            // SMOOTH continuous slider (no step → glides), snapping the SELECTION to the nearest
            // of the 5 stops as you cross each midpoint. Tick dots mark the stops.
            Slider(value: $sliderPos, in: 0...Double(lastIndex))
                .tint(Theme.accent)
                .background(alignment: .center) { tickMarks(count: tiers.count) }
                .onChange(of: sliderPos) { _, v in
                    let id = tierID(at: Int(v.rounded()))
                    if id != selectedID { onSelectTier(id) }
                }
            // Live pick + cost + tradeoff, updates as you drag.
            Text("\(sel.advice.estimatedCost.headline) · \(model.t(sel.noteKey))")
                .font(.sfCaption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(width: 300)
        .onAppear { sliderPos = Double(idx) }
    }

    /// Faint dots under the slider marking the 5 discrete stops.
    private func tickMarks(count: Int) -> some View {
        GeometryReader { g in
            let inset: CGFloat = 10   // approx thumb radius so ticks sit under the stops
            let usable = max(g.size.width - inset * 2, 1)
            ForEach(0..<max(count, 1), id: \.self) { i in
                Circle().fill(Theme.hairline)
                    .frame(width: 3, height: 3)
                    .position(x: inset + usable * CGFloat(i) / CGFloat(max(count - 1, 1)),
                              y: g.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// A loop RECOMMENDATION — shown only when the engine read a repeat/verify signal
    /// in the prompt (goal / schedule / event). It explains, in plain words, how this
    /// task could run as a loop and offers to create it. For a plain turn-based chat it
    /// isn't shown, so "Apply team" stays the single primary action.
    @ViewBuilder private func loopHintRow(_ sel: AdvisorEngine.Tier) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.tealText)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.t("advisor.loop.hint.title")).font(.sfCaption2.weight(.semibold))
                Text(model.t("advisor.loop.hint.\(sel.advice.loopKind.rawValue)"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Button(model.t("advisor.inline.createLoop"), action: onCreateLoop)
                .buttonStyle(.reefOutline).controlSize(.small)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.tealSoft))
    }

    /// The quiet toggle that reveals the visual agent roster (the options themselves stay above,
    /// always visible). Labeled by what it shows so it's discoverable.
    private var detailsToggle: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { showDetails.toggle() } } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                Text(model.t(showDetails ? "advisor.inline.hideTeam" : "advisor.inline.showTeam"))
                Image(systemName: showDetails ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .font(.sfCaption2).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// The team as VISUAL cards — provider logo + role + model — instead of a dense text row.
    /// Uses the real picks when ≥2 providers are connected; otherwise the IDEAL mix, with the
    /// not-yet-connected providers dimmed + a one-tap connect nudge.
    @ViewBuilder private func agentCards(_ sel: AdvisorEngine.Tier) -> some View {
        let picks = displayPicks(sel)
        if !picks.isEmpty {
            let hasLocked = picks.contains { !$0.isConnected }
            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("advisor.inline.team"))
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)],
                          spacing: Space.s) {
                    ForEach(Array(picks.prefix(6)), id: \.self) { agentCard($0) }
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

    private func agentCard(_ pick: AdvisorEngine.ProviderPick) -> some View {
        HStack(spacing: 7) {
            ProviderLogo(provider: pick.provider, size: 15, templateTint: pick.provider.tint)
                .opacity(pick.isConnected ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(pick.roleName).font(.sfCaption2.weight(.medium))
                    .foregroundStyle(pick.isConnected ? Theme.ink : .secondary).lineLimit(1)
                Text(pick.modelDisplayName).scaledFont(9, design: .monospaced)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !pick.isConnected { Image(systemName: "lock.fill").scaledFont(7).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, Space.s).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous).fill(Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
        .help(model.t(pick.reasonKey))
    }

    /// Real picks when the run will actually mix providers; otherwise the aspirational
    /// (display-only) ideal mix, so the claim is visible even on a Claude-only setup.
    private func displayPicks(_ sel: AdvisorEngine.Tier) -> [AdvisorEngine.ProviderPick] {
        sel.advice.providerPicks.isEmpty
            ? AdvisorEngine.aspirationalPicks(for: sel.advice.strategy,
                                              connected: model.connectedProviders,
                                              bias: AdvisorEngine.TierBias.from(tierID: sel.id),
                                              modelLocked: model.modelLockedProviders)
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
