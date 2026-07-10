//
//  ContentView.swift
//  StrategyForge
//
//  Root three-column layout: saved configurations (sidebar) → strategy editor
//  (content) → file preview & actions (detail).
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var model = model
        // Manual two-pane layout instead of NavigationSplitView: an HStack fills
        // the window, so each pane is height-bounded and its ScrollView scrolls
        // correctly. (NavigationSplitView here sized itself to its tall content
        // ideal and got centered in the window, clipping content and killing
        // scroll — reproduced and confirmed via the accessibility tree.)
        HStack(spacing: 0) {
            // Left column: chat history. Collapsible into a thin rail; always shown
            // in full when there's no active chat (so New chat stays reachable).
            if model.showSidebar || model.selectedConfiguration == nil {
                SidebarView(showSidebar: $model.showSidebar)
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            } else {
                CollapsedSidebarRail(showSidebar: $model.showSidebar)
                    .transition(.move(edge: .leading))
                Divider()
            }

            if let id = model.selectedConfigID, let chat = model.selectedConfiguration {
                // Center: the chat — the protagonist, full width.
                ChatView(config: chat,
                         binary: model.settings.claudeBinary,
                         permissionMode: model.settings.chatAutonomy.permissionMode,
                         showInspector: $model.showInspector,
                         showSidebar: $model.showSidebar,
                         showActivity: $model.showActivity,
                         persist: { [id] messages in model.updateTranscript(id, messages) },
                         rename: { [id] title in model.renameConfiguration(id, title) },
                         autoTitle: { [id] text in model.autoTitleIfNeeded(id, fromFirstMessage: text) },
                         saveDraft: { [id] text in model.updateDraft(id, text) },
                         ensureStrategyFiles: { [id] in model.writeStrategyFilesQuietly(id) },
                         persistUsage: { [id] tokens, cost in model.updateUsage(id, tokens: tokens, costUSD: cost) })
                    .id("\(id)|\(chat.repoPath ?? "none")")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyEditorState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        // Per-chat configuration as a modal sheet (strategy + file generation).
        .sheet(isPresented: $model.showInspector) {
            if let id = model.selectedConfigID { configSheet(id) }
        }
        .onChange(of: model.selectedConfigID) { model.rememberSelection() }
        .onAppear { if !didOnboard { showOnboarding = true } }
        .sheet(isPresented: $showOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingView(onCreate: { model.addConfiguration() })
        }
    }

    /// The per-chat configuration sheet: strategy + file-generation options.
    private func configSheet(_ id: Configuration.ID) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.t("chat.settings")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { model.showInspector = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
            Divider()
            ChatInspector(config: model.configurationBinding(id))
        }
        .frame(minWidth: 820, idealWidth: 1040, maxWidth: .infinity,
               minHeight: 640, idealHeight: 820, maxHeight: .infinity)
    }
}

/// Shown in the center column when nothing is selected.
private struct EmptyEditorState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label(model.t("empty.editor.title"), systemImage: "square.stack.3d.up")
        } description: {
            Text(model.t("empty.editor.desc"))
        } actions: {
            VStack(spacing: Space.m) {
                // Beginner: proven setup in one click.
                Button {
                    model.setUpForMe()
                } label: {
                    Label(model.t("setup.oneClick"), systemImage: "wand.and.stars")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(model.t("setup.oneClick.sub"))

                // Zero-risk practice folder.
                Button {
                    model.trySampleFolder()
                } label: {
                    Label(model.t("setup.sample"), systemImage: "sparkles")
                        .frame(maxWidth: 320)
                }
                .controlSize(.large)
                .help(model.t("setup.sample.sub"))

                Button(model.t("sidebar.new")) { model.addConfiguration() }
                    .buttonStyle(.link)
            }
        }
    }
}

private struct ContentPreviewHost: View {
    @State private var model: AppModel = {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        let m = AppModel()
        var c1 = Configuration(name: "Improve the game's visual design",
                               strategy: StrategyLibrary.orchestratorWorkers(),
                               repoPath: "/Users/me/Projects/starfox",
                               updatedAt: Date(timeIntervalSinceNow: -600))
        c1.transcript = [
            .init(role: .user, text: "I want to improve the game's design a lot, it's very poor right now."),
            .init(role: .assistant, text: "I audited the project. Here's the plan:\n\n**What I found**\n- The HUD uses generic mint/orange inline colors.\n- No shared design tokens.\n\n**Next steps**\n1. Introduce a `Theme` with tokens.\n2. Rework the title screen.\n\nStarting with the HUD now."),
        ]
        c1.totalTokens = 24_500
        c1.totalCostUSD = 0.12
        var c2 = Configuration(name: "Understand the physics engine",
                               strategy: StrategyLibrary.researchFanout(),
                               repoPath: "/Users/me/Projects/starfox",
                               updatedAt: Date(timeIntervalSinceNow: -86_400))
        m.configurations = [c1, c2]
        m.selectedConfigID = c1.id
        return m
    }()
    var body: some View {
        ContentView()
            .environment(model)
            .tint(Theme.accent)
            .frame(width: 1100, height: 680)
    }
}

#Preview { ContentPreviewHost() }
