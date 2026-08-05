//
//  ContentView.swift
//  StrategyForge
//
//  Root three-column layout: saved configurations (sidebar) → strategy editor
//  (content) → file preview & actions (detail).
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    /// The live design-system selection — reading it here re-renders the whole shell (and
    /// re-reads every palette-driven Theme token) the moment the rail picker changes it.
    @State private var theme = ThemeStore.shared
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
            } else if model.navSection == .map {
                // Map section leads with the list of generated maps.
                MapSelectorColumn()
            } else if model.navSection == .usage
                        || model.navSection == .particleLab || model.navSection == .code
                        || model.navSection == .skills || model.navSection == .memory
                        || model.navSection == .arena || model.navSection == .settings {
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
            } else if model.navSection == .particleLab {
                ParticleLabView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .code {
                CodeLauncherView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .map {
                CodeMapView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .skills {
                SkillsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .memory {
                MemoryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.navSection == .arena {
                ArenaView()
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
        // Re-skin live when the design system changes: `.id` forces the tree to rebuild so
        // every palette-driven Theme token is re-read; Midnight forces a dark appearance.
        .id(theme.active)
        .preferredColorScheme(theme.resolvedScheme)
        // Fill the window edge-to-edge — macOS rounds the window corners for us (no
        // inset "capsule"). A very subtle aurora sits behind the panels as a warm
        // ambient; behind-window glass sits below it.
        .ignoresSafeArea()
        .background(AppAuroraBackground().ignoresSafeArea())
        .background(hazeBackground)
        // A whisper of film GRAIN over the whole app — the single cheapest "this feels
        // expensive" ingredient (kills the flat digital-vacuum read of pure fills).
        .overlay(GrainOverlay().ignoresSafeArea())
        // ⌘K quick-switcher across chats + sections, floating above everything.
        .overlay {
            if model.showCommandPalette {
                CommandPalette(isPresented: $model.showCommandPalette)
                    .transition(.opacity)
            }
        }
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
        // Track full-screen so the columns can drop the traffic-light inset when there are
        // no traffic lights (design review D4). Async sequences — no Combine.
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willEnterFullScreenNotification) {
                model.isFullScreen = true
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSWindow.willExitFullScreenNotification) {
                model.isFullScreen = false
            }
        }
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
            // Same for the knowledge base store.
            MemoryStore.shared.onError = { key, detail in
                model.flashFailure(model.t(key, detail))
            }
            if let err = MemoryStore.shared.loadError {
                model.flashFailure(model.t(err.key, err.detail))
                MemoryStore.shared.loadError = nil
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
                // And, if configured, a remote webhook so it reaches you OFF the Mac
                // (ntfy → phone, Slack/Discord, or any endpoint). Best-effort, off by
                // default; the local notification above still covers the at-the-Mac case.
                if let hook = model.settings.loopWebhookURL, !hook.isEmpty {
                    Task { await LoopWebhookNotifier.notify(urlString: hook, title: d,
                                                            body: message, summary: summary) }
                }
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
/// A static, deterministic film-grain overlay — a sparse stipple of faint dots drawn once
/// (no TimelineView, so no per-frame cost). Deterministic xorshift seed → no flicker on the
/// occasional redraw. Subtle enough to read as texture, not noise.
struct GrainOverlay: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Lighter grain on the near-white light ground (halved) so the roomy surface stays
        // clean; dark keeps a touch more tooth.
        let ceiling = scheme == .dark ? 0.05 : 0.012
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> Double {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return Double(seed % 100_000) / 100_000
            }
            let count = Int(size.width * size.height / 420)
            for _ in 0..<count {
                let x = rnd() * size.width, y = rnd() * size.height
                // Mostly bright specks (catch the light) with a few dark ones for tooth.
                let bright = rnd() > 0.35
                let a = rnd() * (bright ? ceiling : ceiling * 0.9)
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                         with: .color((bright ? Color.white : Color.black).opacity(a)))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.softLight)
    }
}

struct AppAuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pause the animated (caustic) backdrop when the app isn't frontmost — no sense burning
    /// 20fps of blurred gradient while the user is in another app.
    @Environment(\.scenePhase) private var scenePhase
    /// Accessibility: when Reduce Transparency is on, drop the translucent haze + blooms
    /// for a solid, opaque base (the whole app's glass falls back to opaque too).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Pastel identity hues. On dark, the base goes to reef-ink and the blooms dim.
    // One background truth: the aurora base IS Theme.appBg, so the window's ground never
    // subtly shifts depending on whether the aurora is mounted (was a near-but-not-equal
    // inline hex — color review, phase 1).
    private var base: Color { Theme.appBg }
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

    /// The active design language's background atmosphere.
    private var backdrop: Backdrop { Theme.P.backdrop }

    private var auroraBody: some View {
        ZStack {
            base.opacity(tintOpacity)
            // A whisper of directional LIGHT — brighter top, deeper bottom — so panels read
            // as resting on a lit surface.
            LinearGradient(
                colors: scheme == .dark
                    ? [.white.opacity(0.05), .clear, .black.opacity(0.10)]
                    : [.white.opacity(0.45), .clear, .clear],   // no bottom darkening on light — flat paper
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height, d = max(w, h)
                switch backdrop {
                case .paper:      paperGrid(w: w, h: h)
                case .caustic:    causticGlow(w: w, h: h, d: d)
                case .duotone:    duotoneWash(w: w, h: h, d: d)
                case .auroraCoral:
                    reefSunrise(w: w, h: h, d: d)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Backdrops

    /// Reef Paper: matte paper with a faint magazine baseline grid — composed, not empty.
    private func paperGrid(w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            for i in 1...3 {
                let x = size.width * CGFloat(i) / 4
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Theme.ink.opacity(0.025)), lineWidth: 1)
            }
        }
    }

    /// Bioluminescence: coral light pooling from below on a near-black void, drifting slowly
    /// so it reads as living water, not a static gradient. The hero atmosphere.
    private func causticGlow(w: CGFloat, h: CGFloat, d: CGFloat) -> some View {
        let strong = Theme.P.glow                                   // 0.42 in dark
        let frozen = reduceMotion || scenePhase != .active
        return TimelineView(.animation(minimumInterval: 1.0 / 20, paused: frozen)) { tl in
            let t = frozen ? 0 : tl.date.timeIntervalSinceReferenceDate
            ZStack {
                bloom(Theme.coral, at: CGPoint(x: w * (0.30 + 0.06 * sin(t * 0.20)),
                                               y: h * (0.84 + 0.03 * cos(t * 0.16))), size: d * 1.15, opacity: strong * 0.5)
                bloom(Theme.coralDeep, at: CGPoint(x: w * (0.74 + 0.05 * cos(t * 0.18)),
                                                   y: h * (0.70 + 0.04 * sin(t * 0.22))), size: d * 0.95, opacity: strong * 0.34)
                bloom(Theme.coral, at: CGPoint(x: w * 0.52, y: h * 0.10), size: d * 0.6, opacity: strong * 0.14)
            }
            .blur(radius: 70)
            .drawingGroup()
        }
    }

    /// Classic (the flagship LIGHT): a warm coral "reef sunrise" — a soft coral wash in the
    /// top-trailing corner and a fainter deep-coral echo bottom-leading, glowing through the
    /// translucent panels so daylight has real atmosphere instead of dead white. Kept in the
    /// corners so the reading areas stay clean; richer on light (where we want the sunrise),
    /// subtle on dark. Uses the vivid brand coral (a blurred saturated GLOW reads as warm
    /// light, not the desaturated "brick" that a coral SURFACE fill produced).
    private func reefSunrise(w: CGFloat, h: CGFloat, d: CGFloat) -> some View {
        let dark = scheme == .dark
        return ZStack {
            // Light: a whisper of coral in the far corners only — the reading area stays a
            // clean near-white (the ground should read as ONE light surface, not tinted).
            bloom(Theme.coral, at: CGPoint(x: w * 0.98, y: h * -0.02),
                  size: d * 1.15, opacity: dark ? 0.10 : 0.035)
            bloom(Theme.coralDeep, at: CGPoint(x: w * 0.02, y: h * 1.02),
                  size: d * 0.85, opacity: dark ? 0.05 : 0.015)
        }
        .blur(radius: 100)
        .drawingGroup()
    }

    /// Ember: a coral→magenta duotone wash across the diagonal.
    private func duotoneWash(w: CGFloat, h: CGFloat, d: CGFloat) -> some View {
        ZStack {
            bloom(Theme.coral, at: CGPoint(x: w * 0.90, y: h * 0.06), size: d * 0.95, opacity: 0.10)
            bloom(Theme.coralDeep, at: CGPoint(x: w * 0.08, y: h * 0.96), size: d * 0.9, opacity: 0.10)
        }
        .blur(radius: 85).drawingGroup()
    }

    private func bloom(_ color: Color, at center: CGPoint, size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear],
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
        VStack(spacing: Space.xxl) {
            Spacer(minLength: 0)

            VStack(spacing: Space.l) {
                CoralSphere(size: 96)
                    .restingShadow(diameter: 96)   // the hero object rests on the reef
                    .breathingGlow(color: Theme.accentGlow, enabled: false)
                VStack(spacing: Space.s) {
                    // Hero headline with a single coral accent-dot as punctuation (the
                    // reference's signature gesture, on Coral's "one accent = you" rule).
                    (Text(greeting).foregroundStyle(Theme.ink)
                        + Text(".").foregroundStyle(Theme.coral))
                        .font(.sfHero)
                        .tracking(-0.8)
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
        .padding(.top, model.titlebarTopInset + Space.l)
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
