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

    var body: some View {
        VStack(spacing: Space.l) {
            // Brand
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
                .padding(.top, Space.s)

            item("square.and.pencil", "sidebar.new") {
                model.navSection = .chats
                model.addConfiguration()
            }
            item("bubble.left.and.bubble.right.fill", "sidebar.chats",
                 active: model.navSection == .chats) {
                model.navSection = .chats
                if !showSidebar {
                    if reduceMotion { showSidebar = true }
                    else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                }
            }
            item("point.3.connected.trianglepath.dotted", "rail.connected",
                 active: model.navSection == .services) {
                model.navSection = .services
            }

            Spacer()

            item("gearshape.fill", "sidebar.settings") { openSettings() }
        }
        .frame(width: 66)
        .frame(maxHeight: .infinity)
        .padding(.vertical, Space.m)
        .background(Theme.railBg)
    }

    private func item(_ icon: String, _ labelKey: String,
                      active: Bool = false, action: @escaping () -> Void) -> some View {
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
                Text(model.t(labelKey))
                    .font(.system(size: 9, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(model.t(labelKey))
        .accessibilityLabel(model.t(labelKey))
    }
}
