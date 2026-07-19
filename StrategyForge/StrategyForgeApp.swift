//
//  StrategyForgeApp.swift
//  StrategyForge
//
//  Created by Marcos on 08/07/2026.
//

import SwiftUI
import AppKit

/// Terminates any live child CLI processes on quit so a running chat/loop subprocess is
/// never orphaned (it would otherwise survive the app and keep burning the user's plan).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Local-only crash/hang reporting: MetricKit delivers last run's diagnostics
        // now, and CrashReporter summarizes them into the exportable DiagnosticsLog.
        #if canImport(MetricKit)
        CrashReporter.shared.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        LiveProcesses.terminateAll()
    }
}

@main
struct StrategyForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var auth = AuthModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(auth)
                .tint(Theme.accent)
        }
        // Flush any coalesced device-local write (transcript/usage/draft) when the app
        // leaves the foreground, so a deferred save is never lost on quit.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flushSaves() }
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
