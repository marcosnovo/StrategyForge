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
    /// The rail can EXPAND to a labeled sidebar or stay a minimal icon strip (persisted).
    @AppStorage("nav.railExpanded") private var railExpanded = false

    private var railWidth: CGFloat { railExpanded ? 208 : 76 }

    /// The power-tools group under "More" is collapsed by default (persisted).
    @AppStorage("nav.showMore") private var showMore = false
    /// Sections that live under "More" — used to auto-open the group when one is active.
    /// (Team is now a top-level WORK item; Code Map + Arena moved DOWN into More.)
    private var moreSectionActive: Bool {
        [.map, .arena, .loops, .memory, .skills, .usage, .services].contains(model.navSection)
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
                         running: !model.runningChatIDs.isEmpty || !model.attentionChatIDs.isEmpty,
                         help: "sidebar.chats.help") {
                        model.guardedLeave {
                            model.navSection = .chats
                            // Rail = "where am I" (reveal the list); the chat HEADER's toggle is
                            // the single place that hides it.
                            if reduceMotion { showSidebar = true }
                            else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                        }
                    }
                    item("chevron.left.forwardslash.chevron.right", "rail.code", active: model.navSection == .code,
                         help: "rail.code.help") {
                        model.guardedLeave { model.navSection = .code }
                    }
                    // Team is the headline "design a team" capability — promoted into WORK.
                    item("person.3.sequence.fill", "rail.team", active: model.navSection == .team,
                         help: "rail.team.help") {
                        model.guardedLeave { model.navSection = .team }
                    }

                    railDivider

                    // POWER TOOLS + setup, behind one disclosure so the resting rail stays
                    // scannable (Chats · Code · Team). Auto-expands when one is active.
                    moreTile
                    if moreShown {
                        item("circle.hexagongrid.fill", "rail.map", active: model.navSection == .map,
                             help: "rail.map.help") {
                            model.guardedLeave { model.navSection = .map }
                        }
                        item("flag.checkered", "rail.arena", active: model.navSection == .arena,
                             help: "rail.arena.help") {
                            model.guardedLeave { model.navSection = .arena }
                        }
                        item("arrow.triangle.2.circlepath", "rail.loops",
                             active: model.navSection == .loops,
                             running: !LoopStore.shared.runningLoopIDs.isEmpty) {
                            model.guardedLeave { model.navSection = .loops }
                        }
                        item("brain", "rail.memory", active: model.navSection == .memory,
                             help: "rail.memory.help") {
                            model.guardedLeave { model.navSection = .memory }
                        }
                        item("puzzlepiece.extension.fill", "rail.skills", active: model.navSection == .skills,
                             help: "rail.skills.help") {
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

            // Theme/appearance moved to Settings (the rail stays a clean nav strip).
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
        // ONE spotlight beam behind the whole rail, positioned on the active row's bounds and
        // animated → it physically SLIDES between sections (never insert-then-settle). Sits
        // UNDER the icons (zIndex -1) so it lights them rather than covering them.
        .backgroundPreferenceValue(SpotlightAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, !railExpanded {
                    let r = proxy[anchor]
                    SpotlightBeam(tint: Theme.coral)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        // Smooth but alive: the light GLIDES to the new section (a soft spring
                        // with a hint of settle), rather than darting — the founder found the
                        // fast version "corre mucho". Snaps under Reduce Motion.
                        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82),
                                   value: model.navSection)
                }
            }
            .allowsHitTesting(false)
        }
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
                      help helpKey: String? = nil,
                      action: @escaping () -> Void) -> some View {
        // The tooltip TEACHES what the destination does (verb-first) rather than echoing the
        // label — so a newcomer can tell the sections apart on hover. Falls back to the label.
        Button(action: action) {
            rowBody(icon: icon, label: model.t(labelKey), active: active, running: running)
        }
        .buttonStyle(.plain)
        .help(model.t(helpKey ?? labelKey))
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
            // Expanded → the calm coral pill (a text list wants a quiet marker). The
            // collapsed icon rail's selection is drawn by ONE sliding spotlight overlay
            // (see the rail container), so no per-row background there.
            if active && railExpanded {
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(Theme.coral.opacity(0.09))
            }
        }
        // Report the ACTIVE row's bounds so the single spotlight beam can slide onto it
        // (a real move between rows, not an insert-then-settle).
        .anchorPreference(key: SpotlightAnchorKey.self, value: .bounds) {
            (active && !railExpanded) ? $0 : nil
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

/// The active row's bounds, so ONE spotlight beam can be positioned on it and animate its
/// move between rows (a real slide, not an insert). nil when nothing should be lit.
private struct SpotlightAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// A CORAL spotlight shining FROM THE LEFT onto the active icon: a bright lamp on the leading
/// edge, a soft cone of coral light widening rightward, and a warm pool on the icon. Sized to
/// the active row and slid vertically between rows by the caller. Decorative.
private struct SpotlightBeam: View {
    var tint: Color = Theme.coral

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let iconY = h * 0.38          // the icon sits in the upper part of the cell
            ZStack {
                // OUTER cone — a wide, very soft volumetric wash so the beam reads as light
                // spilling into the cell (not a hard wedge). Fans from the lamp to the far edge.
                cone(w: w, h: h, iconY: iconY, spreadTop: 0.10, spreadBottom: 0.62, reach: 1.0,
                     colors: [tint.opacity(0.30), tint.opacity(0.10), .clear])
                    .blur(radius: 9)
                // INNER cone — the brighter core of the beam, narrower and tighter, giving the
                // shaft of light its defined shape from the left edge across the icon.
                cone(w: w, h: h, iconY: iconY, spreadTop: 0.05, spreadBottom: 0.34, reach: 0.82,
                     colors: [tint.opacity(0.62), tint.opacity(0.22), .clear])
                    .blur(radius: 3.5)
                // Pool of light where the icon sits — the beam "landing" on the target.
                RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0.18), .clear],
                               center: .center, startRadius: 0, endRadius: h * 0.52)
                    .frame(width: h * 1.1, height: h * 1.1)
                    .position(x: w * 0.52, y: iconY)
                    .blur(radius: 4)
                // The lamp on the leading edge — a bright coral BAR (the light source), with a
                // soft halo. No round bulb: the founder wants a clean line, no dot in the middle.
                Capsule().fill(tint.opacity(0.95))
                    .frame(width: 3, height: h * 0.4)
                    .position(x: 2, y: iconY)
                    .shadow(color: tint.opacity(0.85), radius: 6)
                    .shadow(color: tint.opacity(0.5), radius: 2)
                    .blur(radius: 0.5)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }

    /// A left-origin light cone: narrow at the lamp (x≈0), fanning right to `reach`·w. The
    /// vertical half-spread grows from `spreadTop`·h at the source to `spreadBottom`·h at the
    /// mouth, and the gradient fades left→right so the shaft dims as it travels.
    private func cone(w: CGFloat, h: CGFloat, iconY: CGFloat,
                      spreadTop: CGFloat, spreadBottom: CGFloat, reach: CGFloat,
                      colors: [Color]) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: iconY - h * spreadTop))
            p.addLine(to: CGPoint(x: 0, y: iconY + h * spreadTop))
            p.addLine(to: CGPoint(x: w * reach, y: iconY + h * spreadBottom))
            p.addLine(to: CGPoint(x: w * reach, y: iconY - h * spreadBottom))
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
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
