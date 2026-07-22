//
//  TeamCatalogView.swift
//  StrategyForge
//
//  The team catalog (v1): discover a starter or community agent team and import it
//  into your saved-team library in one click. Curated built-ins resolve locally;
//  a pasted GitHub ref (owner/repo[@ref]#path/to/team.sfstrategy) is fetched over
//  HTTPS and decoded with StrategyPackage. No backend, no API keys.
//

import SwiftUI
import AppKit

struct TeamCatalogView: View {
    @Environment(AppModel.self) private var model
    private var store: TeamCatalogStore { .shared }

    @State private var pasteRef = ""
    @State private var fetching = false
    @State private var errorText: String?
    /// A resolved team awaiting the preview/confirm sheet.
    @State private var preview: PreviewTeam?

    /// A resolved-but-not-yet-imported team (identifiable for the sheet).
    private struct PreviewTeam: Identifiable {
        let id = UUID()
        let name: String
        let strategy: Strategy
        let remote: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                pasteRow
                if let e = errorText {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.sfCaption2).foregroundStyle(Theme.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVStack(spacing: Space.m) {
                    ForEach(store.curated) { curatedCard($0) }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .sheet(item: $preview) { previewSheet($0) }
    }

    // MARK: Header + paste

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.t("catalog.title")).font(.sfDisplay)
            Text(model.t("catalog.subtitle")).font(.sfCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pasteRow: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "link").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(model.t("catalog.paste"), text: $pasteRef)
                .textFieldStyle(.plain).font(.sfCode)
                .onSubmit { importPasted() }
            if fetching { WorkingLogo(size: 14) }
        }
        .padding(.horizontal, Space.m).padding(.vertical, 10)
        .glassPanel(cornerRadius: Theme.buttonCorner)
    }

    // MARK: Curated card

    private func curatedCard(_ team: CuratedTeam) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(team.name).font(.sfCardTitle)
                categoryChip(team.category)
                if team.verified {
                    Label(model.t("catalog.verified"), systemImage: "checkmark.seal.fill")
                        .font(.sfCaption2).foregroundStyle(Theme.success).labelStyle(.iconOnly)
                }
                Spacer()
                if team.isRemote {
                    Image(systemName: "cloud").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Text(team.description).font(.sfCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Button { open(team) } label: {
                    Label(model.t("catalog.import"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.moon)
                if let repo = team.repoURL {
                    Link(destination: repo) {
                        Label(model.t("catalog.source"), systemImage: "arrow.up.right.square")
                    }
                    .font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        // Rounded floating card (soft depth) instead of a flat hairline box.
        .card(padding: Space.m)
        .hoverLift()
    }

    private func categoryChip(_ text: String) -> some View {
        Text(text.uppercased()).font(.sfFieldLabel).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Theme.accentSoft))
    }

    // MARK: Preview sheet (confirm before it lands in the library)

    private func previewSheet(_ p: PreviewTeam) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.sfCardTitle)
                    Text(model.t("catalog.preview.subtitle")).font(.sfCaption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.t("common.cancel")) { preview = nil }
            }
            .padding(Space.m)
            Divider()
            StrategyDiagramView(strategy: p.strategy, compact: true, ambient: false)
                .frame(height: 220).padding(Space.l)
            Divider()
            HStack {
                Spacer()
                Button { commit(p, edit: true) } label: { Text(model.t("catalog.importEdit")) }
                Button { commit(p, edit: false) } label: { Text(model.t("catalog.import")) }
                    .buttonStyle(.moon).keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial)
        .bannerOverlay()
    }

    // MARK: Actions

    /// Resolve a curated team (locally or over the network) into a preview sheet.
    private func open(_ team: CuratedTeam) {
        errorText = nil
        Task {
            fetching = team.isRemote
            defer { fetching = false }
            do {
                let strategy = try await store.resolve(team)
                preview = PreviewTeam(name: team.name, strategy: strategy, remote: team.isRemote)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func importPasted() {
        let ref = pasteRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return }
        errorText = nil
        Task {
            fetching = true
            defer { fetching = false }
            do {
                let strategy = try await store.resolve(githubRef: ref)
                preview = PreviewTeam(name: model.strategyDisplayName(strategy), strategy: strategy, remote: true)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Land the previewed team in the saved-team library (or open it as a draft to
    /// edit first), then jump to the Teams section.
    private func commit(_ p: PreviewTeam, edit: Bool) {
        let fixed = p.strategy.autoFixed()
        if edit {
            model.beginDraftTeam(from: fixed, named: p.name)
        } else {
            model.createTeam(from: fixed, named: p.name)
        }
        preview = nil
        pasteRef = ""
        model.navSection = .team
    }
}
