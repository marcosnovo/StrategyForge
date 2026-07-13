//
//  TeamBrowseView.swift
//  StrategyForge
//
//  The Team section's "no team open" surface: one place to start a team, with two
//  tabs — Templates (built-in strategy blueprints) and Discover (the catalog of
//  curated / community teams to import). This folds the old standalone "Team
//  library" screen into the Team section so it no longer sits beside the chat list.
//

import SwiftUI

struct TeamBrowseView: View {
    @Environment(AppModel.self) private var model

    enum Tab: String, CaseIterable { case templates, discover }
    /// Persisted so the section reopens on the tab you left it on.
    @AppStorage("team.browse.tab") private var tabRaw = Tab.templates.rawValue
    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabRaw) ?? .templates }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header + tab switch. Titles make it obvious this is where teams are born.
            VStack(alignment: .leading, spacing: Space.s) {
                Text(model.t("team.browse.title")).font(.sfDisplay)
                Text(model.t("team.browse.subtitle")).font(.sfCallout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("", selection: tab) {
                    Text(model.t("team.browse.templates")).tag(Tab.templates)
                    Text(model.t("team.browse.discover")).tag(Tab.discover)
                }
                .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 320)
                .padding(.top, Space.xs)
            }
            .padding(.horizontal, Space.l).padding(.top, Space.l).padding(.bottom, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.appBg)
            Divider()

            switch tab.wrappedValue {
            case .templates:
                StrategyPickerColumn(config: nil, selectedStrategyName: nil,
                                     onSelect: { model.beginDraftTeam(from: $0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .discover:
                TeamCatalogView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
