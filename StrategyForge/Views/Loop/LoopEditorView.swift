//
//  LoopEditorView.swift
//  StrategyForge
//
//  The loop editor: one scroll of cards — kind → goal (with guardrails) →
//  worker/verifier team → cycle diagram → run panel — with a bottom action bar
//  (repo picker, preview, generate). Mirrors StrategyEditorView's structure.
//

import SwiftUI

struct LoopEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var plan: LoopPlan
    let store: LoopStore

    @State private var showPreview = false
    @State private var showGuardrails = false
    @State private var confirmDelete = false
    @State private var didCopyLaunch = false
    @State private var banner: LocalBanner?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

    /// Inline confirmation local to this editor (never touches AppModel.banner).
    private enum LocalBanner: Equatable {
        case success(String)
        case failure(String)
    }

    private var repoURL: URL? { store.repoURL(for: plan) }
    private var intervalChoices: [Int] { [15, 30, 60, 120] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header
                kindCard
                goalCard
                teamCard
                diagramCard
                runCard
                validationSummary
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .safeAreaInset(edge: .bottom, spacing: 0) { generateBar }
        .sheet(isPresented: $showPreview) { LoopFilePreviewSheet(plan: plan) }
        .confirmationDialog(model.t("loop.delete.confirm"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button(model.t("loop.delete"), role: .destructive) { store.delete(plan.id) }
            Button(model.t("common.cancel"), role: .cancel) {}
        }
        // Persist edits, coalesced so typing doesn't write the store per keystroke.
        .onChange(of: plan) {
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                store.save()
            }
        }
        .onDisappear { store.save() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(model.t("loop.editor.name.placeholder"), text: $plan.name)
                    .textFieldStyle(.plain)
                    .font(.sfDisplay)
                Text(model.t(plan.kind.labelKey))
                    .font(.sfCallout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(model.t("loop.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    // MARK: - Card 1 · Kind

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("arrow.triangle.2.circlepath", model.t("loop.editor.kind.title"),
                          subtitle: model.t("loop.editor.kind.subtitle"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m)],
                      spacing: Space.m) {
                ForEach(LoopKind.allCases) { kind in kindCell(kind) }
            }
        }
        .card()
    }

    private func kindCell(_ kind: LoopKind) -> some View {
        let selected = plan.kind == kind
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { plan.kind = kind }
        } label: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    ZStack {
                        Circle().fill(Theme.accentSoft).frame(width: 30, height: 30)
                        Image(systemName: kind.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(model.t(kind.labelKey))
                        .font(.sfCallout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(model.t(kind.blurbKey))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(kind.flow)
                    .font(.sfFieldLabel)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkDim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(selected ? Theme.accentSoft : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .strokeBorder(selected ? Theme.accent : Theme.hairline,
                              lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.t(kind.suitsKey))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Card 2 · Goal + guardrails

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("target", model.t("loop.editor.goal.title"),
                          subtitle: model.t("loop.editor.goal.subtitle"))

            FieldLabel(text: model.t("loop.editor.goal.label"))
            textEditor($plan.goal, placeholder: model.t("loop.editor.goal.placeholder"), height: 76)

            // Good vs bad example, so "verifiable" is concrete.
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success).font(.system(size: 11))
                    Text(model.t("loop.editor.goal.good"))
                        .font(.sfCaption2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.danger).font(.system(size: 11))
                    Text(model.t("loop.editor.goal.bad"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))

            DisclosureGroup(isExpanded: $showGuardrails) {
                VStack(alignment: .leading, spacing: Space.m) {
                    FieldLabel(text: model.t("loop.editor.neverTouch.label"))
                    textEditor($plan.neverTouch,
                               placeholder: model.t("loop.editor.neverTouch.placeholder"), height: 56)
                    FieldLabel(text: model.t("loop.editor.stopIf.label"))
                    textEditor($plan.stopIf,
                               placeholder: model.t("loop.editor.stopIf.placeholder"), height: 56)
                }
                .padding(.top, Space.s)
            } label: {
                Label(model.t("loop.editor.guardrails"), systemImage: "shield.lefthalf.filled")
                    .font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            HStack(spacing: Space.l) {
                Stepper(value: $plan.maxTurns, in: 1...100) {
                    Text(model.t("loop.editor.maxTurns", plan.maxTurns))
                        .font(.sfCallout).monospacedDigit()
                }
                .fixedSize()
                Text(model.t("loop.editor.maxTurns.brake"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if plan.kind == .timeBased {
                VStack(alignment: .leading, spacing: Space.xs) {
                    FieldLabel(text: model.t("loop.editor.interval"))
                    Picker("", selection: $plan.intervalMinutes) {
                        ForEach(intervalChoices, id: \.self) { m in
                            Text(model.t("loop.editor.minutes", m)).tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }
        }
        .card()
    }

    /// A TextEditor with an inset border and a placeholder (TextEditor has none).
    private func textEditor(_ text: Binding<String>, placeholder: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11).padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Card 3 · Team of the loop

    private var teamCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("person.2.fill", model.t("loop.editor.team.title"),
                          subtitle: model.t("loop.editor.team.subtitle"))

            FieldLabel(text: model.t("loop.editor.worker"))
            modelChips($plan.workerModel, enabled: true)

            Divider()

            Toggle(isOn: $plan.verifierEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.verifier")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.verifier.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            if plan.verifierEnabled {
                FieldLabel(text: model.t("loop.editor.verifier.model"))
                modelChips($plan.verifierModel, enabled: plan.verifierEnabled)
            }

            Divider()

            Toggle(isOn: $plan.memoryEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.t("loop.editor.memory")).font(.sfCallout.weight(.medium))
                    Text(model.t("loop.editor.memory.why"))
                        .font(.sfCaption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        .card()
    }

    /// Model chips mirroring RoleEditorForm.modelGrid (tier icon + tier + name).
    private func modelChips(_ selection: Binding<ClaudeModel>, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(ClaudeModel.allCases) { m in
                let selected = selection.wrappedValue == m
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        selection.wrappedValue = m
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: m.tierIcon).font(.system(size: 12))
                            .foregroundStyle(selected ? Theme.accent : .secondary)
                        Text(model.t(m.tierNameKey))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? .primary : .secondary)
                            .lineLimit(1)
                        Text(m.displayName)
                            .font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? Theme.accentSoft : Theme.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? Theme.accent : Theme.hairline,
                                      lineWidth: selected ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(m.safeguardNote ?? model.t(m.tierBlurbKey))
                .accessibilityLabel("\(model.t(m.tierNameKey)) — \(m.displayName)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .opacity(enabled ? 1 : 0.5)
    }

    // MARK: - Card 4 · Diagram

    private var diagramCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("point.3.connected.trianglepath.dotted",
                          model.t("loop.editor.diagram.title"),
                          subtitle: model.t("loop.editor.diagram.subtitle"))
            LoopDiagramView(plan: plan, isLive: false)
                .frame(height: 150)
        }
        .card()
    }

    // MARK: - Card 5 · Run panel (built by another module)

    private var runCard: some View {
        LoopRunPanel(plan: plan, repoURL: repoURL, binary: model.settings.claudeBinary)
    }

    // MARK: - Validation summary

    @ViewBuilder
    private var validationSummary: some View {
        let issues = plan.validate()
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(issues, id: \.self) { key in
                    let isWarning = key == "loop.issue.noVerifier"
                    Label(model.t(key), systemImage: isWarning
                          ? "exclamationmark.triangle.fill" : "exclamationmark.octagon.fill")
                        .font(.sfCallout)
                        .foregroundStyle(isWarning ? Theme.warning : Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.warning.opacity(0.10)))
        }
    }

    // MARK: - Bottom action bar

    private var generateBar: some View {
        VStack(spacing: Space.m) {
            bannerView
            launchRow

            if repoURL == nil {
                Text(model.t("loop.editor.needRepo"))
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: Space.m) {
                Button {
                    store.pickRepo(for: plan.id)
                } label: {
                    Label(plan.repoPath.map { ($0 as NSString).lastPathComponent }
                          ?? model.t("loop.editor.chooseRepo"),
                          systemImage: "folder")
                }
                .controlSize(.large)
                .lineLimit(1)
                .help(model.t("loop.editor.chooseRepo.help"))

                Button {
                    showPreview = true
                } label: {
                    Label(model.t("loop.editor.preview"), systemImage: "doc.text.magnifyingglass")
                }
                .controlSize(.large)
                .lineLimit(1)

                Spacer(minLength: Space.s)

                Button {
                    generate()
                } label: {
                    Label(model.t("loop.editor.generate"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.moon)
                .controlSize(.large)
                .disabled(repoURL == nil)
                .help(model.t("loop.editor.generate.help"))
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// The launch command, copyable — mirrors PreviewPanelView.launchBlock.
    private var launchRow: some View {
        let command = LoopFileGenerator.launchCommand(for: plan, binary: model.settings.claudeBinary)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(command.components(separatedBy: "\n").first ?? command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(command, forType: .string)
                didCopyLaunch = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopyLaunch = false
                }
            } label: {
                Image(systemName: didCopyLaunch ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(didCopyLaunch ? Theme.success : Theme.accent)
            }
            .buttonStyle(.borderless)
            .help(model.t("loop.editor.copyLaunch"))
            .accessibilityLabel(model.t("loop.editor.copyLaunch"))
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.insetBg)
                .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                    .strokeBorder(Theme.hairline))
        )
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            let isSuccess: Bool = { if case .success = banner { return true }; return false }()
            let text: String = {
                switch banner {
                case .success(let m): return m
                case .failure(let m): return m
                }
            }()
            HStack(spacing: 8) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { self.banner = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.t("common.done"))
            }
            .padding(Space.m)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner)
                .fill(isSuccess ? Theme.success : Theme.danger))
        }
    }

    // MARK: - Actions

    private func generate() {
        guard let url = repoURL else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let written = try LoopWriter(repoURL: url, binary: model.settings.claudeBinary)
                .write(plan: plan)
            show(.success(model.t("loop.editor.generated", written.count, url.lastPathComponent)))
            store.save()
        } catch {
            show(.failure(model.t("loop.editor.generateFailed", error.localizedDescription)))
        }
    }

    private func show(_ newBanner: LocalBanner) {
        banner = newBanner
        bannerDismissTask?.cancel()
        if case .success = newBanner {
            bannerDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if banner == newBanner { banner = nil }
            }
        }
    }
}

// MARK: - File preview sheet

/// A read-only preview of every file the loop would write, mirroring
/// FilePreviewSheet (segmented tabs + monospaced contents).
private struct LoopFilePreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: LoopPlan

    @State private var selectedFile: String?

    var body: some View {
        let files = LoopFileGenerator.generate(for: plan)
        let ids = files.map(\.id)
        let effective = (selectedFile.flatMap { ids.contains($0) ? $0 : nil }) ?? files.first?.id

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.t("loop.preview.title")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Space.l)
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { effective }, set: { selectedFile = $0 })) {
                    ForEach(files) { file in
                        Text(file.displayName).tag(Optional(file.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, Space.l).padding(.top, Space.m)

                let current = files.first { $0.id == effective }
                ScrollView {
                    Text(current?.contents ?? "")
                        .font(.sfCode)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.l)
                }
                .background(Theme.insetBg)
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 560, idealHeight: 640)
    }
}
