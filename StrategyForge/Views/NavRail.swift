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
    /// Advanced destinations (Loops / Skills / Usage) collapse by default so a first-run
    /// rail is just Chats · Code · Team + account — power stays one disclosure away.
    @AppStorage("nav.showAdvanced") private var showAdvanced = false
    /// Live design-system selection (the swatch picker below Lab).
    @State private var theme = ThemeStore.shared

    var body: some View {
        // ChatGPT-calm: a narrow ICON rail (64pt). Labels live in tooltips (.help), so the
        // rail stops being a second text column and the conversation becomes the protagonist.
        // Destinations scroll if the window is short; theme/settings/avatar pin at the foot.
        VStack(spacing: Space.xs) {
            brand
            newChatButton

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Space.xs) {
                    item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                         active: model.navSection == .chats,
                         running: !model.runningChatIDs.isEmpty || !model.attentionChatIDs.isEmpty) {
                        model.guardedLeave {
                            model.navSection = .chats
                            toggleSidebar()          // the Chats icon reveals / hides the list
                        }
                    }

                    railDivider

                    item("person.3.sequence.fill", "rail.team", active: model.navSection == .team) {
                        model.guardedLeave { model.navSection = .team }
                    }
                    item("chevron.left.forwardslash.chevron.right", "rail.code", active: model.navSection == .code) {
                        model.guardedLeave { model.navSection = .code }
                    }
                    item("flag.checkered", "rail.arena", active: model.navSection == .arena) {
                        model.guardedLeave { model.navSection = .arena }
                    }
                    item("brain", "rail.memory", active: model.navSection == .memory) {
                        model.guardedLeave { model.navSection = .memory }
                    }
                    item("arrow.triangle.2.circlepath", "rail.loops",
                         active: model.navSection == .loops,
                         running: !LoopStore.shared.runningLoopIDs.isEmpty) {
                        model.guardedLeave { model.navSection = .loops }
                    }
                    item("puzzlepiece.extension.fill", "rail.skills", active: model.navSection == .skills) {
                        model.guardedLeave { model.navSection = .skills }
                    }
                    item("gauge.with.dots.needle.bottom.50percent", "rail.usage", active: model.navSection == .usage) {
                        model.guardedLeave {
                            model.navSection = .usage
                            Task { await model.refreshUsage(includeExact: true) }
                        }
                    }

                    railDivider

                    item("point.3.connected.trianglepath.dotted", "rail.connected", active: model.navSection == .services) {
                        model.guardedLeave { model.navSection = .services }
                    }

                    #if DEBUG
                    devItem("sparkles", "Lab", active: model.navSection == .particleLab) {
                        model.navSection = .particleLab
                    }
                    #endif
                }
                .padding(.vertical, Space.xs)
            }

            themePicker

            item("gearshape.fill", "sidebar.settings", active: model.navSection == .settings) {
                model.guardedLeave { model.navSection = .settings }
            }
            .overlay(alignment: .topTrailing) {
                if model.availableUpdate != nil {
                    Circle().fill(Theme.coral)
                        .frame(width: 7, height: 7)
                        .offset(x: -6, y: 6)
                        .accessibilityLabel(model.t("settings.updates.badge"))
                }
            }
            profileRow
        }
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, Space.s)
        .padding(.top, 34)          // clear the floating traffic lights (hidden titlebar)
        .padding(.bottom, Space.m)
        // The rail uses the native macOS `.sidebar` vibrancy so it reads as a true sidebar,
        // distinct from the content columns (chat list / activity panel), which stay on
        // `translucentColumn`. This is the "rail ≠ content" separation (design review D5).
        .railColumn()
        // One spring cross-fades the selected pill between sections. Snaps under Reduce Motion.
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: model.navSection)
        // Populate the rail's usage card from LOCAL logs only — no Keychain read, so the
        // app never prompts for the Keychain password at launch (a debug build's ad-hoc
        // signature means "Always Allow" doesn't stick, so it would ask every time). The
        // exact 5-hour / week rate-limit % (which needs the Keychain token) is fetched
        // only on deliberate intent — when the user opens the Usage section.
        .task { await model.refreshUsage() }
    }

    /// Live design-system switcher — a menu of the four visual directions, each with a
    /// brand-coral swatch; picking one re-skins the whole app instantly.
    private var themePicker: some View {
        Menu {
            Section(model.t("rail.theme")) {
                ForEach(DesignSystem.allCases) { ds in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { theme.active = ds }
                    } label: {
                        if theme.active == ds { Label(ds.displayName, systemImage: "checkmark") }
                        else { Text(ds.displayName) }
                    }
                }
            }
            Section(model.t("appearance.title")) {
                ForEach(AppAppearance.allCases) { ap in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { theme.appearance = ap }
                    } label: {
                        if theme.appearance == ap { Label(model.t(ap.labelKey), systemImage: "checkmark") }
                        else { Text(model.t(ap.labelKey)) }
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondaryOnMaterial)
                .frame(width: 40, height: 34)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(theme.active.palette.coral).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                        .offset(x: -6, y: -5)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 40)
        .help(model.t("rail.theme"))
        .accessibilityLabel(model.t("rail.theme"))
    }

    /// Brand mark: just the coral glyph (matches the app icon) — the wordmark is dropped
    /// on the narrow icon rail.
    private var brand: some View {
        CoralMark(size: 26, color: Theme.coral)
            .frame(width: 40, height: 36)
            .padding(.bottom, Space.xs)
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
            Image(systemName: "square.and.pencil")
                .font(.system(size: 16))
                .foregroundStyle(Theme.coral)
                .frame(width: 40, height: 34)
                .glassPanel(cornerRadius: Theme.buttonCorner)
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
    /// A tappable group header that expands/collapses the Advanced section.
    private func advancedHeader(expanded: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showAdvanced.toggle() }
        } label: {
            HStack(spacing: Space.xs) {
                Text(model.t("rail.group.advanced").uppercased())
                    .font(.sfFieldLabel).tracking(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.secondaryOnMaterial)
            .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.t("rail.group.advanced"))
        .accessibilityValue(expanded ? model.t("common.expanded") : model.t("common.collapsed"))
    }

    /// Toggle the chat-list column open/closed (the Chats icon is now the reveal gesture).
    private func toggleSidebar() {
        if reduceMotion { showSidebar.toggle() }
        else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() } }
    }

    /// A short hairline rule that groups the icon rail into sections.
    private var railDivider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 24, height: 1)
            .padding(.vertical, 2)
    }

    /// Shared row chrome (used by `item` and the DEBUG `devItem`): a centered icon in a
    /// square tap target, with a soft coral pill + coral tint when active and a running
    /// pulse dot in the corner. The label rides in the tooltip (`.help`), not on the rail.
    private func rowBody(icon: String, label: String, active: Bool, running: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 17))
            .foregroundStyle(active ? Theme.coral : Theme.secondaryOnMaterial)
            .frame(width: 40, height: 34)
            .background(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                .fill(active ? Theme.accentSoft : .clear))
            .overlay(alignment: .topTrailing) {
                if running && !active { RunningPulseDot().offset(x: -3, y: 3) }
            }
            .hoverTint(cornerRadius: Theme.rowCorner)
            .contentShape(Rectangle())
    }


    // MARK: Profile row

    /// The bottom user-profile row: identity + a menu (Settings / Sync / Sign out) when
    /// signed in, or a "Sign in" affordance (identity only gates iCloud sync) otherwise.
    @ViewBuilder private var profileRow: some View {
        if let acc = auth.account {
            Button { showAccountMenu.toggle() } label: {
                avatarCircle(initials(acc.label))
            }
            .buttonStyle(.plain)
            .help(acc.label)
            .popover(isPresented: $showAccountMenu, arrowEdge: .trailing) { accountMenu }
            .padding(.top, Space.xs)
        } else {
            Button { model.navSection = .settings } label: {
                signInAvatar
            }
            .buttonStyle(.plain)
            .help(model.t("rail.profile.signin"))
            .padding(.top, Space.xs)
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

/// The rail's "work in flight elsewhere" indicator: a small teal dot (teal = the
/// team is live) with a slow opacity pulse (static under Reduce Motion).
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
