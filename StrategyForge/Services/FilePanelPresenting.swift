//
//  FilePanelPresenting.swift
//  StrategyForge
//
//  The seam (#12) between AppModel/LoopStore and AppKit's file panels. The 14 open/save
//  panels collapse to three intents (choose a directory, choose a file, save a file); the
//  real implementation runs NSOpenPanel/NSSavePanel, and a fake can return a preset URL so
//  code that picks a folder/file is testable without a modal.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
protocol FilePanelPresenting {
    /// Pick a single directory, optionally opening at `startingAt`. Returns nil if cancelled.
    func chooseDirectory(prompt: String?, message: String?, startingAt: URL?) -> URL?
    /// Pick a single file of the given content types. Returns nil if cancelled.
    func chooseFile(contentTypes: [UTType], prompt: String?) -> URL?
    /// Choose a save destination, seeded with a suggested name + content types.
    func save(suggestedName: String, contentTypes: [UTType]) -> URL?
}

/// The real presenter: runs AppKit's modal panels.
@MainActor
struct AppKitFilePanels: FilePanelPresenting {
    func chooseDirectory(prompt: String?, message: String?, startingAt: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let prompt { panel.prompt = prompt }
        if let message { panel.message = message }
        if let startingAt { panel.directoryURL = startingAt }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseFile(contentTypes: [UTType], prompt: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if !contentTypes.isEmpty { panel.allowedContentTypes = contentTypes }
        if let prompt { panel.prompt = prompt }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func save(suggestedName: String, contentTypes: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if !contentTypes.isEmpty { panel.allowedContentTypes = contentTypes }
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
