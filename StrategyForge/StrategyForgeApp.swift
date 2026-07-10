//
//  StrategyForgeApp.swift
//  StrategyForge
//
//  Created by Marcos on 08/07/2026.
//

import SwiftUI

@main
struct StrategyForgeApp: App {
    @State private var model = AppModel()
    @State private var auth = AuthModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(auth)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)   // content fills under the traffic lights (seamless glass)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)
        .commands {
            // New chat replaces the default New Item.
            CommandGroup(replacing: .newItem) {
                Button(model.t("sidebar.new")) { model.addConfiguration() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            // View menu: toggle the panes from the keyboard.
            CommandGroup(after: .sidebar) {
                Button(model.t("sidebar.toggle")) { model.showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button(model.t("chat.activity")) { model.showActivity.toggle() }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                    .disabled(model.selectedConfiguration == nil)
                Button(model.t("chat.settings")) { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.selectedConfiguration == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(auth)
        }
    }
}
