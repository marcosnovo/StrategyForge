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
    /// Set at launch so quit-time cleanup can reach the app model. scenePhase can't
    /// tell "hide/deactivate" from "quit", so pending chat deletes are finalized HERE
    /// (real termination) instead of in the leave-foreground flush — see
    /// AppModel.finalizeOnTerminate.
    @MainActor static weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Local-only crash/hang reporting: MetricKit delivers last run's diagnostics
        // now, and CrashReporter summarizes them into the exportable DiagnosticsLog.
        #if canImport(MetricKit)
        CrashReporter.shared.start()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        LiveProcesses.terminateAll()
        // Delegate callbacks arrive on the main thread; make that explicit for Swift.
        MainActor.assumeIsolated { AppDelegate.model?.finalizeOnTerminate() }
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
                // Quit-time hook: the delegate finalizes pending deletes on REAL
                // termination (scenePhase alone can't distinguish hide from quit).
                .onAppear { AppDelegate.model = model }
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
            // New chat replaces the default New Item, plus the chat lifecycle actions
            // (duplicate / delete / import / export) as real File-menu items with the
            // same shortcuts the command palette advertises.
            CommandGroup(replacing: .newItem) {
                Button(model.t("sidebar.new")) { model.addConfiguration() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button(model.t("config.duplicate")) {
                    if let id = model.selectedConfigID { model.duplicateConfiguration(id) }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model.selectedConfiguration == nil)
                Button(model.t("sidebar.delete")) {
                    if let id = model.selectedConfigID { model.deleteConfiguration(id) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedConfiguration == nil)
                Divider()
                Button(model.t("doc.import")) { model.importStrategyDocument() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(model.t("doc.export")) {
                    if let c = model.selectedConfiguration { model.exportStrategyDocument(c) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedConfiguration == nil)
            }
            // ⌘K opens the command palette (chat + section quick-switcher); ⌘. stops the
            // selected chat's live turn (the macOS "cancel" convention).
            CommandGroup(after: .toolbar) {
                Button(model.t("palette.placeholder")) { model.showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button(model.t("chat.stop")) { model.stopSelectedChat() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(model.selectedConfiguration == nil)
            }
            // View menu: toggle the panes + switch chats from the keyboard.
            CommandGroup(after: .sidebar) {
                Button(model.t("menu.prevChat")) { model.selectAdjacentChat(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button(model.t("menu.nextChat")) { model.selectAdjacentChat(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
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
