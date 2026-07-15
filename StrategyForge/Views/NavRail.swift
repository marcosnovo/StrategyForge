//
//  NavRail.swift
//  StrategyForge
//
//  The always-present left navigation sidebar (Aetheris-style): a light translucent
//  glass strip (200pt) with the brand wordmark, labeled icon rows (selected = a soft
//  coral pill + leading bar), and Settings pinned at the bottom. The container is an
//  `.ultraThinMaterial` so the aurora behind the window glows faintly through in both
//  light and dark appearance; text/icons use the dynamic Theme ink/secondary ramp.
//  The chat list remains a separate, section-conditional column beside it.
//

import SwiftUI

struct NavRail: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSidebar: Bool
    /// Drives the styled account popover (reference-style menu with icon rows).
    @State private var showAccountMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            brand

            newChatButton
            item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                 active: model.navSection == .chats,
                 running: !model.runningChatIDs.isEmpty || !model.attentionChatIDs.isEmpty) {
                model.guardedLeave {
                    model.navSection = .chats
                    if !showSidebar {
                        if reduceMotion { showSidebar = true }
                        else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                    }
                }
            }
            groupLabel("rail.group.workspace")

            item("chevron.left.forwardslash.chevron.right", "rail.code",
                 active: model.navSection == .code) {
                model.guardedLeave { model.navSection = .code }
            }
            item("person.3.sequence.fill", "rail.team",
                 active: model.navSection == .team) {
                model.navSection = .team
            }
            item("arrow.triangle.2.circlepath", "rail.loops",
                 active: model.navSection == .loops,
                 running: !LoopStore.shared.runningLoopIDs.isEmpty) {
                model.guardedLeave { model.navSection = .loops }
            }
            item("puzzlepiece.extension.fill", "rail.skills",
                 active: model.navSection == .skills) {
                model.guardedLeave { model.navSection = .skills }
            }
            groupLabel("rail.group.account")

            item("point.3.connected.trianglepath.dotted", "rail.connected",
                 active: model.navSection == .services) {
                model.guardedLeave { model.navSection = .services }
            }
            item("gauge.with.dots.needle.bottom.50percent", "rail.usage",
                 active: model.navSection == .usage) {
                model.guardedLeave {
                    model.navSection = .usage
                    Task { await model.refreshUsage(includeExact: true) }
                }
            }

            #if DEBUG
            // DEBUG-only: preview the dot/particle motion system (spinners + waits).
            devItem("sparkles", "Lab", active: model.navSection == .particleLab) {
                model.navSection = .particleLab
            }
            #endif

            Spacer(minLength: Space.m)

            item("gearshape.fill", "sidebar.settings", active: model.navSection == .settings) {
                model.guardedLeave { model.navSection = .settings }
            }
            // A coral dot signals a downloadable update (surfaced fully in Settings).
            .overlay(alignment: .topTrailing) {
                if model.availableUpdate != nil {
                    Circle().fill(Theme.coral)
                        .frame(width: 7, height: 7)
                        .offset(x: -6, y: 6)
                        .accessibilityLabel(model.t("settings.updates.badge"))
                }
            }
            usageCard
            profileRow
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, Space.m)
        .padding(.top, 34)          // clear the floating traffic lights (hidden titlebar)
        .padding(.bottom, Space.m)
        // Frosted glass rail: a thin translucent material lets the faint aurora
        // vibrancy show through more (closer to the reference), while the inner usage
        // and profile cards stay their own readable surfaces.
        .background(.ultraThinMaterial)
        // One spring cross-fades the selected pill between sections. Snaps under Reduce Motion.
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: model.navSection)
        // Pull Claude's REAL 5-hour / week rate-limit % into the rail card (the same
        // exact fetch the Usage page does), so it's visible without opening Usage.
        // `refreshExactUsage()` is gated to run at most once per session, so this is a
        // single deferred fetch (it may trigger a one-time macOS Keychain prompt).
        .task { await model.refreshUsage(includeExact: true) }
    }

    /// Brand row: the coral mark (matches the app icon, breathing slowly) + wordmark.
    private var brand: some View {
        HStack(spacing: Space.s) {
            CoralMark(size: 24, color: Theme.coral)
                .breathingGlow(color: Theme.coral)
            Text("Coral")
                .font(.sfMono)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
    }

    /// The "New chat" affordance: a friendly rounded glass pill with a coral icon and
    /// an ink label, set apart from the plain nav rows above the section list.
    private var newChatButton: some View {
        Button {
            model.guardedLeave {
                model.navSection = .chats
                model.addConfiguration()
            }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                Text(model.t("sidebar.new"))
                    .font(.sfBodyM.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(height: 34)
            .glassPanel(cornerRadius: Theme.buttonCorner, material: .thinMaterial)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t("sidebar.new"))
        .accessibilityLabel(model.t("sidebar.new"))
    }

    /// A labeled sidebar row: leading icon + label, a full-width rounded pill fill +
    /// leading bar when active, and a trailing running-pulse when a non-active section
    /// has work in flight. On the light glass rail text uses the Theme ink/secondary
    /// ramp and the active accent is coral.
    private func item(_ icon: String, _ labelKey: String,
                      active: Bool = false, running: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(icon: icon, label: model.t(labelKey), active: active, running: running)
        }
        .buttonStyle(.plain)
        .help(model.t(labelKey))
        .accessibilityLabel(model.t(labelKey))
    }

    /// A muted uppercase group divider label (reference-style nav grouping).
    private func groupLabel(_ key: String) -> some View {
        Text(model.t(key).uppercased())
            .font(.sfFieldLabel)
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryOnMaterial)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, 2)
    }

    /// Shared row chrome (used by `item` and the DEBUG `devItem`).
    private func rowBody(icon: String, label: String, active: Bool, running: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(active ? Theme.accent : Theme.secondaryOnMaterial)
                .frame(width: 22)
            Text(label)
                .font(.sfBodyM.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.accent : Theme.secondaryOnMaterial)
                .lineLimit(1)
            Spacer(minLength: 0)
            if running && !active { RunningPulseDot() }
        }
        .padding(.horizontal, Space.m)
        .frame(height: 34)
        // A soft coral wash hugs the active row (tight radius, no hard border) with a
        // short coral leading bar as the single strong accent cue.
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            .fill(active ? Theme.accentSoft : .clear))
        .overlay(alignment: .leading) {
            if active {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 16)
            }
        }
        .hoverTint(cornerRadius: Theme.rowCorner)
        .contentShape(Rectangle())   // whole row is tappable
    }

    // MARK: Usage card (one row per connected provider)

    /// A compact usage card with ONE row per connected provider — each a single-color
    /// ring + bars. Claude publishes no token cap, so its ring is the 5-hour window's
    /// time-to-reset and its two bars are this week's / this block's tokens; Codex
    /// reports a real plan %, so its ring + bar show that exact percentage.
    @ViewBuilder private var usageCard: some View {
        let rows = usageProviders
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(rows, id: \.self) { providerUsageRow($0) }
                Button {
                    model.guardedLeave {
                        model.navSection = .usage
                        Task { await model.refreshUsage(includeExact: true) }
                    }
                } label: {
                    Text(model.t("rail.usage.view")).font(.sfCaption2.weight(.medium))
                        .foregroundStyle(Theme.teal)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Neutral card ground + hairline — no colored gradient behind the numbers.
            // Only the ring/bar STROKES carry teal, so the data reads with clean contrast.
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    /// Connected providers that actually have usage to show, in catalog order.
    private var usageProviders: [AIProvider] {
        AIProvider.allCases.filter { p in
            switch p {
            case .claude: return model.claudeUsage?.hasData == true || model.claudeExact != nil
            case .openai: return model.codexUsage?.hasData == true
            case .gemini: return false   // Gemini exposes no reliable local usage
            }
        }
    }

    @ViewBuilder private func providerUsageRow(_ provider: AIProvider) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            switch provider {
            case .claude:
                if let e = model.claudeExact {
                    // The REAL rate-limit % from Claude's endpoint (5-hour + week).
                    miniRing(fraction: e.fiveHourPercent / 100,
                             center: "\(Int(e.fiveHourPercent.rounded()))%", caption: model.t("rail.usage.5h"))
                    VStack(alignment: .leading, spacing: 4) {
                        providerLabel(provider, right: model.providerPlan(.claude))
                        miniBar(model.t("rail.usage.wk"), fraction: e.weekPercent / 100,
                                value: "\(Int(e.weekPercent.rounded()))%")
                    }
                } else if let u = model.claudeUsage {
                    // Signed out / no exact data yet → ring = 5-hour time-to-reset, bars =
                    // each model's share of the week (a real %).
                    miniRing(fraction: blockFraction(u), center: resetLabel(u), caption: model.t("rail.usage.5h"))
                    VStack(alignment: .leading, spacing: 4) {
                        providerLabel(provider, right: model.providerPlan(.claude))
                        let wk = max(u.weekTokens, 1)
                        ForEach(Array(u.weekByModel.prefix(3))) { m in
                            let f = Double(m.tokens) / Double(wk)
                            miniBar(m.model, fraction: f, value: "\(Int((f * 100).rounded()))%")
                        }
                    }
                }
            case .openai:
                if let c = model.codexUsage, let w = c.primary ?? c.secondary {
                    // Codex reports the real plan % server-side.
                    miniRing(fraction: w.usedPercent / 100, center: "\(Int(w.usedPercent.rounded()))%",
                             caption: model.t("rail.usage.codexCaption"))
                    VStack(alignment: .leading, spacing: 4) {
                        providerLabel(provider, right: c.planType?.capitalized)
                        miniBar(model.t(w.kindLabelKey), fraction: w.usedPercent / 100,
                                value: "\(Int(w.usedPercent.rounded()))%")
                    }
                }
            case .gemini:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
    }

    private func providerLabel(_ p: AIProvider, right: String?) -> some View {
        HStack(spacing: 5) {
            Text(p.displayName).font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: 0)
            if let right, !right.isEmpty {
                Text(right).font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.secondaryOnMaterial)
            }
        }
    }

    /// A single-color usage ring (no confusing two-tone gradient) with a centered label
    /// and a small caption underneath so it's clear WHAT the ring measures.
    private func miniRing(fraction: Double, center: String, caption: String) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 3.5)
                Circle().trim(from: 0, to: max(0.02, min(fraction, 1)))
                    .stroke(Theme.teal, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(center).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
            }
            .frame(width: 34, height: 34)
            Text(caption).font(.system(size: 7, weight: .semibold)).tracking(0.4)
                .foregroundStyle(Theme.secondaryOnMaterial)
        }
    }

    private func miniBar(_ label: String, fraction: Double, value: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 8, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(Theme.secondaryOnMaterial)
                Spacer(minLength: 0)
                Text(value).font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.secondaryOnMaterial)
            }
            GeometryReader { geo in
                Capsule().fill(Theme.hairline)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.teal)
                            .frame(width: max(3, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                    }
            }
            .frame(height: 3)
        }
    }

    /// The elapsed fraction of the current 5-hour block (0…1) for the ring.
    private func blockFraction(_ u: UsageSummary) -> Double {
        guard let s = u.blockStart, let r = u.blockResetAt, r > s else { return 0 }
        return min(max(Date().timeIntervalSince(s) / r.timeIntervalSince(s), 0), 1)
    }

    /// Compact time-to-reset for the ring center ("2h" / "45m" / "—").
    private func resetLabel(_ u: UsageSummary) -> String {
        guard let r = u.blockResetAt else { return "—" }
        let secs = Int(r.timeIntervalSince(Date()))
        guard secs > 0 else { return "—" }
        return secs >= 3600 ? "\(secs / 3600)h" : "\(max(1, secs / 60))m"
    }

    /// Compact token count ("24.5k", "310k", "980").
    private func fmtTokens(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }

    // MARK: Profile row

    /// The bottom user-profile row: identity + a menu (Settings / Sync / Sign out) when
    /// signed in, or a "Sign in" affordance (identity only gates iCloud sync) otherwise.
    @ViewBuilder private var profileRow: some View {
        if let acc = auth.account {
            Button { showAccountMenu.toggle() } label: {
                profileCard(avatar: avatarCircle(initials(acc.label)),
                            title: acc.label, sub: acc.email,
                            trailingIcon: "chevron.down")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAccountMenu, arrowEdge: .bottom) { accountMenu }
        } else {
            Button { model.navSection = .settings } label: {
                profileCard(avatar: signInAvatar,
                            title: model.t("rail.profile.signin"),
                            sub: model.t("rail.profile.signin.sub"),
                            trailingIcon: nil)
            }
            .buttonStyle(.plain)
        }
    }

    /// The account dropdown, styled like the reference: a soft frosted card of icon
    /// rows, with a coral "Sign out" set apart under a divider.
    private var accountMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Settings lives in the rail already, so it's not repeated here.
            if auth.canSync {
                accountMenuRow("arrow.triangle.2.circlepath", "rail.profile.sync") {
                    Task { await auth.sync(model) }
                }
                Divider().padding(.horizontal, Space.s).padding(.vertical, 5)
            }
            accountMenuRow("rectangle.portrait.and.arrow.right", "rail.profile.signout",
                           destructive: true) { auth.signOut() }
        }
        .padding(Space.xs)
        .frame(width: 214)
    }

    private func accountMenuRow(_ icon: String, _ key: String,
                                destructive: Bool = false,
                                action: @escaping () -> Void) -> some View {
        Button {
            showAccountMenu = false
            action()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(destructive ? Theme.danger : Theme.secondaryOnMaterial)
                    .frame(width: 20)
                Text(model.t(key))
                    .font(.sfBodyM)
                    .foregroundStyle(destructive ? Theme.danger : Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTint(cornerRadius: Theme.rowCorner)
    }

    /// A distinct profile card (reference "Sophia · Pro Plan" style): a solid, softly
    /// elevated light card — avatar + name + plan/email + a chevron — so it reads
    /// clearly as its own element at the foot of the translucent rail (a faint frosted
    /// patch got lost against the glass).
    private func profileCard(avatar: some View, title: String, sub: String?,
                             trailingIcon: String?) -> some View {
        HStack(spacing: Space.s) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.sfBodyM.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                if let sub, !sub.isEmpty {
                    Text(sub).font(.sfCaption2).foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryOnMaterial)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 10)
        // A solid, elevated card — clearly defined against the frosted rail.
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.cardBg)
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .padding(.top, Space.xs)
        .contentShape(Rectangle())
    }

    /// Solid coral avatar with white initials — a clear, high-contrast identity chip
    /// (the old accentSoft-on-coral read too faint).
    private func avatarCircle(_ initials: String) -> some View {
        Circle().fill(Theme.primaryFill).frame(width: 34, height: 34)
            .overlay(Text(initials)
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white))
            .shadow(color: Theme.accentGlow, radius: 4, y: 1)
    }

    private var signInAvatar: some View {
        Circle().fill(Theme.primaryFill).frame(width: 34, height: 34)
            .overlay(Image(systemName: "person.fill")
                .font(.system(size: 14)).foregroundStyle(.white))
            .shadow(color: Theme.accentGlow, radius: 4, y: 1)
    }

    private func initials(_ s: String) -> String {
        let words = s.split(separator: " ")
        if words.count >= 2 { return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased() }
        return String(s.prefix(2)).uppercased()
    }

    #if DEBUG
    /// Like `item`, but with a literal (un-localized) label — for DEBUG-only tools.
    private func devItem(_ icon: String, _ label: String,
                         active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(icon: icon, label: label, active: active, running: false)
        }
        .buttonStyle(.plain)
        .help("Particle Lab (DEBUG)")
    }
    #endif
}

/// The rail's "work in flight elsewhere" indicator: a 4pt coral dot with a slow
/// opacity pulse (static under Reduce Motion).
private struct RunningPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.teal)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion ? 1 : (dim ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
            .accessibilityHidden(true)
    }
}
