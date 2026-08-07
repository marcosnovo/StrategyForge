//
//  SplashView.swift
//  StrategyForge
//
//  A brief launch splash: the same 3D coral sphere the chat uses, spinning over the
//  ambient background while Coral warms the things the app works best with already in
//  hand — connected-provider detection, local usage, and the GitHub repo list — so the
//  first navigation into Code/Usage is instant instead of kicking off a subprocess.
//  It is bounded: the app becomes interactive after a short minimum and never waits on a
//  slow `gh` beyond a hard cap (preload just keeps warming caches in the background).
//

import SwiftUI

/// True when the process is hosting an XCTest bundle. `StrategyForgeTests` is app-hosted
/// (TEST_HOST = Coral.app), so running the suite launches the FULL app — and its launch
/// warm-up spawns provider CLIs, PTY login checks, and network fetches that can HANG the
/// test host ("los tests se quedan congelados"). Anything that shells out or hits the
/// network at launch must be skipped when this is true so the gate stays fast + deterministic.
enum AppEnvironment {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}

/// Wraps the app content and holds a splash over it until the (bounded) preload finishes.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ready = false
    @State private var step = ""

    var body: some View {
        ContentView()
            .opacity(ready ? 1 : 0)
            .overlay { if !ready { SplashView(step: step).transition(.opacity) } }
            // Floor the window size so the three-column layout (rail · list · content ·
            // panels) never collapses into the overlapping mess the founder hit when
            // shrinking the window — with `.windowResizability(.contentMinSize)` this min
            // becomes the window's minimum, so it can't be dragged smaller.
            .frame(minWidth: 880, minHeight: 600)
            .task { await preload() }
    }

    /// Run the warm-up steps, but never hold the window hostage: show for at least a
    /// moment (no jarring flash) and at most a few seconds (a slow `gh` keeps warming in
    /// the background after we reveal the app).
    private func preload() async {
        // Under XCTest the app is only a host for the unit bundle — never run the launch
        // warm-up (it shells out / hits the network and can freeze the whole run).
        if AppEnvironment.isRunningTests { ready = true; return }
        async let minShow: Void = quietSleep(ms: 650)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await runSteps() }
            group.addTask { await quietSleep(ms: 4_000) }   // hard cap
            await group.next()
            group.cancelAll()
        }
        await minShow
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { ready = true }
    }

    @MainActor private func runSteps() async {
        step = model.t("splash.models")
        await ModelCatalog.refresh()   // pull the latest add/deprecate list (repo-hosted, cached)
        await SkillStore.shared.refreshCatalog()   // extra Discover skills from any source
        step = model.t("splash.providers")
        await model.refreshConnectedProviders()
        step = model.t("splash.verify")
        await model.verifyConnections()   // flag any installed-but-expired/missing logins up front
        model.pruneEmptyChats(keeping: model.selectedConfigID)   // clear blank leftover chats

        step = model.t("splash.usage")
        await model.refreshUsage()   // LOCAL logs only — no Keychain prompt at launch
        if GitHubCLI.isInstalled, model.cachedGitHubRepos.isEmpty {
            step = model.t("splash.repos")
            let repos = await GitHubCLI.listRepos()
            if !repos.isEmpty {
                model.cachedGitHubRepos = repos
                model.gitHubReposLoadedAt = Date()
            }
        }
    }

    private func quietSleep(ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
}

/// The launch screen: the chat's 3D coral sphere, the wordmark, and the current warm-up
/// step (transparency — every long op says what it's doing, never a bare spinner).
struct SplashView: View {
    var step: String

    var body: some View {
        ZStack {
            Theme.appBg.ignoresSafeArea()
            VStack(spacing: Space.l) {
                CoralSphere(size: 120, animating: true)
                Text("Coral")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(step.isEmpty ? "" : step)
                    .font(.sfCaption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 14)          // reserve the line so the layout doesn't jump
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
