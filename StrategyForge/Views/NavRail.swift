//
//  NavRail.swift
//  StrategyForge
//
//  The always-present left navigation strip: ONE fixed-width icon rail (Claude/ChatGPT/
//  Cursor style). Each destination is an icon with a small label below it; the active one
//  is marked by a quiet neutral selection wash + a coral leading bar (no expand/collapse
//  mode, no animated spotlight — a calm, invariant rail). Labels also surface as verb-first
//  tooltips. Power tools live under a "More" disclosure; account + settings pin at the foot.
//

import SwiftUI

struct NavRail: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSidebar: Bool
    /// Drives the styled account popover (reference-style menu with icon rows).
    @State private var showAccountMenu = false

    /// Fixed slim icon rail — one width, always (no expand mode).
    private let railWidth: CGFloat = 76

    /// The power-tools group under "More" is collapsed by default (persisted).
    @AppStorage("nav.showMore") private var showMore = false
    /// Sections that live under "More" — used to auto-open the group when one is active.
    private var moreSectionActive: Bool {
        [.map, .arena, .loops, .memory, .skills, .services].contains(model.navSection)
    }
    private var moreShown: Bool { showMore || moreSectionActive }

    var body: some View {
        VStack(spacing: Space.xs) {
            brand
            newChatButton

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Space.xs) {
                    railDivider
                    item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                         active: model.navSection == .chats,
                         running: !model.runningChatIDs.isEmpty || !model.attentionChatIDs.isEmpty,
                         help: "sidebar.chats.help") {
                        model.guardedLeave {
                            model.navSection = .chats
                            if reduceMotion { showSidebar = true }
                            else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                        }
                    }
                    item("chevron.left.forwardslash.chevron.right", "rail.code", active: model.navSection == .code,
                         help: "rail.code.help") {
                        model.guardedLeave { model.navSection = .code }
                    }
                    // Team is the headline "design a team" capability — top-level.
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

            // The ONE usage door: shows the live rate-limit % AND opens Usage (a neutral
            // gauge tile until a % is cached). No Keychain touch here (see the .task below).
            ClaudeUsagePill(style: .tile)

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
        .frame(width: railWidth)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, Space.s)
        .padding(.top, 34)          // clear the floating traffic lights (hidden titlebar)
        .padding(.bottom, Space.m)
        // The rail uses the native macOS `.sidebar` vibrancy so it reads as a true sidebar,
        // distinct from the content columns (chat list / activity panel).
        .railColumn()
        // One spring cross-fades the neutral selection marker between rows. Snaps under Reduce Motion.
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: model.navSection)
        // Usage card from LOCAL logs only — no Keychain read, so launch never prompts.
        .task { await model.refreshUsage() }
    }

    /// Brand mark: the coral glyph (matches the app icon), centered on the icon rail.
    private var brand: some View {
        CoralMark(size: 26, color: Theme.coral)
            .frame(width: 40, height: 36)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Space.xs)
    }

    /// The "New chat" affordance — a flat coral create action (the rail's inviting primary).
    private var newChatButton: some View {
        Button {
            model.guardedLeave {
                model.navSection = .chats
                model.addConfiguration()
            }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.coral)
                    .frame(width: 40, height: 30)
                Text(model.t("sidebar.newShort")).scaledFont(10, weight: .medium)
                    .foregroundStyle(Theme.coral).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .hoverTint(cornerRadius: Theme.rowCorner)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t("sidebar.new"))
        .accessibilityLabel(model.t("sidebar.new"))
    }

    /// A rail destination: icon over a small label; the tooltip teaches what it opens.
    private func item(_ icon: String, _ labelKey: String,
                      active: Bool = false, running: Bool = false,
                      help helpKey: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(icon: icon, label: model.t(labelKey), active: active, running: running)
        }
        .buttonStyle(.plain)
        .help(model.t(helpKey ?? labelKey))
        .accessibilityLabel(model.t(labelKey))
    }

    /// A short hairline rule that groups the icon rail into sections.
    private var railDivider: some View {
        Rectangle().fill(Theme.hairline)
            .frame(width: 24, height: 1)
            .frame(maxWidth: 24)
            .padding(.vertical, 2)
    }

    /// Shared row chrome: icon with a small label below. The ACTIVE row is marked by a quiet
    /// neutral selection wash behind the cell + a coral leading bar + a coral icon — no
    /// animated spotlight, just a calm "you are here".
    private func rowBody(icon: String, label: String, active: Bool, running: Bool) -> some View {
        let iconTint = active ? Theme.coral : Theme.secondaryOnMaterial
        let labelTint = active ? Theme.ink : Theme.secondaryOnMaterial
        // Fill is reserved for the ACTIVE row — at rest every glyph is its lighter outline,
        // which is the single biggest cut to the rail's ink weight (the "reads dark" note).
        let resolvedIcon = active ? icon : (icon.hasSuffix(".fill") ? String(icon.dropLast(5)) : icon)
        return VStack(spacing: 1) {
            Image(systemName: resolvedIcon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(iconTint)
                .frame(width: 40, height: 30)
                .overlay(alignment: .topTrailing) {
                    if running && !active { RunningPulseDot().offset(x: -3, y: 3) }
                }
            Text(label).scaledFont(10, weight: .medium)
                .foregroundStyle(labelTint)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background {
            if active {
                RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                    .fill(Theme.selectionFill)
            }
        }
        .overlay(alignment: .leading) {
            if active {
                Capsule().fill(Theme.coral).frame(width: 3, height: 22)
            }
        }
        .hoverTint(cornerRadius: Theme.rowCorner)
        .contentShape(Rectangle())
    }

    /// The "More" disclosure tile: reveals the power-tools group. A running pulse rides it
    /// when a hidden loop is live (so a background run's signal is never buried).
    private var moreTile: some View {
        let hiddenRunning = !moreShown && !LoopStore.shared.runningLoopIDs.isEmpty
        let icon = moreShown ? "chevron.up" : "ellipsis"
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showMore.toggle() }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.secondaryOnMaterial)
                    .frame(width: 40, height: 30)
                    .overlay(alignment: .topTrailing) { if hiddenRunning { RunningPulseDot().offset(x: -3, y: 3) } }
                Text(model.t("rail.more")).scaledFont(10, weight: .medium)
                    .foregroundStyle(Theme.secondaryOnMaterial).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .hoverTint(cornerRadius: Theme.rowCorner)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t("rail.more"))
        .accessibilityLabel(model.t("rail.more"))
    }

    // MARK: Profile row

    /// The bottom user-profile row: identity + a menu (Sync / Sign out) when signed in, or a
    /// "Sign in" affordance otherwise.
    @ViewBuilder private var profileRow: some View {
        if let acc = auth.account {
            Button { showAccountMenu.toggle() } label: {
                avatarCircle(initials(acc.label))
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(acc.label)
            .popover(isPresented: $showAccountMenu, arrowEdge: .trailing) { accountMenu }
            .padding(.top, Space.xs)
        } else {
            Button { model.navSection = .settings } label: {
                signInAvatar.frame(maxWidth: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.t("rail.profile.signin"))
            .padding(.top, Space.xs)
        }
    }

    /// The account dropdown: a soft frosted card of icon rows, with a coral "Sign out".
    private var accountMenu: some View {
        VStack(alignment: .leading, spacing: 1) {
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

    /// Solid coral avatar with white initials — a clear, high-contrast identity chip.
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

/// The rail's "work in flight elsewhere" indicator: a small teal dot with a slow opacity
/// pulse (static under Reduce Motion).
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
