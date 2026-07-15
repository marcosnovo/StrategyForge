//
//  ChatInspector.swift
//  StrategyForge
//
//  The collapsible right panel that configures the active chat: which agentic
//  strategy it uses (models/roles) and the file-generation options. Chat is the
//  protagonist; this is where you tune it, so it's tucked away behind a toggle.
//

import SwiftUI

struct ChatInspector: View {
    @Environment(AppModel.self) private var model
    @Binding var config: Configuration
    @State private var tab: Tab = .strategy
    @State private var pendingTemplate: Strategy?

    private enum Tab: Hashable { case strategy, config }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(model.t("picker.header")).tag(Tab.strategy)
                Text(model.t("inspector.config")).tag(Tab.config)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Theme.accent)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zIndex(1)

            switch tab {
            case .strategy:
                StrategyPickerColumn(config: $config,
                                     selectedStrategyName: config.strategy.name,
                                     onSelect: { template in
                    // Confirm before replacing this chat's team (destructive, no undo).
                    if template.name == config.strategy.name { return }
                    pendingTemplate = template
                })
            case .config:
                StrategyEditorView(config: $config)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Frosted glass column: a translucent material shows the faint aurora as clean
        // neutral vibrancy; the segmented-picker header (.bar) above stays glass too.
        .background(.regularMaterial)
        .confirmationDialog(model.t("inspector.replaceStrategy.confirm"),
                            isPresented: Binding(get: { pendingTemplate != nil },
                                                 set: { if !$0 { pendingTemplate = nil } }),
                            titleVisibility: .visible) {
            Button(model.t("common.apply"), role: .destructive) {
                if let t = pendingTemplate { model.applyTemplate(t, to: config.id) }
                pendingTemplate = nil
            }
            Button(model.t("common.cancel"), role: .cancel) { pendingTemplate = nil }
        }
    }
}

private struct ChatInspectorPreviewHost: View {
    @State private var config = Configuration(name: "Demo",
                                              strategy: StrategyLibrary.orchestratorWorkers(),
                                              repoPath: "/Users/me/Projects/my-app")
    var body: some View {
        ChatInspector(config: $config)
            .environment(AppModel())
            .tint(Theme.accent)
            .frame(width: 340, height: 700)
    }
}

#Preview("Inspector") { ChatInspectorPreviewHost() }
