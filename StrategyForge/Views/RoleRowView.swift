//
//  RoleRowView.swift
//  StrategyForge
//
//  One editable row in the roles table: name, role badge, model picker (with
//  Fable safeguard tooltip), count stepper, tools multi-select, and buttons to
//  edit the system prompt and description in sheets.
//

import SwiftUI

struct RoleRowView: View {
    @Environment(AppModel.self) private var model
    @Binding var role: AgentRole
    /// Validation issues that target this specific role.
    let issues: [Strategy.ValidationIssue]

    @State private var editingPrompt = false
    @State private var editingDescription = false
    @State private var hoveredModel: ClaudeModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasError: Bool { issues.contains { $0.severity == .error } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name row: badge + editable name, name flexible so it never overflows.
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
            }

            // Model as a visual capability grid, then the smaller controls below it.
            modelField
            HStack(alignment: .bottom, spacing: 16) {
                labeled("field.instances") { countStepper }
                labeled("field.tools") { toolsMenu }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    editingPrompt = true
                } label: {
                    Label(model.t("role.systemPrompt"), systemImage: "text.alignleft")
                }
                Button {
                    editingDescription = true
                } label: {
                    Label(model.t("role.description"), systemImage: "arrow.triangle.branch")
                }
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if role.isOrchestrator {
                Label(model.t("role.orchestratorNote"), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .sheet(isPresented: $editingPrompt) {
            TextEditingSheet(
                title: "\(model.t("role.systemPrompt")) — \(role.name)",
                subtitle: model.t("sheet.systemPrompt.subtitle"),
                text: $role.systemPrompt
            )
        }
        .sheet(isPresented: $editingDescription) {
            TextEditingSheet(
                title: "\(model.t("role.description")) — \(role.name)",
                subtitle: model.t("sheet.description.subtitle"),
                text: $role.description
            )
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

    /// Model picker + a capability-tier hint (Specialist / Expert / Generalist /
    /// Fast) and a model-vs-effort explainer, so the model choice is understood as
    /// "how capable", separate from Claude Code's runtime effort setting.
    private var modelField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FieldLabel(text: model.t("field.model"))
                InfoPopoverButton(text: model.t("glossary.modelEffort"))
            }
            modelGrid
            // The redirect caveat (e.g. Fable → Opus) shown inline when relevant.
            if let note = role.model.safeguardNote {
                Label(note, systemImage: "info.circle")
                    .font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A capability grid: one card per model showing its tier icon, tier name and
    /// model name, so "how capable" is legible at a glance instead of a bare menu.
    private var modelGrid: some View {
        HStack(spacing: 6) {
            ForEach(ClaudeModel.allCases) { m in modelChip(m) }
        }
    }

    private func modelChip(_ m: ClaudeModel) -> some View {
        let selected = role.model == m
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { role.model = m }
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
            Button(model.t("role.inheritAll")) {
                role.tools = []
            }
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
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .frame(width: 96, alignment: .center)
            .accessibilityLabel(name)
    }

    private var color: Color {
        switch kind {
        case .orchestrator: return .purple
        case .worker: return .blue
        case .advisor: return .teal
        case .reviewer: return .orange
        case .planner: return .indigo
        case .researcher: return .green
        case .specialist: return .pink
        }
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
