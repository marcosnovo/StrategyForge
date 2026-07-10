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

            item("square.and.pencil", "sidebar.new", tint: Theme.accent) { model.addConfiguration() }
            item("bubble.left.and.bubble.right.fill", "sidebar.chats", active: showSidebar) {
                if reduceMotion { showSidebar.toggle() }
                else { withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() } }
            }
            item("link", "rail.connected") { openSettings() }

            Spacer()

            item("gearshape.fill", "sidebar.settings") { openSettings() }
        }
        .frame(width: 66)
        .frame(maxHeight: .infinity)
        .padding(.vertical, Space.m)
        .background(Theme.railBg)
    }

    private func item(_ icon: String, _ labelKey: String, tint: Color = .white,
                      active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(active ? Theme.accent : tint.opacity(tint == .white ? 0.85 : 1))
                    .frame(width: 40, height: 34)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(active ? Color.white.opacity(0.12) : .clear))
                Text(model.t(labelKey))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(active ? Theme.accent : Color.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help(model.t(labelKey))
        .accessibilityLabel(model.t(labelKey))
    }
}
