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

    /// Advisor → chat: new chat with the recommended team applied and the task
    /// text seeded as the draft, no team saved.
    private func useAdviceInChat(_ advice: AdvisorEngine.Advice, task: String) {
        model.addConfiguration()
        if let id = model.selectedConfigID {
            model.applyTemplate(advice.strategy, to: id)
            model.updateDraft(id, task)
        }
        model.navSection = .chats
        model.flashSuccess(model.t("advisor.usedInChat"))
    }

    /// Advisor → loop: a new loop pre-filled with a name inferred from the task,
    /// plus the recommended kind, goal and worker model, opened in the Loop Builder.
    private func createLoop(from advice: AdvisorEngine.Advice, task: String) {
        let inferred = AppModel.inferredTitle(from: task)
        let name = inferred.isEmpty ? String(task.prefix(48)) : inferred
        let prefill = LoopPlan(name: name,
                               kind: advice.loopKind,
                               goal: advice.goalSuggestion,
                               effort: advice.effort,
                               workerModel: advice.model)
        LoopStore.shared.addLoop(prefill: prefill)
        model.navSection = .loops
        model.flashSuccess(model.t("loop.createdFromAdvice"))
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
                // While configuring a DRAFT (creating), the editor takes the full width —
                // no team-list column beside it (that squished sliver was the glitch).
                if model.draftTeamBinding == nil {
                    TeamSelectorColumn(selectedID: $model.selectedTeamID).frame(width: CGFloat(teamW))
                    ResizableDivider(width: widthBinding($teamW), range: 220...480)
                }
            } else if model.navSection == .loops {
                // Loops section leads with the loop list (mirrors Team).
                LoopSelectorColumn(store: LoopStore.shared)
                Divider()
            } else if model.navSection == .usage || model.navSection == .advisor
                        || model.navSection == .particleLab || model.navSection == .code
                        || model.navSection == .skills || model.navSection == .settings {
                // Single full-width surfaces — no second column (no chat list here).
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
                if let tool = model.selectedTool {
                    ToolConfigView(tool: tool)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProviderConfigView(provider: model.selectedService)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.navSection == .team {
                if let draft = model.draftTeamBinding {
                    // A draft is being configured → edit it, commit only on "Create".
                    TeamView(team: draft, mode: .draft, onCommit: { model.commitDraftTeam() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let tid = model.selectedTeamID, model.savedTeams.contains(where: { $0.id == tid }) {
                    // A team is open → edit it (canvas + detail).
                    TeamView(team: model.teamBinding(tid))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // No team open → the browse surface: Templates + Discover (the old
                    // standalone Team library, now folded in here).
                    TeamBrowseView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.navSection == .usage {
                UsageView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .loops {
                if let lid = LoopStore.shared.selectedLoopID,
                   let plan = LoopStore.shared.binding(lid) {
                    // A loop is open → edit it. Re-key by id so the embedded run
                    // panel (and its controller) resets when switching loops.
                    LoopEditorView(plan: plan, store: LoopStore.shared)
                        .id(lid)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(model.t("loop.empty.title"), systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text(model.t("loop.empty.desc"))
                    } actions: {
                        Button {
                            LoopStore.shared.addLoop()
                        } label: {
                            Label(model.t("loop.empty.create"), systemImage: "plus")
                                .frame(maxWidth: 320)
                        }
                        .buttonStyle(.moon)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.navSection == .advisor {
                AdvisorView(onUseInChat: { advice, task in useAdviceInChat(advice, task: task) },
                            onCreateLoop: { advice, task in createLoop(from: advice, task: task) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .particleLab {
                ParticleLabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .code {
                CodeLauncherView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .skills {
                SkillsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .settings {
                SettingsView(embedded: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let id = model.selectedConfigID, let chat = model.selectedConfiguration,
                      let vm = model.chatViewModel(for: id) {
                // Center: the chat — the protagonist, full width. The VM is owned
                // by AppModel, so a running turn survives navigating away.
                ChatView(config: chat,
                         vm: vm,
                         showInspector: $model.showInspector,
                         showSidebar: $model.showSidebar,
                         showActivity: $model.showActivity,
                         rename: { [id] title in model.renameConfiguration(id, title) },
                         saveDraft: { [id] text in model.updateDraft(id, text) })
                    .id(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyEditorState(onDescribeTask: { startFromTask() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        // Fill the window edge-to-edge — macOS rounds the window corners for us (no
        // inset "capsule"). A very subtle aurora sits behind the panels as a warm
        // ambient; behind-window glass sits below it.
        .ignoresSafeArea()
        .background(AppAuroraBackground().ignoresSafeArea())
        .background(hazeBackground)
        // App-wide banner so success/errors surface anywhere, not just the editor.
        .bannerOverlay()
        // Leaving an uncommitted draft team warns that it will be lost.
        .confirmationDialog(model.t("team.draft.discardTitle"),
                            isPresented: $model.showDiscardDraftConfirm, titleVisibility: .visible) {
            Button(model.t("team.draft.discard"), role: .destructive) { model.confirmDiscardDraft() }
            Button(model.t("team.draft.keep"), role: .cancel) { model.cancelDiscardDraft() }
        } message: {
            Text(model.t("team.draft.discardMsg"))
        }
        // Per-chat configuration as a modal sheet (strategy + file generation).
        .sheet(isPresented: $model.showInspector) {
            if let id = model.selectedConfigID { configSheet(id) }
        }
        .onChange(of: model.selectedConfigID) { model.rememberSelection() }
        .onChange(of: model.selectedTeamID) { model.rememberSelection() }
        .task { await model.refreshConnectedProviders() }
        .task { await model.checkForUpdates() }
        // Load usage from LOCAL logs at launch (no Keychain, no prompt) so the rail's
        // Claude usage is populated by default — not only after visiting the Usage page.
        .task { await model.refreshUsage() }
        .onAppear {
            if !didOnboard { showOnboarding = true }
            // Wire the loop store's feedback into the global banner (idempotent).
            LoopStore.shared.onError = { key, detail in
                model.flashFailure(model.t(key, detail))
            }
            if let err = LoopStore.shared.loadError {
                model.flashFailure(model.t(err.key, err.detail))
                LoopStore.shared.loadError = nil
            }
            LoopStore.shared.onRunFinished = { id, summary in
                let name = LoopStore.shared.loops.first(where: { $0.id == id })?.name ?? ""
                let d = name.isEmpty ? model.t("loop.untitled") : name
                let message: String
                switch summary.pass {
                case .some(true): message = model.t("loop.runDone", d)
                case .some(false): message = model.t("loop.runFailed", d)
                case .none: message = model.t("loop.runDoneUnverified", d)
                }
                // A system notification so a background loop tells you when it's done
                // even if Coral isn't focused (suppressed by macOS while frontmost).
                LoopNotifier.notify(title: d, body: message)
                // In-app banner only for runs the user isn't already watching.
                guard model.navSection != .loops || LoopStore.shared.selectedLoopID != id else { return }
                if summary.pass == false { model.flashFailure(message) } else { model.flashSuccess(message) }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingView(onCreate: { model.addConfiguration() },
                           onDescribeTask: { startFromTask() })
        }
        // Review the first-run onboarding on demand (from the Lab) without touching
        // the didOnboard flag — so it can be seen without reinstalling.
        .sheet(isPresented: $model.showOnboardingPreview) {
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
        // Min must fit inside the window's own minimum (720×480) — a sheet larger
        // than its window gets clipped by macOS. ChatInspector scrolls, so small is OK.
        .frame(minWidth: 680, idealWidth: 1040, maxWidth: .infinity,
               minHeight: 460, idealHeight: 820, maxHeight: .infinity)
        // Sheets cover the window's banner overlay, so the sheet hosts its own.
        .bannerOverlay()
    }
}

/// The app-wide ambient aurora: soft pastel blooms in the Coral identity (coral +
/// peach + teal + mint) over a warm base, heavily blurred so it reads as a dreamy
/// gradient. It shows around the floating app pane (in the window margin) and glows
/// faintly through any translucent panels layered above it. Static (no motion) so it
/// stays calm and cheap; the living AuroraBackground still animates inside the chat.
struct AppAuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    /// Accessibility: when Reduce Transparency is on, drop the translucent haze + blooms
    /// for a solid, opaque base (the whole app's glass falls back to opaque too).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Pastel identity hues. On dark, the base goes to reef-ink and the blooms dim.
    private var base: Color {
        scheme == .dark ? Color(red: 0.043, green: 0.067, blue: 0.075)   // #0B1113
                        : Color(red: 0.972, green: 0.965, blue: 0.960)   // #F8F6F5 warm white
    }
    // A faint brand tint over the vibrancy so text stays legible over a busy wallpaper,
    // while the desktop still reads clearly through it — "leaning toward transparent".
    private var tintOpacity: Double { scheme == .dark ? 0.44 : 0.30 }
    // Very low, so the app-wide background reads as ONE uniform translucent color
    // rather than a visible coral/teal gradient bleeding through the (now translucent)
    // chat and panels. Just a whisper of warmth, no directional wash.
    private var bloomOpacity: Double { scheme == .dark ? 0.05 : 0.06 }

    var body: some View {
        // Reduce Transparency → a plain opaque surface, no haze, no blooms.
        if reduceTransparency {
            return AnyView(base.ignoresSafeArea())
        }
        return AnyView(auroraBody)
    }

    private var auroraBody: some View {
        ZStack {
            // A faint, TRANSLUCENT brand tint (was an opaque fill — which is exactly what
            // hid the behind-window glass sitting below this view). At this opacity the
            // desktop reads clearly through the frosted haze while text stays legible.
            base.opacity(tintOpacity)
            // Two corner blooms only — the identity duality: coral leads (top-trailing),
            // teal answers (bottom-leading). Peach + mint were dropped so the wash reads
            // as one calm gradient, not four hues (design review, wave A).
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let d = max(w, h)
                ZStack {
                    bloom(Theme.coral, at: CGPoint(x: w * 0.92, y: h * 0.04), size: d * 1.05)
                    bloom(Theme.teal, at: CGPoint(x: w * 0.06, y: h * 0.98), size: d * 1.0)
                }
                .blur(radius: 70)
                .drawingGroup()
            }
        }
        .ignoresSafeArea()
    }

    private func bloom(_ color: Color, at center: CGPoint, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(bloomOpacity), .clear],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .position(center)
    }
}

/// Shown in the center column when nothing is selected.
private struct EmptyEditorState: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    var onDescribeTask: () -> Void = {}

    var body: some View {
        // Reference-style landing ("Good Morning, …"): a big iridescent sphere over a
        // centered greeting + subtitle, then the primary/secondary actions — airy and
        // centered, floating on the aurora pane.
        VStack(spacing: Space.xl) {
            Spacer(minLength: 0)

            VStack(spacing: Space.l) {
                CoralSphere(size: 84)
                    .breathingGlow(color: Theme.accentGlow, enabled: false)
                VStack(spacing: Space.xs) {
                    Text(greeting)
                        .font(.sfDisplay)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(model.t("empty.editor.desc"))
                        .font(.sfBodyM).foregroundStyle(Theme.secondaryOnMaterial)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // One primary action: just start a chat. It opens with an auto-team (Coral
            // picks the agents from your first message), so there's nothing to configure —
            // no separate "describe your task" modal, no mode to choose first.
            Button { model.addConfiguration() } label: {
                Label(model.t("empty.editor.start"), systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.moon)

            // Beginner escape hatch: seed a proven team in one click (still optional).
            Button { model.setUpForMe() } label: {
                Label(model.t("setup.oneClick"), systemImage: "wand.and.stars")
            }
            .buttonStyle(.link)
            .help(model.t("setup.oneClick.sub"))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Space.xl + Space.s)
        .padding(.top, Theme.titlebarInset + Space.l)
    }

    /// A personal greeting when signed in ("Hi, {first name}"), else a neutral welcome.
    private var greeting: String {
        if let first = auth.account?.displayName?.split(separator: " ").first {
            return model.t("empty.greeting.name", String(first))
        }
        return model.t("empty.greeting")
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
