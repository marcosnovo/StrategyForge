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
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .fill(Theme.insetBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
                .strokeBorder(hasError ? Theme.danger.opacity(0.55) : Theme.hairline, lineWidth: 1)
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
        .background(Capsule().fill(Theme.cardBg).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1)))
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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            modelField
            HStack(alignment: .bottom, spacing: 16) {
                labeled("field.instances") { countStepper }
                labeled("field.tools") { toolsMenu }
                Spacer(minLength: 0)
            }
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

    /// Model picker + a capability-tier hint, separate from Claude Code's runtime
    /// effort setting.
    private var modelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FieldLabel(text: model.t("field.model"))
                InfoPopoverButton(text: model.t("glossary.modelEffort"))
                Spacer()
                providerMenu
            }
            if role.provider == .claude {
                modelGrid
                if let note = role.model.safeguardNote {
                    Label(note, systemImage: "info.circle")
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

    /// Per-role AI back-end — this is what enables cross-provider "mixes".
    private var providerMenu: some View {
        Menu {
            ForEach(AIProvider.allCases) { p in
                if model.isConnected(p) {
                    Button {
                        role.provider = p
                        role.providerModelID = p == .claude ? nil : p.models.first?.id
                    } label: {
                        Label(p.displayName, systemImage: role.provider == p ? "checkmark" : p.icon)
                    }
                } else {
                    Button { model.navSection = .services; model.selectedService = p } label: {
                        Label("\(p.displayName) — \(model.t("provider.locked"))", systemImage: "lock.fill")
                    }
                }
            }
            Divider()
            Button(model.t("provider.manage")) { model.navSection = .services }
        } label: {
            HStack(spacing: 3) {
                ProviderLogo(provider: role.provider, size: 11, templateTint: role.provider.tint)
                Text(role.provider.displayName).font(.sfCaption2.weight(.semibold))
            }
            .foregroundStyle(role.provider.tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(role.provider.tint.opacity(0.14)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
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
                            .font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
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
                    if m.safeguardNote != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7)).foregroundStyle(Theme.warning)
                    }
                }
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
                .strokeBorder(selected ? Theme.accent
                              : (hoveredModel == m ? Theme.accent.opacity(0.5) : Theme.hairline),
                              lineWidth: selected ? 1.5 : 1))
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
        .help(m.safeguardNote ?? model.t(m.tierBlurbKey))
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
