//
//  NavRail.swift
//  StrategyForge
//
//  The always-present left navigation rail (reference-style): a dark, rounded strip
//  with the brand, primary actions and settings. It sits left of the collapsible
//  chat list.
//

import SwiftUI

struct NavRail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSidebar: Bool
    /// Shared namespace so the coral section dot glides between rail items.
    @Namespace private var navDotNS

    var body: some View {
        VStack(spacing: Space.l) {
            // Brand — the coral mark (matches the app icon), breathing slowly.
            CoralMark(size: 26, color: Theme.coral)
                .breathingGlow(color: Theme.coral)
                .padding(.top, Space.s)

            item("square.and.pencil", "sidebar.new") {
                model.guardedLeave {
                    model.navSection = .chats
                    model.addConfiguration()
                }
            }
            item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                 active: model.navSection == .chats,
                 running: !model.runningChatIDs.isEmpty) {
                model.guardedLeave {
                    model.navSection = .chats
                    if !showSidebar {
                        if reduceMotion { showSidebar = true }
                        else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                    }
                }
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
            item("wand.and.stars", "rail.advisor",
                 active: model.navSection == .advisor) {
                model.guardedLeave { model.navSection = .advisor }
            }
            item("point.3.connected.trianglepath.dotted", "rail.connected",
                 active: model.navSection == .services) {
                model.guardedLeave { model.navSection = .services }
            }
            item("gauge.with.dots.needle.bottom.50percent", "rail.usage",
                 active: model.navSection == .usage) {
                model.guardedLeave {
                    model.navSection = .usage
                    Task { await model.refreshUsage() }
                }
            }

            #if DEBUG
            // DEBUG-only: preview the dot/particle motion system (spinners + waits).
            devItem("sparkles", "Lab", active: model.navSection == .particleLab) {
                model.navSection = .particleLab
            }
            #endif

            Spacer()

            item("gearshape.fill", "sidebar.settings") { openSettings() }
        }
        // 78pt so the window's traffic lights (which span ~70pt) sit fully over the
        // dark rail instead of straddling the seam with the next panel.
        .frame(width: 78)
        .frame(maxHeight: .infinity)
        .padding(.top, 34)          // clear the floating traffic lights (hidden titlebar)
        .padding(.bottom, Space.m)
        .background(Theme.railBg)
        // One spring drives the selection change: the pill fill and the coral
        // dot glide to the new section. Snaps (no glide) under Reduce Motion.
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: model.navSection)
    }

    /// A fixed 3pt slot under every icon; only the active item fills it with the
    /// 2.5pt coral dot. Single `matchedGeometryEffect` source (one active item),
    /// so the dot glides between sections along the rail. An inactive section
    /// with work in flight shows a pulsing dot instead (outside the matched-
    /// geometry branch, so the glide is untouched).
    @ViewBuilder
    private func navDot(_ active: Bool, running: Bool = false) -> some View {
        ZStack {
            if active {
                Circle()
                    .fill(Theme.coral)
                    .matchedGeometryEffect(id: "navdot", in: navDotNS)
                    .frame(width: 2.5, height: 2.5)
            } else if running {
                RunningPulseDot()
            }
        }
        .frame(height: 3)
    }

    private func item(_ icon: String, _ labelKey: String,
                      active: Bool = false, running: Bool = false,
                      action: @escaping () -> Void) -> some View {
        // The rail is always dark, so everything is light; the selected item gets a
        // brighter icon/label and a light fill (never the dark graphite accent).
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.72))
                    .frame(width: 40, height: 34)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(active ? Color.white.opacity(0.18) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(active ? 0.25 : 0), lineWidth: 1))
                navDot(active, running: running)
                Text(model.t(labelKey))
                    .font(.system(size: 9, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())   // whole item is tappable (fixes missed clicks)
        }
        .buttonStyle(.plain)
        .help(model.t(labelKey))
        .accessibilityLabel(model.t(labelKey))
    }

    #if DEBUG
    /// Like `item`, but with a literal (un-localized) label — for DEBUG-only tools.
    private func devItem(_ icon: String, _ label: String,
                         active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.72))
                    .frame(width: 40, height: 34)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(active ? Color.white.opacity(0.18) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(active ? 0.25 : 0), lineWidth: 1))
                navDot(active)
                Text(label)
                    .font(.system(size: 9, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
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
            .fill(Theme.coral)
            .frame(width: 4, height: 4)
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
