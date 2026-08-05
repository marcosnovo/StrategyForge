//
//  OnboardingView.swift
//  StrategyForge
//
//  First-run onboarding as a clean, centered, PAGED flow (Antigravity-style):
//   1. Welcome — what Coral is + the wedge (yours, not rented).
//   2. Appearance — System / Light / Dark.
//   3. Connect — sign in to your providers (your plans, no keys) + GitHub.
//  Previous / Next / Finish with page dots. Calm and minimal, like the mainstream AI apps.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called when the user wants to jump straight into creating a configuration.
    let onCreate: () -> Void
    /// The primary path: describe a task and let AI build the team (onboarding gate).
    var onDescribeTask: () -> Void = {}

    @State private var step = 0
    @State private var theme = ThemeStore.shared
    /// A provider whose connect sheet is open (sheet-over-sheet).
    @State private var connecting: AIProvider?
    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcomeStep
                case 1: appearanceStep
                default: connectStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            footer
        }
        .frame(width: 640, height: 600)
        .background(AuroraBackground(intensity: 0.55))
        .sheet(item: $connecting) { p in
            ProviderConnectSheet(provider: p) { Task { await model.refreshConnectedProviders() } }
        }
        .task { Analytics.log(.onboardingStarted) }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: Space.l) {
            Spacer()
            CoralSphere(size: 84)
            Text(model.t("onboard.title")).font(.sfDisplay).multilineTextAlignment(.center)
            Text(model.t("onboard.intro"))
                .font(.sfBodyM).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            HStack(alignment: .top, spacing: Space.l) {
                wedgeBadge("bolt.slash.fill", "onboard.wedge.byo.title", "onboard.wedge.byo.desc")
                wedgeBadge("lock.laptopcomputer", "onboard.wedge.private.title", "onboard.wedge.private.desc")
                wedgeBadge("square.stack.3d.up.fill", "onboard.wedge.mix.title", "onboard.wedge.mix.desc")
            }
            .frame(maxWidth: 500)
            .padding(.top, Space.s)
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    private func wedgeBadge(_ icon: String, _ titleKey: String, _ descKey: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.accent)
            Text(model.t(titleKey)).font(.sfCaption2.weight(.semibold)).multilineTextAlignment(.center)
            Text(model.t(descKey)).font(.sfCaption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var appearanceStep: some View {
        VStack(spacing: Space.l) {
            Spacer()
            stepTitle("onboard.step.appearance.title", "onboard.step.appearance.desc")
            HStack(spacing: Space.l) {
                appearanceCard(.auto)
                appearanceCard(.light)
                appearanceCard(.dark)
            }
            .padding(.top, Space.s)
            Spacer()
        }
        .padding(.horizontal, Space.xl)
    }

    private func appearanceCard(_ a: AppAppearance) -> some View {
        let selected = theme.appearance == a
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { theme.appearance = a }
        } label: {
            VStack(spacing: Space.s) {
                themePreview(a)
                    .frame(width: 132, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Theme.coral : Theme.hairline, lineWidth: selected ? 2 : 1))
                Text(model.t(a.labelKey))
                    .font(.sfCaption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// A tiny window mockup: white (light), near-black (dark), or a split (system).
    @ViewBuilder private func themePreview(_ a: AppAppearance) -> some View {
        switch a {
        case .light: mockWindow(dark: false)
        case .dark:  mockWindow(dark: true)
        case .auto:
            HStack(spacing: 0) {
                mockWindow(dark: false).frame(width: 66)
                mockWindow(dark: true).frame(width: 66)
            }
        }
    }

    private func mockWindow(dark: Bool) -> some View {
        let bg = dark ? Color(red: 0.08, green: 0.09, blue: 0.10) : Color.white
        let line = dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12)
        return ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.coral.opacity(0.9)).frame(width: 26, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 44, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 36, height: 4)
            }
            .padding(10)
        }
    }

    private var connectStep: some View {
        VStack(spacing: Space.m) {
            Spacer(minLength: Space.m)
            stepTitle("onboard.step.connect.title", "onboard.step.connect.desc")
            VStack(spacing: Space.s) {
                ForEach(AIProvider.allCases) { p in providerRow(p) }
                githubRow
            }
            .frame(maxWidth: 460)
            Spacer(minLength: Space.m)
        }
        .padding(.horizontal, Space.xl)
    }

    private func providerRow(_ p: AIProvider) -> some View {
        let on = model.isConnected(p)
        return HStack(spacing: Space.s) {
            ProviderLogo(provider: p, size: 20, templateTint: p.tint)
            Text(p.displayName).font(.sfBodyM.weight(.medium))
            Spacer()
            if on {
                Label(model.t("onboard.connected"), systemImage: "checkmark.circle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.success).labelStyle(.titleAndIcon)
            } else {
                Button(model.t("onboard.connect.action")) { connecting = p }
                    .buttonStyle(.moon).controlSize(.small)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .glassPanel(cornerRadius: Theme.innerCorner)
    }

    private var githubRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.t("onboard.github.title")).font(.sfBodyM.weight(.medium))
                Text(model.t("onboard.github.desc")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if GitHubCLI.isInstalled {
                Label(model.t("onboard.connected"), systemImage: "checkmark.circle.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.success).labelStyle(.titleAndIcon)
            } else {
                Button(model.t("onboard.connect.action")) { dismiss(); model.navSection = .services }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .glassPanel(cornerRadius: Theme.innerCorner)
    }

    private func stepTitle(_ titleKey: String, _ descKey: String) -> some View {
        VStack(spacing: Space.xs) {
            Text(model.t(titleKey)).font(.sfCardTitle).multilineTextAlignment(.center)
            Text(model.t(descKey)).font(.sfCallout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
    }

    // MARK: Footer (Previous · Next/Finish · dots)

    private var footer: some View {
        VStack(spacing: Space.s) {
            Button(model.t("onboard.previous")) {
                withAnimation(.easeInOut(duration: 0.2)) { step = max(0, step - 1) }
            }
            .buttonStyle(.plain)
            .font(.sfCaption2)
            .foregroundStyle(step == 0 ? Color.secondary.opacity(0.4) : Color.secondary)
            .disabled(step == 0)

            Button {
                if step < stepCount - 1 { withAnimation(.easeInOut(duration: 0.2)) { step += 1 } }
                else { finish() }
            } label: {
                Text(model.t(step < stepCount - 1 ? "onboard.next" : "onboard.finish"))
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.moon).controlSize(.large)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Theme.coral : Theme.secondaryOnMaterial.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 2)
        }
        .padding(.bottom, Space.xl)
    }

    private func finish() {
        Analytics.log(.onboardingPathSelected(path: "describe"))
        Analytics.log(.onboardingCompleted)
        dismiss()
        onDescribeTask()
    }
}

private func previewModel(_ lang: AppLanguage) -> AppModel {
    let m = AppModel(); m.settings.language = lang; return m
}

#Preview("EN") { OnboardingView(onCreate: {}).environment(previewModel(.en)) }
#Preview("ES") { OnboardingView(onCreate: {}).environment(previewModel(.es)) }
