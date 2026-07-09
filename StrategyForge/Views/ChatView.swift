//
//  ChatView.swift
//  StrategyForge
//
//  The "work here" chat: after designing the strategy, talk to Claude directly.
//  Claude Code runs headless in the project's repo (honoring the generated
//  .claude/agents + CLAUDE.md), edits files directly, and streams its replies.
//  No code pane — just the conversation, like a focused agent chat.
//

import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Binding var showInspector: Bool
    @Binding var showSidebar: Bool
    /// Live configuration for header display (title/strategy/repo), re-passed by the
    /// parent so edits made in the config sheet reflect immediately.
    let config: Configuration
    @State private var vm: ChatViewModel
    @State private var editingTitle: String
    private let rename: (String) -> Void
    private let saveDraft: (String) -> Void

    init(config: Configuration, binary: String,
         permissionMode: String = "acceptEdits",
         showInspector: Binding<Bool> = .constant(false),
         showSidebar: Binding<Bool> = .constant(true),
         persist: @escaping ([ChatMessage]) -> Void = { _ in },
         rename: @escaping (String) -> Void = { _ in },
         autoTitle: @escaping (String) -> Void = { _ in },
         saveDraft: @escaping (String) -> Void = { _ in },
         ensureStrategyFiles: @escaping () -> Void = {},
         persistUsage: @escaping (Int, Double) -> Void = { _, _ in }) {
        self.config = config
        self.rename = rename
        self.saveDraft = saveDraft
        _showInspector = showInspector
        _showSidebar = showSidebar
        _editingTitle = State(initialValue: config.name)
        _vm = State(initialValue: ChatViewModel(config: config, binary: binary,
                                                permissionMode: permissionMode,
                                                persist: persist, onFirstUserMessage: autoTitle,
                                                ensureStrategyFiles: ensureStrategyFiles,
                                                persistUsage: persistUsage))
    }

    init(viewModel: ChatViewModel, showInspector: Binding<Bool> = .constant(false)) {
        self.config = viewModel.config
        self.rename = { _ in }
        self.saveDraft = { _ in }
        _showInspector = showInspector
        _showSidebar = .constant(true)
        _editingTitle = State(initialValue: viewModel.config.name)
        _vm = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            if !vm.editedFiles.isEmpty { changedFilesStrip }
            if let error = vm.errorText { errorBanner(error) }
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        // Reflect an auto-generated title (set in AppModel after the first message).
        .onChange(of: config.name) { _, new in editingTitle = new }
        // Preserve unsent text when leaving this chat.
        .onDisappear { saveDraft(vm.input) }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            IconBadge(systemName: "bubble.left.and.text.bubble.right.fill")
            VStack(alignment: .leading, spacing: 3) {
                // The chat title — the H1, editable inline.
                TextField(model.t("chat.untitled"), text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.sfCardTitle)
                    .onSubmit { rename(editingTitle) }

                HStack(spacing: Space.s) {
                    // Strategy pill doubles as an entry point to the config sheet.
                    Button { showInspector = true } label: {
                        Text(model.strategyDisplayName(config.strategy))
                            .font(.sfCaption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent.opacity(0.15)))
                    }
                    .buttonStyle(.plain)

                    if let path = config.repoPath {
                        Text(model.t("chat.subtitle", (path as NSString).lastPathComponent))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(model.t("chat.needRepo"))
                            .font(.sfCaption2).foregroundStyle(Theme.warning).lineLimit(1)
                    }
                }
            }
            Spacer()
            if vm.totalTokens > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "circle.hexagongrid").font(.system(size: 9))
                    Text(model.t("chat.tokens", formatTokens(vm.totalTokens)))
                        .font(.sfCaption2.weight(.semibold))
                    if vm.totalCostUSD > 0 {
                        Text(String(format: "· $%.2f", vm.totalCostUSD))
                            .font(.sfCaption2)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.hairline))
                .help(model.t("chat.tokens.help"))
            }
            Button { showInspector = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(model.t("inspector.toggle"))
        }
        .padding(Space.m)
        .background(.bar)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    /// Render Claude's markdown while PRESERVING newlines (plain markdown parsing
    /// collapses single newlines into spaces, which produced the wall of text).
    private func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.m) {
                    if vm.messages.isEmpty { emptyState }
                    ForEach(vm.messages) { message in
                        bubble(message,
                               isStreaming: vm.isRunning
                                   && message.role == .assistant
                                   && message.id == vm.messages.last?.id)
                            .id(message.id)
                    }
                    if vm.isRunning { activityRow.id("activity") }
                }
                .padding(Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: vm.messages.last?.text) { scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage, isStreaming: Bool) -> some View {
        if message.role == .user {
            // User: compact bubble on the right.
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.sfBodyM)
                    .foregroundStyle(Theme.onAccent)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.accent))
                    .contextMenu { copyButton(message.text) }
            }
        } else {
            // Assistant: full-width, no bubble (like Claude/ChatGPT) with an avatar.
            HStack(alignment: .top, spacing: Space.m) {
                Group {
                    if isStreaming {
                        WorkingLogo(size: 20)
                    } else {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.accentSoft))
                    }
                }
                .frame(width: 24, height: 24)
                .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    (Text(rendered(message.text))
                        + (isStreaming ? Text(" ▍").foregroundColor(Theme.accent) : Text("")))
                        .font(.sfBodyM)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isStreaming {
                        Button { copyToClipboard(message.text) } label: {
                            Label(model.t("chat.copy"), systemImage: "doc.on.doc").font(.sfCaption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                    }
                }
                .contextMenu { copyButton(message.text) }
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            copyToClipboard(text)
        } label: {
            Label(model.t("chat.copy"), systemImage: "doc.on.doc")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(model.t("chat.empty"))
                .font(.sfCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(["chat.suggest1", "chat.suggest2", "chat.suggest3"], id: \.self) { key in
                    Button { vm.input = model.t(key) } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: "arrow.up.forward.square").foregroundStyle(Theme.accent)
                            Text(model.t(key)).font(.sfCallout).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                            .fill(Theme.cardBg)
                            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                                .strokeBorder(Theme.hairline, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 520)
        }
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activityRow: some View {
        HStack(spacing: Space.s) {
            WorkingLogo(size: 18)
            if let sub = vm.activeSubagent {
                // Show the strategy at work: which teammate the orchestrator called.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                    Text(model.t("chat.delegating", sub)).font(.sfCaption2.weight(.medium))
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(vm.activity.isEmpty
                     ? model.t("chat.thinking")
                     : model.t("chat.using", Array(vm.activity.suffix(3)).joined(separator: ", ")))
                    .font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
    }

    /// A compact strip listing files the agent changed; each reveals in Finder.
    private var changedFilesStrip: some View {
        Menu {
            ForEach(vm.editedFiles, id: \.self) { path in
                Button((path as NSString).lastPathComponent) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "pencil.and.list.clipboard").font(.system(size: 10))
                Text(model.t("chat.changedFiles", vm.editedFiles.count)).font(.sfCaption2)
            }
            .foregroundStyle(Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft)
    }

    private func errorBanner(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.10))
    }

    private var inputBar: some View {
        HStack(spacing: Space.s) {
            TextField(model.t(vm.config.repoPath == nil ? "chat.needRepo" : "chat.placeholder"),
                      text: Bindable(vm).input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
                .onSubmit { send() }
                // Up arrow on an empty field recalls the last message to edit/resend.
                .onKeyPress(.upArrow) {
                    guard vm.input.isEmpty,
                          let last = vm.messages.last(where: { $0.role == .user }) else { return .ignored }
                    vm.input = last.text
                    return .handled
                }

            if vm.isRunning {
                Button { vm.stop() } label: {
                    Label(model.t("chat.stop"), systemImage: "stop.fill")
                }
                .controlSize(.large)
            } else {
                Button { send() } label: {
                    Label(model.t("chat.send"), systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(Space.m)
        .background(.bar)
    }

    private func send() {
        vm.send()
        saveDraft("")   // sent → clear the persisted draft
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if vm.isRunning {
                proxy.scrollTo("activity", anchor: .bottom)
            } else if let last = vm.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ChatPreviewHost: View {
    var body: some View {
        let vm = ChatViewModel(
            config: Configuration(name: "Demo", strategy: StrategyLibrary.orchestratorWorkers(),
                                  repoPath: "/Users/me/Projects/my-app"),
            binary: "claude")
        vm.messages = [
            .init(role: .user, text: "Add a dark mode toggle and update the tests."),
            .init(role: .assistant, text: "I'll add a `colorScheme` toggle to **Settings**, thread it through the theme, and update the snapshot tests. Starting now…"),
        ]
        return ChatView(viewModel: vm)
            .environment(AppModel())
            .tint(Theme.accent)
    }
}

#Preview("Chat") { ChatPreviewHost() }
#Preview("Chat (Dark)") { ChatPreviewHost().preferredColorScheme(.dark) }
