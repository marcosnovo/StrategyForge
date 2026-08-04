//
//  ProviderConnectSheet.swift
//  StrategyForge
//
//  One simple, direct "Connect" flow for a provider — Coral does everything: it
//  installs the CLI silently if it's missing (to a user-writable prefix, no sudo),
//  then runs the web sign-in (opens the browser, no Terminal). A two-step indicator
//  makes the (few) steps clear; a Terminal fallback appears only if something fails.
//

import SwiftUI

struct ProviderConnectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    /// Called after a successful connect so the caller can re-detect.
    var onConnected: () -> Void = {}

    enum Phase: Equatable { case installing, signingIn, terminal, node, done, failed(String) }
    @State private var phase: Phase = .installing
    @State private var log: [String] = []
    @State private var url: String?
    /// Set while Node.js is being installed via Homebrew (before we can install the CLI).
    @State private var installingNode = false
    /// Claude's login finishes by pasting a code shown in the browser — we collect it
    /// here and send it into the (hidden) login process.
    @State private var awaitingCode = false
    @State private var code = ""
    @State private var input = LoginInput()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                ProviderLogo(provider: provider, size: 18, templateTint: provider.tint)
                Text(model.t("provider.connect.title", provider.displayName)).font(.sfCardTitle)
                Spacer()
                if phase == .installing || phase == .signingIn || installingNode { ThinkingOrb(state: .connecting, size: 18) }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: Theme.innerCorner)

            steps

            statusLine

            if phase == .signingIn, let url, let u = URL(string: url) {
                // Make the browser step impossible to miss: a loud hint + the open button.
                Label(model.t("provider.signin.browserHint"), systemImage: "safari.fill")
                    .font(.sfCaption2).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: u) {
                    Label(model.t("provider.signin.openPage"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.moon)
            }
            // Node.js is missing — the one true prerequisite. Offer a one-tap Homebrew
            // install when brew is present, else a link to the Node.js download page.
            if phase == .node {
                VStack(alignment: .leading, spacing: Space.s) {
                    if installingNode {
                        Label(model.t("provider.node.installing"), systemImage: "arrow.down.circle")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if ProviderInstaller.hasHomebrew() {
                        Button(action: installNodeThenRetry) {
                            Label(model.t("provider.node.brew"), systemImage: "shippingbox.fill")
                        }
                        .buttonStyle(.moon)
                    } else {
                        Link(destination: ProviderInstaller.nodeDownloadURL) {
                            Label(model.t("provider.node.download"), systemImage: "arrow.down.app")
                        }
                        .buttonStyle(.moon)
                        Text(model.t("provider.node.manual"))
                            .font(.sfCaption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // Paste-the-code step (Claude): the browser shows a code to paste back.
            if awaitingCode {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(model.t("provider.signin.pasteCode"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.s) {
                        TextField(model.t("provider.signin.codePlaceholder"), text: $code)
                            .textFieldStyle(.roundedBorder).font(.sfCode)
                            .onSubmit(submitCode)
                        Button(model.t("provider.signin.submitCode"), action: submitCode)
                            .buttonStyle(.moon)
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            if phase == .terminal {
                Button(model.t("provider.signin.terminal")) { ProviderInstaller.launchSignIn(provider) }
                    .buttonStyle(.moon)
            }
            if case .failed = phase {
                Button(model.t("provider.signin.terminal")) { ProviderInstaller.launchSignIn(provider) }
                    .buttonStyle(.reefOutline)
            }

            ScrollView {
                Text(log.suffix(200).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 120)
            .padding(Space.s)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg))

            HStack {
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
        .frame(width: 460)
        .task { await run() }
    }

    // MARK: Steps

    private var steps: some View {
        HStack(spacing: Space.s) {
            stepPill(1, model.t("provider.connect.step.install"),
                     state: phase == .installing ? .active : .done)
            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            stepPill(2, model.t("provider.connect.step.signin"),
                     state: (phase == .signingIn || phase == .terminal) ? .active : (phase == .done ? .done : .pending))
        }
    }

    private enum StepState { case pending, active, done }
    private func stepPill(_ n: Int, _ label: String, state: StepState) -> some View {
        let color: Color = state == .active ? Theme.accent : (state == .done ? Theme.success : Theme.secondaryOnMaterial)
        return HStack(spacing: 5) {
            if state == .done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
            } else {
                Text("\(n)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 15, height: 15).background(Circle().fill(color.opacity(0.18)))
            }
            Text(label).font(.sfCaption2.weight(.medium))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .installing:
            Label(model.t("provider.connect.installing"), systemImage: "arrow.down.circle")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .signingIn:
            Label(model.t("provider.signin.waiting"), systemImage: "safari")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .terminal:
            Label(model.t("provider.signin.terminalNote"), systemImage: "terminal")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .node:
            VStack(alignment: .leading, spacing: 2) {
                Label(model.t("provider.node.title"), systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(Theme.warning)
                Text(model.t("provider.node.desc"))
                    .font(.sfCaption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            Label(model.t("provider.connect.done"), systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(Theme.success)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run() async {
        for await event in ProviderInstaller.connect(provider, input: input) {
            switch event {
            case .phase(let s): phase = (s == .installing ? .installing : .signingIn)
            case .log(let l): log.append(l)
            case .url(let u): url = u
            case .needsCode: awaitingCode = true
            case .needsNode: phase = .node
            case .needsTerminal: phase = .terminal
            case .failed(let m): phase = .failed(m)
            case .done: phase = .done; awaitingCode = false; onConnected()
            }
        }
    }

    /// Install Node.js via Homebrew, then restart the whole connect flow (install CLI →
    /// sign in) now that npm is available.
    private func installNodeThenRetry() {
        installingNode = true
        Task {
            for await ev in ProviderInstaller.installNode() {
                switch ev {
                case .log(let l): log.append(l)
                case .finished:
                    installingNode = false
                    phase = .installing
                    await run()
                    return
                case .failed(let m): installingNode = false; phase = .failed(m); return
                case .needsNode: installingNode = false   // brew vanished — stay on .node (link fallback)
                case .needsCode: break
                }
            }
        }
    }

    /// Send the pasted browser code into the login process; a spinner then shows while
    /// the CLI validates it and finishes.
    private func submitCode() {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        input.submit(trimmed)
        code = ""
        awaitingCode = false   // back to the "signing in" spinner until .done/.failed
    }
}
