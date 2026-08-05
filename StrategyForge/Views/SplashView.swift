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
            .task { await preload() }
    }

    /// Run the warm-up steps, but never hold the window hostage: show for at least a
    /// moment (no jarring flash) and at most a few seconds (a slow `gh` keeps warming in
    /// the background after we reveal the app).
    private func preload() async {
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
        step = model.t("splash.providers")
        await model.refreshConnectedProviders()
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
