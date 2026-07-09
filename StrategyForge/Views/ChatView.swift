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
    @State private var showActivity = false
    @State private var showPreview = false
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
        HStack(spacing: 0) {
            chatColumn
            if showActivity {
                Divider()
                AgentActivityPanel(vm: vm)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showActivity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        // Reflect an auto-generated title (set in AppModel after the first message).
        .onChange(of: config.name) { _, new in editingTitle = new }
        // Auto-open the panel the first time an agent starts working.
        .onChange(of: vm.isRunning) { _, running in
            if running && vm.timeline.isEmpty && !showActivity { showActivity = true }
        }
        // Preserve unsent text when leaving this chat.
        .onDisappear { saveDraft(vm.input) }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            if !vm.deniedTools.isEmpty && !vm.isRunning { deniedStrip }
            if !vm.editedFiles.isEmpty { changedFilesStrip }
            if let error = vm.errorText { errorBanner(error) }
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .glassEffect(.regular.tint(Theme.accent.opacity(0.18)).interactive(),
                                         in: .capsule)
                    }
                    .buttonStyle(.plain)

                    if let path = config.repoPath, !path.isEmpty {
                        Text(model.t("chat.subtitle", (path as NSString).lastPathComponent))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(model.t("chat.scratch"))
                            .font(.sfCaption2).foregroundStyle(.secondary).lineLimit(1)
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
                .padding(.horizontal, 9).padding(.vertical, 3)
                .glassEffect(.regular, in: .capsule)
                .help(model.t("chat.tokens.help"))
            }
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showActivity.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .foregroundStyle(showActivity ? Theme.accent : .secondary)
            }
            .buttonStyle(.glass)
            .help(model.t("chat.activity.help"))

            Button { showInspector = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.glass)
            .help(model.t("inspector.toggle"))
        }
        .padding(Space.m)
        .background(.bar)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
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
                    MarkdownView(text: message.text + (isStreaming ? " ▍" : ""))
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

    /// A compact strip listing files the agent changed; tap to preview/export them.
    private var changedFilesStrip: some View {
        Button { showPreview = true } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "pencil.and.list.clipboard").font(.system(size: 10))
                Text(model.t("chat.changedFiles", vm.editedFiles.count)).font(.sfCaption2)
                Image(systemName: "eye").font(.system(size: 9)).opacity(0.7)
            }
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft)
        .sheet(isPresented: $showPreview) {
            DocumentPreviewSheet(files: vm.editedFiles)
        }
    }

    /// Shown after a run that was blocked by permission denials: what was blocked
    /// and a one-click "allow all & retry".
    private var deniedStrip: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "hand.raised.fill").foregroundStyle(Theme.warning).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("chat.denied", vm.deniedTools.prefix(4).joined(separator: ", ")))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            Button { vm.retryAllowingAll() } label: {
                Label(model.t("chat.allowRetry"), systemImage: "checkmark.shield")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12))
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
        VStack(alignment: .leading, spacing: Space.s) {
            if !vm.attachments.isEmpty { attachmentChips }
            HStack(spacing: Space.s) {
            // Attach files for Claude to review.
            Button {
                pickAttachments()
            } label: {
                Image(systemName: "paperclip").font(.system(size: 15))
            }
            .buttonStyle(.glass)
            .help(model.t("chat.attach"))

            TextField(model.t("chat.placeholder"),
                      text: Bindable(vm).input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(Space.s)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.innerCorner))
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
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!vm.canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
            }
        }
        .padding(Space.m)
        .background(.bar)
    }

    /// Chips for staged attachments, each removable.
    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(vm.attachments) { att in
                    HStack(spacing: 4) {
                        Image(systemName: "doc").font(.system(size: 9))
                        Text(att.name).font(.sfCaption2).lineLimit(1)
                        Button { vm.attachments.removeAll { $0.id == att.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                }
            }
        }
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = model.t("chat.attach")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            // Convert Office docs to text so Claude can read them; images/PDF/code
            // pass through. Append when ready.
            Task {
                let readable = await AttachmentConverter.convert(url)
                let att = Attachment(name: url.lastPathComponent, url: readable)
                if !vm.attachments.contains(where: { $0.name == att.name }) {
                    vm.attachments.append(att)
                }
            }
        }
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
