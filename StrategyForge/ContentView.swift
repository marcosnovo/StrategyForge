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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false
    /// The Task→Strategy generator, used as the onboarding gate + empty-state CTA.
    @State private var showTaskGen = false
    // Persisted, user-resizable widths for the second column (list / services / team).
    @AppStorage("col.sidebar") private var sidebarW = 240.0
    @AppStorage("col.services") private var servicesW = 240.0
    @AppStorage("col.team") private var teamW = 260.0

    /// A CGFloat binding backed by a Double @AppStorage, for ResizableDivider.
    private func widthBinding(_ value: Binding<Double>) -> Binding<CGFloat> {
        Binding(get: { CGFloat(value.wrappedValue) }, set: { value.wrappedValue = Double($0) })
    }

    /// Create a fresh chat and open the "describe your task" generator on it.
    private func startFromTask() {
        model.addConfiguration()
        showTaskGen = true
    }

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
            // Always-present dark navigation rail (brand + actions + settings).
            NavRail(showSidebar: $model.showSidebar)
            Divider()

            // Second column: the chat list, the services list, or (in Team) the
            // strategy picker so you can swap the whole team.
            if model.navSection == .services {
                ServicesListColumn().frame(width: CGFloat(servicesW))
                ResizableDivider(width: widthBinding($servicesW), range: 200...460)
            } else if model.navSection == .team {
                // Team section always leads with the team selector (list + empty state).
                TeamSelectorColumn(selectedID: $model.selectedTeamID).frame(width: CGFloat(teamW))
                ResizableDivider(width: widthBinding($teamW), range: 220...480)
            } else if model.navSection == .usage || model.navSection == .particleLab {
                // Single full-width surfaces — no second column.
                EmptyView()
            } else if model.showSidebar || model.selectedConfiguration == nil {
                SidebarView(showSidebar: $model.showSidebar)
                    .frame(width: CGFloat(sidebarW))
                    .transition(.move(edge: .leading).combined(with: .opacity))
                ResizableDivider(width: widthBinding($sidebarW), range: 200...460)
            }

            // Main area: a provider's config in Services, the visual Team canvas in
            // Team, else the chat.
            if model.navSection == .services {
                ProviderConfigView(provider: model.selectedService)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .team {
                if let tid = model.selectedTeamID, model.savedTeams.contains(where: { $0.id == tid }) {
                    // A team is open → edit it (canvas + detail).
                    TeamView(team: model.teamBinding(tid))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // No team open → the strategy browser is the "create a team" surface.
                    StrategyPickerColumn(config: nil, selectedStrategyName: nil,
                                         onSelect: { model.createTeam(from: $0) })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.navSection == .usage {
                UsageView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .particleLab {
                ParticleLabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let id = model.selectedConfigID, let chat = model.selectedConfiguration {
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
                EmptyEditorState(onDescribeTask: { startFromTask() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(hazeBackground)
        // App-wide banner so success/errors surface anywhere, not just the editor.
        .overlay(alignment: .top) { GlobalBanner() }
        // Per-chat configuration as a modal sheet (strategy + file generation).
        .sheet(isPresented: $model.showInspector) {
            if let id = model.selectedConfigID { configSheet(id) }
        }
        .onChange(of: model.selectedConfigID) { model.rememberSelection() }
        .task { await model.refreshConnectedProviders() }
        .onAppear { if !didOnboard { showOnboarding = true } }
        .sheet(isPresented: $showOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingView(onCreate: { model.addConfiguration() },
                           onDescribeTask: { startFromTask() })
        }
        // The onboarding gate + empty-state CTA: describe a task → AI builds the team.
        .sheet(isPresented: $showTaskGen) {
            if let id = model.selectedConfigID {
                TaskToStrategySheet(config: model.configurationBinding(id))
            }
        }
    }

    /// True behind-window glass: the desktop shows through, blurred. Frosted panels
    /// (columns, chat) layer on top. The window is made non-opaque by WindowConfigurator.
    @ViewBuilder
    private var hazeBackground: some View {
        VisualEffectBackground()
            .overlay(WindowConfigurator().frame(width: 0, height: 0))
            .ignoresSafeArea()
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

/// App-wide success/error banner, driven by `model.banner`. Auto-dismiss is
/// handled in AppModel; this just renders it wherever the user is.
private struct GlobalBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let banner = model.banner {
            let isSuccess: Bool = { if case .success = banner { return true } else { return false } }()
            let text: String = { if case .success(let m) = banner { return m }
                                 if case .failure(let m) = banner { return m }; return "" }()
            HStack(spacing: Space.s) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(text).font(.sfCallout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Button { model.banner = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(Capsule().fill(isSuccess ? Theme.success : Theme.danger)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4))
            .padding(.top, Space.m)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Shown in the center column when nothing is selected.
private struct EmptyEditorState: View {
    @Environment(AppModel.self) private var model
    var onDescribeTask: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label(model.t("empty.editor.title"), systemImage: "square.stack.3d.up")
        } description: {
            Text(model.t("empty.editor.desc"))
        } actions: {
            VStack(spacing: Space.m) {
                // The primary path: describe a task and let AI assemble the team.
                Button {
                    onDescribeTask()
                } label: {
                    Label(model.t("onboard.describeTask"), systemImage: "sparkles")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.moon)
                .controlSize(.large)

                // Beginner: proven setup in one click.
                Button {
                    model.setUpForMe()
                } label: {
                    Label(model.t("setup.oneClick"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.link)
                .help(model.t("setup.oneClick.sub"))

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
