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
    /// "Spotlight dock": one moving beam that slides to whichever section is active, so the
    /// selection reads as a light being aimed — not a static pill (the founder's reference).
    @Namespace private var spotlightNS
    /// Advanced destinations (Loops / Skills / Usage) collapse by default so a first-run
    /// rail is just Chats · Code · Team + account — power stays one disclosure away.
    /// The rail can EXPAND to a labeled sidebar or stay a minimal icon strip (persisted).
    @AppStorage("nav.railExpanded") private var railExpanded = false
    /// Live design-system selection (the swatch picker below Lab).
    @State private var theme = ThemeStore.shared

    private var railWidth: CGFloat { railExpanded ? 208 : 76 }

    /// The power-tools group under "More" is collapsed by default (persisted).
    @AppStorage("nav.showMore") private var showMore = false
    /// Sections that live under "More" — used to auto-open the group when one is active.
    private var moreSectionActive: Bool {
        [.team, .loops, .memory, .skills, .usage, .services].contains(model.navSection)
    }
    private var moreShown: Bool { showMore || moreSectionActive }

    var body: some View {
        // ChatGPT-calm: a narrow ICON rail (64pt). Labels live in tooltips (.help), so the
        // rail stops being a second text column and the conversation becomes the protagonist.
        // Destinations scroll if the window is short; theme/settings/avatar pin at the foot.
        VStack(spacing: Space.xs) {
            brand
            newChatButton

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Space.xs) {
                    // IA (grouped by intent, per the founder's rail redesign): WORK (where you
                    // do the work), COMPARE (pit teams/models), and MORE (power tools + setup,
                    // behind a disclosure). Section headers show only when the rail is expanded;
                    // collapsed, a hairline divider separates the groups.
                    railSection("rail.section.work")
                    item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                         active: model.navSection == .chats,
                         running: !model.runningChatIDs.isEmpty || !model.attentionChatIDs.isEmpty) {
                        model.guardedLeave {
                            model.navSection = .chats
                            // Rail = "where am I" (reveal the list); the chat HEADER's toggle is
                            // the single place that hides it.
                            if reduceMotion { showSidebar = true }
                            else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                        }
                    }
                    item("chevron.left.forwardslash.chevron.right", "rail.code", active: model.navSection == .code) {
                        model.guardedLeave { model.navSection = .code }
                    }
                    item("circle.hexagongrid.fill", "rail.map", active: model.navSection == .map) {
                        model.guardedLeave { model.navSection = .map }
                    }

                    railSection("rail.section.compare")
                    item("flag.checkered", "rail.arena", active: model.navSection == .arena) {
                        model.guardedLeave { model.navSection = .arena }
                    }

                    railDivider

                    // POWER TOOLS + setup, behind one disclosure so the resting rail stays
                    // scannable. Auto-expands when one of its sections is active.
                    moreTile
                    if moreShown {
                        item("person.3.sequence.fill", "rail.team", active: model.navSection == .team) {
                            model.guardedLeave { model.navSection = .team }
                        }
                        item("arrow.triangle.2.circlepath", "rail.loops",
                             active: model.navSection == .loops,
                             running: !LoopStore.shared.runningLoopIDs.isEmpty) {
                            model.guardedLeave { model.navSection = .loops }
                        }
                        item("brain", "rail.memory", active: model.navSection == .memory) {
                            model.guardedLeave { model.navSection = .memory }
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
                        item("point.3.connected.trianglepath.dotted", "rail.connected", active: model.navSection == .services) {
                            model.guardedLeave { model.navSection = .services }
                        }
                    }

                    #if DEBUG
                    devItem("sparkles", "Lab", active: model.navSection == .particleLab) {
                        model.navSection = .particleLab
                    }
                    #endif
                }
                .padding(.vertical, Space.xs)
            }

            // Ambient Claude rate-limit % at the rail foot ("como antes"): glanceable while
            // you work anywhere in the app, cache-backed (no Keychain touch here — the rail's
            // .task refreshes local/cached only), tap → Usage. Hidden until the % is known.
            ClaudeUsagePill(style: .tile)

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
            railToggle
            profileRow
        }
        .frame(width: railWidth)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, Space.s)
        .padding(.top, 34)          // clear the floating traffic lights (hidden titlebar)
        .padding(.bottom, Space.m)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: railExpanded)
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
            HStack(spacing: Space.s) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryOnMaterial)
                    .frame(width: 40, height: 34)
                    .overlay(alignment: .bottomTrailing) {
                        if !railExpanded {
                            Circle().fill(theme.active.palette.coral).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                                .offset(x: -6, y: -5)
                        }
                    }
                if railExpanded {
                    Text(theme.active.displayName).font(.sfCaption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1)
                    Spacer(minLength: 0)
                    Circle().fill(theme.active.palette.coral).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                }
            }
            .padding(.trailing, railExpanded ? Space.s : 0)
            .frame(maxWidth: railExpanded ? .infinity : 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help(model.t("rail.theme"))
        .accessibilityLabel(model.t("rail.theme"))
    }

    /// Brand mark: just the coral glyph (matches the app icon) — the wordmark is dropped
    /// on the narrow icon rail.
    private var brand: some View {
        HStack(spacing: Space.s) {
            CoralMark(size: 26, color: Theme.coral)
                .frame(width: 40, height: 36)
            if railExpanded {
                Text("Coral").font(.sfMono).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: railExpanded ? .infinity : 40, alignment: .leading)
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
            Group {
                if railExpanded {
                    HStack(spacing: Space.s) {
                        Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.coral)
                            .frame(width: 40, height: 34)
                        Text(model.t("sidebar.new")).font(.sfBodyM.weight(.medium)).foregroundStyle(Theme.coral)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 1) {
                        Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.coral)
                            .frame(width: 40, height: 30)
                        Text(model.t("sidebar.newShort")).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.coral).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
            }
            // No raised glass pill — "Nuevo" is a flat, coral create action (marked by colour,
            // not a white floating block that stacked as a second heavy slab above Chats).
            .hoverTint(cornerRadius: Theme.rowCorner)
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

    /// A group header: an uppercase caption when the rail is expanded, a hairline when it's
    /// the narrow icon strip (headers would just be noise there).
    @ViewBuilder
    private func railSection(_ key: String) -> some View {
        if railExpanded {
            Text(model.t(key))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.s).padding(.top, Space.xs).padding(.bottom, 1)
        } else {
            railDivider
        }
    }

    /// A short hairline rule that groups the icon rail into sections.
    private var railDivider: some View {
        Rectangle().fill(Theme.hairline)
            .frame(width: railExpanded ? nil : 24, height: 1)
            .frame(maxWidth: railExpanded ? .infinity : 24)
            .padding(.vertical, 2)
    }

    /// Shared row chrome (used by `item` and the DEBUG `devItem`). EXPANDED → icon + label
    /// in a row. COLLAPSED → icon with a small label BELOW it, so every destination is legible
    /// at a glance (an icon-only rail left "what is this?" to a hover tooltip). Soft coral pill
    /// + coral tint when active; a running pulse dot on the icon.
    private func rowBody(icon: String, label: String, active: Bool, running: Bool) -> some View {
        // Active is marked calmly (Apple/Raycast/Linear): the ICON carries the coral accent,
        // the label stays NEUTRAL (just darker), the background is a WHISPER of coral (not the
        // old saturated slab), and a crisp coral leading bar says "you are here" in the row
        // layout. One accent carrier, not three — the founder's "Chats too highlighted" fix.
        let iconTint = active ? Theme.coral : Theme.secondaryOnMaterial
        let labelTint = active ? Theme.ink : Theme.secondaryOnMaterial
        let iconView = Image(systemName: icon)
            .font(.system(size: 17))
            .foregroundStyle(iconTint)
            .frame(width: 40, height: 30)
            .overlay(alignment: .topTrailing) {
                if running && !active { RunningPulseDot().offset(x: -3, y: 3) }
            }
        return Group {
            if railExpanded {
                HStack(spacing: Space.s) {
                    iconView
                    Text(label).font(.sfBodyM.weight(active ? .medium : .regular))
                        .foregroundStyle(labelTint).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 1) {
                    iconView
                    Text(label).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(labelTint)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
        }
        .background {
            if active {
                // Expanded → the calm coral pill + leading bar (a text list wants a quiet
                // marker). Collapsed icon rail → the SPOTLIGHT beam, which slides between
                // rows via matchedGeometry so the selection reads as "aim the light".
                if railExpanded {
                    RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                        .fill(Theme.coral.opacity(0.09))
                        .matchedGeometryEffect(id: "spotlight", in: spotlightNS)
                } else {
                    SpotlightBeam(tint: Theme.coral)
                        .matchedGeometryEffect(id: "spotlight", in: spotlightNS)
                }
            }
        }
        .overlay(alignment: .leading) {
            if active && railExpanded {
                Capsule().fill(Theme.coral).frame(width: 3, height: 18).padding(.leading, 1)
            }
        }
        .hoverTint(cornerRadius: Theme.rowCorner)
        .contentShape(Rectangle())
    }

    /// The "More" disclosure tile: reveals the power-tools group (Loops / Memory / Skills /
    /// Usage / Connections). Mirrors an `item` row; a running pulse rides the collapsed tile
    /// when a hidden loop is live (so a background run's signal is never buried).
    private var moreTile: some View {
        let hiddenRunning = !moreShown && !LoopStore.shared.runningLoopIDs.isEmpty
        let icon = moreShown ? "chevron.up" : "ellipsis"
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showMore.toggle() }
        } label: {
            let iconView = Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryOnMaterial)
                .frame(width: 40, height: 30)
                .overlay(alignment: .topTrailing) { if hiddenRunning { RunningPulseDot().offset(x: -3, y: 3) } }
            Group {
                if railExpanded {
                    HStack(spacing: Space.s) {
                        iconView
                        Text(model.t("rail.more")).font(.sfBodyM).foregroundStyle(Theme.secondaryOnMaterial)
                        Spacer(minLength: 0)
                        Image(systemName: moreShown ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.trailing, Space.s).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 1) {
                        iconView
                        Text(model.t("rail.more")).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 3)
                }
            }
            .hoverTint(cornerRadius: Theme.rowCorner)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t("rail.more"))
        .accessibilityLabel(model.t("rail.more"))
    }

    /// Expand / collapse the rail between a labeled sidebar and the icon strip.
    private var railToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { railExpanded.toggle() }
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: railExpanded ? "chevron.left.2" : "chevron.right.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryOnMaterial)
                    .frame(width: 40, height: 30)
                if railExpanded {
                    Text(model.t("rail.collapse")).font(.sfCaption2.weight(.medium))
                        .foregroundStyle(Theme.secondaryOnMaterial)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: railExpanded ? .infinity : 40, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTint(cornerRadius: Theme.rowCorner)
        .help(model.t(railExpanded ? "rail.collapse" : "rail.expand"))
        .accessibilityLabel(model.t(railExpanded ? "rail.collapse" : "rail.expand"))
    }


    // MARK: Profile row

    /// The bottom user-profile row: identity + a menu (Settings / Sync / Sign out) when
    /// signed in, or a "Sign in" affordance (identity only gates iCloud sync) otherwise.
    @ViewBuilder private var profileRow: some View {
        if let acc = auth.account {
            Button { showAccountMenu.toggle() } label: {
                profileLabel(avatar: avatarCircle(initials(acc.label)), title: acc.label)
            }
            .buttonStyle(.plain)
            .help(acc.label)
            .popover(isPresented: $showAccountMenu, arrowEdge: .trailing) { accountMenu }
            .padding(.top, Space.xs)
        } else {
            Button { model.navSection = .settings } label: {
                profileLabel(avatar: signInAvatar, title: model.t("rail.profile.signin"))
            }
            .buttonStyle(.plain)
            .help(model.t("rail.profile.signin"))
            .padding(.top, Space.xs)
        }
    }

    /// Avatar alone (collapsed) or avatar + name (expanded).
    private func profileLabel(avatar: some View, title: String) -> some View {
        HStack(spacing: Space.s) {
            avatar
            if railExpanded {
                Text(title).font(.sfBodyM.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: railExpanded ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
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

/// A "spotlight" behind the active icon-rail row: a lamp cap up top, a soft cone widening
/// down onto the icon, and a warm pool of light — so the selected section looks lit, not
/// boxed. Slid between rows by the caller's matchedGeometry. Purely decorative.
private struct SpotlightBeam: View {
    var tint: Color = Theme.coral
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // The cone: narrow at the lamp (top), widening onto the icon (down).
                Path { p in
                    p.move(to: CGPoint(x: w * 0.5 - 4, y: 2))
                    p.addLine(to: CGPoint(x: w * 0.5 + 4, y: 2))
                    p.addLine(to: CGPoint(x: w * 0.84, y: h))
                    p.addLine(to: CGPoint(x: w * 0.16, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.42), tint.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                .blur(radius: 3)
                // Pool of light where the icon sits.
                Ellipse().fill(tint.opacity(0.20))
                    .frame(width: w * 0.66, height: h * 0.5)
                    .position(x: w * 0.5, y: h * 0.55)
                    .blur(radius: 6)
                // The lamp cap.
                Capsule().fill(tint.opacity(0.9))
                    .frame(width: 10, height: 3)
                    .position(x: w * 0.5, y: 2)
                    .shadow(color: tint.opacity(0.6), radius: 3)
            }
        }
        .allowsHitTesting(false)
    }
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
