//
//  RoleRowView.swift
//  StrategyForge
//
//  One editable row in the roles table (compact list) plus RoleEditorForm — the
//  full role editor (model/provider grid, count, tools, prompts) shared by the
//  legacy Configure sheet and the visual Team canvas' inline detail panel.
//

import SwiftUI

struct RoleRowView: View {
    @Environment(AppModel.self) private var model
    @Binding var role: AgentRole
    /// Validation issues that target this specific role.
    let issues: [Strategy.ValidationIssue]

    @State private var configuring = false

    private var hasError: Bool { issues.contains { $0.severity == .error } }

    var body: some View {
        // COMPACT row: badge + name + a one-line summary + a Configure button.
        // Everything advanced (model, provider, tools, prompts) lives in a sheet so
        // beginners see a clean team list and only dive in when they want to.
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: 10) {
                RoleBadge(kind: role.role, name: model.roleKindName(role.role))
                if role.isOrchestrator {
                    Text(role.name)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(model.t("role.namePlaceholder"), text: $role.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity)
                }
                Button { configuring = true } label: {
                    Label(model.t("role.configure"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered).controlSize(.small).fixedSize()
            }

            RoleSummaryChip(role: role)

            if role.isOrchestrator {
                Label(model.t("role.orchestratorNote"), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(model.t("role.orchestratorNote"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(issues) { issue in
                Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.sfCaption2)
                    .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(role.isOrchestrator ? Theme.accentSoft.opacity(0.6) : Theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(hasError ? Theme.danger.opacity(0.55)
                              : (role.isOrchestrator ? Theme.accent.opacity(0.30) : Theme.hairline),
                              lineWidth: 1)
        )
        .sheet(isPresented: $configuring) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("\(model.roleKindName(role.role)) — \(role.name)").font(.sfCardTitle)
                RoleEditorForm(role: $role, issues: issues)
                HStack { Spacer(); Button(model.t("common.done")) { configuring = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(Space.l)
            .frame(width: 540)
        }
    }
}

/// A one-line summary of a role's setup (provider · model · count · tools).
struct RoleSummaryChip: View {
    @Environment(AppModel.self) private var model
    let role: AgentRole
    var body: some View {
        HStack(spacing: 5) {
            ProviderLogo(provider: role.provider, size: 12, templateTint: role.provider.tint)
            Text(role.modelDisplayName).font(.sfCaption2.weight(.medium))
            Text("· ×\(role.count)").font(.sfCaption2).foregroundStyle(.secondary)
            if !role.tools.isEmpty {
                Text("· \(model.t("role.toolsCount", role.tools.count))").font(.sfCaption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        // Workers get a faint teal team wash (teal = agents); the orchestrator stays neutral.
        .background(Capsule().fill(role.isOrchestrator ? Theme.cardBg : Theme.tealSoft)
            .overlay(Capsule().strokeBorder(role.isOrchestrator ? Theme.hairline : Theme.tealEdge, lineWidth: 1)))
    }
}

// MARK: - Reusable role editor

/// The full editor for a single role: model/provider capability grid, instance
/// count, tools, and the system-prompt / description editors. Used both by the
/// legacy Configure sheet and the visual Team canvas' inline detail panel.
struct RoleEditorForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var role: AgentRole
    var issues: [Strategy.ValidationIssue] = []

    @State private var hoveredModel: ClaudeModel?
    /// Prompts are advanced — collapsed by default so the panel stays clean.
    @State private var showInstructions = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            aiChoiceCard
            HStack(alignment: .bottom, spacing: 16) {
                labeled("field.instances") { countStepper }
                labeled("field.tools") { toolsMenu }
                Spacer(minLength: 0)
            }
            // Persistent per-agent memory (subagents only — the orchestrator has no
            // agent file). Off by default; on, the role carries learnings across runs.
            if !role.isOrchestrator {
                Toggle(isOn: $role.memoryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t("role.memory")).font(.sfCallout.weight(.medium))
                        Text(model.t("role.memory.why"))
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            DisclosureGroup(isExpanded: $showInstructions) {
                VStack(alignment: .leading, spacing: Space.m) {
                    labeled("role.systemPrompt") {
                        TextEditor(text: $role.systemPrompt)
                            .font(.body.monospaced()).frame(height: 120)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    }
                    labeled("role.description") {
                        TextEditor(text: $role.description)
                            .font(.body.monospaced()).frame(height: 80)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    }
                }
                .padding(.top, Space.s)
            } label: {
                Label(model.t("role.instructions"), systemImage: "text.alignleft")
                    .font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(issues) { issue in
                Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.sfCaption2)
                    .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Controls

    /// A small caption label stacked above a control.
    private func labeled<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(text: model.t(key))
            content()
        }
    }

    /// The heart of the panel: WHICH AI (the provider) and HOW SMART (the model),
    /// wrapped in ONE inset card so they read as a single, obvious decision —
    /// "pick the AI, then pick how powerful it is."
    private var aiChoiceCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // 1. WHICH AI — a visible row of provider cards (was a tiny corner menu).
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    FieldLabel(text: model.t("field.aiProvider"))
                    InfoPopoverButton(text: model.t("glossary.aiProvider"))
                    Spacer()
                }
                aiProviderRow
            }
            // 2. HOW SMART — the model tier grid for the chosen provider.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    FieldLabel(text: model.t("field.model"))
                    InfoPopoverButton(text: model.t("glossary.modelEffort"))
                    Spacer()
                }
                if role.provider == .claude {
                    modelGrid
                    if let noteKey = role.model.safeguardNoteKey {
                        Label(model.t(noteKey), systemImage: "info.circle")
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    providerModelGrid
                    if !role.provider.isExecutable {
                        Label(model.t("provider.soon.note"), systemImage: "clock")
                            .font(.sfCaption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    /// The "which AI" control: one tappable card per provider. This is what enables
    /// cross-provider "mixes" — each agent can run on a different AI.
    private var aiProviderRow: some View {
        HStack(spacing: Space.s) {
            ForEach(AIProvider.allCases) { p in
                Button {
                    if model.isConnected(p) {
                        role.provider = p
                        role.providerModelID = p == .claude ? nil : p.models.first?.id
                    } else {
                        // Not connected yet — send the user straight to Connect.
                        model.navSection = .services
                        model.selectedService = p
                    }
                } label: { providerCard(p) }
                .buttonStyle(.plain)
                .help(model.isConnected(p) ? p.displayName : model.t("provider.locked"))
            }
        }
    }

    /// One provider card: brand logo + name, tinted in the provider's color when
    /// selected. An unconnected provider is dimmed with a lock and, when tapped,
    /// routes to Connect instead of selecting.
    private func providerCard(_ p: AIProvider) -> some View {
        let selected = role.provider == p
        let connected = model.isConnected(p)
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ProviderLogo(provider: p, size: 24, templateTint: connected ? p.tint : Theme.inkDim)
                    .frame(maxWidth: .infinity)
                if !connected {
                    Image(systemName: "lock.fill").scaledFont(8).foregroundStyle(Theme.inkDim)
                }
            }
            Text(p.displayName)
                .font(.sfCaption2.weight(.semibold))
                .foregroundStyle(selected ? p.tint : .secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 6)
        .opacity(connected ? 1 : 0.6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? p.tint.opacity(0.12) : Theme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? p.tint : Theme.hairline, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
    }

    /// Model grid for a non-Claude provider (writes providerModelID).
    private var providerModelGrid: some View {
        HStack(spacing: 6) {
            ForEach(role.provider.models) { m in
                let selected = (role.providerModelID ?? role.provider.models.first?.id) == m.id
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { role.providerModelID = m.id }
                } label: {
                    VStack(spacing: 3) {
                        Text(model.t(m.tierKey))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
                        Text(m.displayName)
                            .scaledFont(8).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? role.provider.tint.opacity(0.16) : Theme.cardBg))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? role.provider.tint : Theme.hairline,
                                      lineWidth: selected ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A capability grid: one card per Claude model showing tier icon/name.
    private var modelGrid: some View {
        HStack(spacing: 6) {
            ForEach(ClaudeModel.allCases) { m in modelChip(m) }
        }
    }

    private func modelChip(_ m: ClaudeModel) -> some View {
        let selected = role.model == m
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { role.model = m }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: m.tierIcon).font(.system(size: 12))
                        .foregroundStyle(selected ? Theme.accent : .secondary)
                    if m.safeguardNoteKey != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .scaledFont(7).foregroundStyle(Theme.warning)
                    }
                }
                Text(model.t(m.tierNameKey))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                Text(m.displayName)
                    .scaledFont(8).foregroundStyle(.tertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Theme.selectionFill : Theme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Theme.selectionBorder
                              : (hoveredModel == m ? Theme.accent.opacity(0.5) : Theme.hairline),
                              lineWidth: 1))
            .contentShape(Rectangle())
            .scaleEffect(hoveredModel == m && !selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                if hovering { hoveredModel = m }
                else if hoveredModel == m { hoveredModel = nil }
            }
        }
        .help(m.safeguardNoteKey.map { model.t($0) } ?? model.t(m.tierBlurbKey))
        .accessibilityLabel("\(model.t(m.tierNameKey)) — \(m.displayName)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var countStepper: some View {
        if role.isOrchestrator {
            Text("×1")
                .foregroundStyle(.secondary)
                .frame(height: 20)
                .help(model.t("role.count.orchestratorHelp"))
        } else {
            Stepper(value: $role.count, in: 1...20) {
                Text("×\(role.count)")
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private var toolsMenu: some View {
        Menu {
            Button(model.t("role.inheritAll")) { role.tools = [] }
            Divider()
            ForEach(Constants.availableTools, id: \.self) { tool in
                Button {
                    toggle(tool)
                } label: {
                    if role.tools.contains(tool) {
                        Label(tool, systemImage: "checkmark")
                    } else {
                        Text(tool)
                    }
                }
            }
        } label: {
            Text(toolsSummary)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .help(model.t("role.tools.help"))
        .accessibilityValue(toolsSummary)
    }

    private var toolsSummary: String {
        role.tools.isEmpty ? model.t("role.toolsAll") : model.t("role.toolsCount", role.tools.count)
    }

    private func toggle(_ tool: String) {
        if let idx = role.tools.firstIndex(of: tool) {
            role.tools.remove(at: idx)
        } else {
            role.tools.append(tool)
        }
    }
}

/// Small colored capsule showing the role kind.
struct RoleBadge: View {
    let kind: RoleKind
    /// Localized display name for the kind.
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(kind.tint.opacity(0.18)))
            .foregroundStyle(kind.tint)
            .frame(width: 96, alignment: .center)
            .accessibilityLabel(name)
    }
}

/// A reusable sheet with a large multiline text editor.
struct TextEditingSheet: View {
    let title: String
    let subtitle: String
    @Binding var text: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 520, minHeight: 320)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Spacer()
                Button(model.t("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
