//
//  TokenSaverGuideView.swift
//  StrategyForge
//
//  The curated token-saving guide for the Usage section: ~10 proven habits in
//  three groups ("Before you upload", "While you chat", "Set up once"), each a
//  tinted icon + short title + 1–2 sentence body. Self-contained and bilingual;
//  the coordinator drops it into UsageView.
//

import SwiftUI

struct TokenSaverGuideView: View {
    @Environment(AppModel.self) private var model
    /// Tighter padding + no subtitle for narrow placements.
    var compact: Bool = false

    /// One habit row. `id` is the localization-key suffix
    /// ("saver.guide.habit.<id>.title" / ".body").
    private struct Habit: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        var titleKey: String { "saver.guide.habit.\(id).title" }
        var bodyKey: String { "saver.guide.habit.\(id).body" }
    }

    /// The three groups, in reading order. Tints follow the group so the list
    /// scans as three calm bands rather than a rainbow.
    private static let groups: [(labelKey: String, habits: [Habit])] = [
        ("saver.guide.group.upload", [
            Habit(id: "convert", icon: "doc.plaintext", tint: Theme.success),
            Habit(id: "crop", icon: "crop", tint: Theme.success),
        ]),
        ("saver.guide.group.chat", [
            Habit(id: "planCheap", icon: "map", tint: Theme.teal),
            Habit(id: "batch", icon: "square.stack.3d.up", tint: Theme.teal),
            Habit(id: "point", icon: "scope", tint: Theme.teal),
            Habit(id: "newChat", icon: "plus.bubble", tint: Theme.teal),
            Habit(id: "summarize", icon: "arrow.triangle.2.circlepath", tint: Theme.teal),
        ]),
        ("saver.guide.group.setup", [
            Habit(id: "rightModel", icon: "speedometer", tint: Theme.accent),
            Habit(id: "claudemd", icon: "doc.badge.gearshape", tint: Theme.accent),
            Habit(id: "stateFile", icon: "list.clipboard", tint: Theme.accent),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SectionHeader("leaf.fill", model.t("saver.guide.title"),
                          subtitle: compact ? nil : model.t("saver.guide.subtitle"))

            ForEach(Self.groups, id: \.labelKey) { group in
                VStack(alignment: .leading, spacing: Space.s) {
                    FieldLabel(text: model.t(group.labelKey))
                    ForEach(group.habits) { habit in
                        habitRow(habit)
                    }
                }
            }
        }
        .card(padding: compact ? Space.l : 20)
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: habit.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(habit.tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(habit.tint.opacity(0.14))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t(habit.titleKey))
                    .font(.sfCallout.weight(.semibold))
                Text(model.t(habit.bodyKey))
                    .font(.sfCaption2)
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
