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
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 720)

        Settings {
            SettingsView()
                .environment(model)
                .environment(auth)
        }
    }
}
