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

    private enum Tab: Hashable { case strategy, config }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(model.t("picker.header")).tag(Tab.strategy)
                Text(model.t("inspector.config")).tag(Tab.config)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Space.s)

            Divider()

            switch tab {
            case .strategy:
                StrategyPickerColumn(config: $config)
            case .config:
                StrategyEditorView(config: $config)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
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
