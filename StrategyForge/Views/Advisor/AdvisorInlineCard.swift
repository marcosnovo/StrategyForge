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
    /// Chip hover cue (a tint, not motion) so it reads as an interactive control.
    @State private var chipHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // A simple, always-visible team strip that changes with the tier — no "See the
                // team" toggle needed (the roster also updates live in the Agents panel).
                if onGenerateImage == nil {
                    teamStrip(sel)
                    if sel.advice.loopKind != .turnBased { loopHintRow(sel) }
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

    /// The tier chip — a self-describing "Equipo: {tier} · {cost}" control so it's obvious it SETS
    /// the team level (founder: "no se entiende que sirve para establecer el tipo de equipo").
    private func tierChip(_ sel: AdvisorEngine.Tier) -> some View {
        Button { showTier = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.2.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(model.t("advisor.tier.chipPrefix")).font(.sfCaption2).foregroundStyle(.secondary)   // the NOUN
                Text(model.t(sel.labelKey)).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    .lineLimit(1).truncationMode(.tail)                                                  // the VALUE
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
            }
            // FIXED width so the chip never resizes as the tier name changes — that's what made
            // the popover jump left/right while dragging (founder). Constant width = stable anchor.
            .frame(width: 168)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Theme.accentSoft))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(chipHovering ? 0.55 : 0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { chipHovering = h } }
        .help(model.t("advisor.tier.title"))
        .accessibilityLabel(model.t("advisor.tier.a11y", model.t(sel.labelKey)))
        .popover(isPresented: $showTier, arrowEdge: .bottom) { tierPopover(sel) }
    }

    // MARK: - Tier popover (fixed-size; hero orb right; energy bar that brightens with the level)

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

    /// Instances in a tier's team (orchestrator + workers) — drives the little "team grows" row.
    private func teamSize(_ tier: AdvisorEngine.Tier) -> Int {
        max(1, tier.advice.strategy.roles.reduce(0) { $0 + max(1, $1.count) })
    }

    /// The bar's fill colour — a real INTENSITY ramp: dim, desaturated coral at tier 1 → vivid,
    /// full coral at tier 5. This is the "brighter/stronger as the team grows" cue.
    private func barColor(_ frac: Double) -> Color {
        Color(hue: 0.025,
              saturation: 0.45 + 0.55 * frac,
              brightness: 0.92 + 0.06 * frac)
    }

    private func tierPopover(_ sel: AdvisorEngine.Tier) -> some View {
        let idx = tierIndex(selectedID)
        let lastIndex = max(tiers.count - 1, 1)
        let frac = Double(idx) / Double(lastIndex)
        return HStack(spacing: Space.l) {
            // LEFT: the info, given room to breathe (founder: "muy junta, no se entiende").
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t("advisor.tier.title").uppercased())
                        .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.7).lineLimit(1)
                    Text(model.t(sel.labelKey))
                        .font(.sfDisplay).foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.7)
                }
                VStack(spacing: 5) {
                    modernBar(lastIndex: lastIndex, frac: frac)
                    HStack {
                        Text(model.t("advisor.tier.faster")).font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Text(model.t("advisor.tier.max")).font(.system(size: 10))
                            .foregroundStyle(idx == lastIndex ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    }
                }
                HStack(spacing: 6) {
                    Text(sel.advice.estimatedCost.headline)
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("·").foregroundStyle(.tertiary)
                    Text(model.t(sel.noteKey)).font(.sfCaption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                // Point to where the full roster lives — it updates live as you change the tier.
                Label(model.t("advisor.tier.seeInPanel"), systemImage: "arrow.right")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // RIGHT: the hero orb + a tiny team schematic — together they say "the team grows and
            // gets stronger" as you raise the level (founder's ask).
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                ThinkingOrb(state: orbState(forIndex: idx), size: 68, tint: Theme.accent)
                    .frame(width: 68, height: 68)
                    .scaleEffect(1.0 + 0.06 * frac)
                    .background {
                        Circle().fill(Theme.accentGlow.opacity(0.12 + 0.4 * frac))
                            .frame(width: 74, height: 74).blur(radius: 10)
                    }
                teamGrowRow(count: teamSize(sel))
                Spacer(minLength: 0)
            }
            .frame(width: 96)
        }
        .padding(Space.l)
        .frame(width: 340, height: 176)   // CONSTANT size — never resizes with tier or note length
        .onAppear { sliderPos = Double(idx) }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: idx)
    }

    /// A little roster of people icons that fills up (and brightens) with the tier — a compact,
    /// literal "the team grows" cue beside the orb. Capped at 6 slots.
    private func teamGrowRow(count: Int) -> some View {
        let slots = 6
        let filled = min(count, slots)
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<slots, id: \.self) { i in
                    Image(systemName: "person.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(i < filled ? Theme.accent : Theme.hairline)
                }
            }
            Text(model.t("advisor.tier.agents", count))
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    /// A ModernSlider-style bar (github.com/arjun-dureja/ModernSlider), Coral-tuned: a chunky
    /// rounded track, a white circular knob with a people glyph, and a FILL whose colour intensity
    /// + glow ramps up with the level. Smooth continuous drag; selection snaps to the nearest stop.
    private func modernBar(lastIndex: Int, frac: Double) -> some View {
        GeometryReader { g in
            let h: CGFloat = 26
            let cr: CGFloat = 13
            let knobR = h / 2
            let usable = g.size.width
            let travel = max(usable - h, 1)                  // knob centre range
            let live = CGFloat(sliderPos) / CGFloat(lastIndex)
            let cx = knobR + travel * live                   // knob centre x
            let fill = barColor(Double(live))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: cr, style: .continuous).fill(Theme.insetBg)
                    .overlay(RoundedRectangle(cornerRadius: cr, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                // The coral fill grows to the knob; its colour brightens + it glows more as it rises.
                RoundedRectangle(cornerRadius: cr, style: .continuous).fill(fill)
                    .frame(width: cx + knobR)
                    .shadow(color: Theme.accentGlow.opacity(0.35 + 0.65 * Double(live)), radius: 2 + 8 * live)
                    .mask(RoundedRectangle(cornerRadius: cr, style: .continuous))
                // The white knob with a people glyph (it's the TEAM dial).
                Circle().fill(.white)
                    .frame(width: h - 4, height: h - 4)
                    .overlay(Image(systemName: "person.2.fill")
                        .font(.system(size: (h - 4) / 2.4, weight: .semibold)).foregroundStyle(fill))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .position(x: cx, y: h / 2)
            }
            .frame(width: usable, height: h)
            .contentShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let f = min(max((v.location.x - knobR) / travel, 0), 1)
                    sliderPos = Double(f) * Double(lastIndex)
                    let id = tierID(at: Int(sliderPos.rounded()))
                    if id != selectedID { onSelectTier(id) }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        sliderPos = sliderPos.rounded()
                    }
                })
            .sensoryFeedback(.selection, trigger: selectedID)
        }
        .frame(height: 26)
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

    /// A simple, always-visible team strip on the LEFT of the card — one small chip per role
    /// (provider logo + role name), which changes live as the tier is raised so the user sees the
    /// team it will apply. Replaces the old "See the team" toggle (the full roster also updates in
    /// the Agents panel). Locked providers dim + a one-tap connect nudge.
    @ViewBuilder private func teamStrip(_ sel: AdvisorEngine.Tier) -> some View {
        let picks = displayPicks(sel)
        if !picks.isEmpty {
            let hasLocked = picks.contains { !$0.isConnected }
            HStack(spacing: 6) {
                ForEach(Array(picks.prefix(4)), id: \.self) { pick in
                    HStack(spacing: 4) {
                        ProviderLogo(provider: pick.provider, size: 12, templateTint: pick.provider.tint)
                        Text(pick.roleName).font(.sfCaption2).foregroundStyle(Theme.ink).lineLimit(1)
                    }
                    .opacity(pick.isConnected ? 1 : 0.5)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.insetBg))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                    .help(model.t(pick.reasonKey))
                }
                if picks.count > 4 {
                    Text("+\(picks.count - 4)").font(.sfCaption2.weight(.medium)).foregroundStyle(.secondary)
                }
                if hasLocked {
                    Button { model.openConnectedServices() } label: {
                        Image(systemName: "link").font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .help(model.t("advisor.provider.connect"))
                }
                Spacer(minLength: 0)
            }
        }
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
