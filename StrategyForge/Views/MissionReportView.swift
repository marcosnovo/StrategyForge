//
//  MissionReportView.swift
//  StrategyForge
//
//  Shows the shareable mission report for a finished run: a punchy summary card
//  (great as a PNG to share) + the full Markdown, with copy / export .md / save PNG.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MissionReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let title: String
    let strategyName: String
    let agents: [MissionReport.AgentLine]
    let tokens: Int
    let costUSD: Double
    let elapsed: String
    let outcome: String
    /// What this run says about the team — actionable tuning hints. Empty hides the
    /// section, so the report is unchanged for callers that don't compute them.
    var retune: [RunAnalysis.RetuneSuggestion] = []

    private var actedCount: Int {
        let acted = agents.filter { $0.steps > 0 }.count
        return acted > 0 ? acted : agents.count
    }
    private var markdown: String {
        MissionReport.markdown(title: title, strategyName: strategyName, agents: agents,
                               tokens: tokens, costUSD: costUSD, elapsed: elapsed, outcome: outcome)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.t("report.title")).font(.sfCardTitle)
                Spacer()
                Button(model.t("common.done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 1)
            }
            .zIndex(1)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    reportCard
                    if !retune.isEmpty { retuneSection }
                    MarkdownView(text: markdown)
                }
                .padding(Space.l)
            }

            HStack(spacing: Space.s) {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    model.flashSuccess(model.t("report.copied"))
                } label: { Label(model.t("report.copy"), systemImage: "doc.on.doc") }
                Button {
                    exportMarkdown()
                } label: { Label(model.t("report.exportMd"), systemImage: "arrow.down.doc") }
                Button {
                    exportImage()
                } label: { Label(model.t("report.saveImage"), systemImage: "photo") }
                .buttonStyle(.moon)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background {
                Rectangle().fill(.bar)
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: -1)
            }
        }
        .frame(width: 640, height: 640)
        // Neutral, opaque sheet base so the report card + Markdown read cleanly
        // (the .bar top/bottom action bars stay frosted).
        .background(Theme.appBg)
        // Sheets cover the window's banner host — give this one its own.
        .bannerOverlay()
    }

    /// The punchy summary card — this is what renders to a shareable PNG.
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(MissionReport.headline(agentCount: actedCount, costUSD: costUSD, tokens: tokens))
                .font(.sfDisplay).fixedSize(horizontal: false, vertical: true)
            Text("\(strategyName) · \(title.isEmpty ? model.t("report.aTask") : title)")
                .font(.sfCallout).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: Space.l) {
                stat("person.2.fill", "\(agents.count)", model.t("report.agents"), Theme.accent)
                stat("circle.hexagongrid", formatTokens(tokens), model.t("report.tokens"), Theme.teal)
                if costUSD > 0 { stat("dollarsign.circle", String(format: "$%.2f", costUSD), model.t("report.cost"), Theme.success) }
                if !elapsed.isEmpty { stat("clock", elapsed, model.t("report.time"), Theme.accent) }
            }
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(Theme.accent)
                Text("Coral").font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    /// Actionable tuning hints derived from this run (idle agent, cost hog, …).
    private var retuneSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(model.t("retune.title")).font(.sfCardTitle)
            Text(model.t("retune.subtitle")).font(.sfCaption2).foregroundStyle(.secondary)
            ForEach(retune) { s in
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: icon(for: s.severity))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: s.severity))
                        .frame(width: 18)
                    Text(message(for: s))
                        .font(.sfCallout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    private func message(for s: RunAnalysis.RetuneSuggestion) -> String {
        switch s.kind {
        case .idleAgent:    return model.t(s.messageKey, s.subject)
        case .costHog:      return model.t(s.messageKey, s.subject, s.value)
        case .expensiveRun: return model.t(s.messageKey, s.value)
        case .noDelegation: return model.t(s.messageKey)
        }
    }

    private func icon(for severity: RunAnalysis.Severity) -> String {
        switch severity {
        case .warning:    return "exclamationmark.triangle.fill"
        case .suggestion: return "lightbulb.fill"
        case .info:       return "info.circle"
        }
    }

    private func tint(for severity: RunAnalysis.Severity) -> Color {
        switch severity {
        case .warning:    return Theme.warning
        case .suggestion: return Theme.accent
        case .info:       return .secondary
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String, _ tint: Color = Theme.accent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(value).foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .font(.sfCardTitle)
            Text(label).font(.sfCaption2).foregroundStyle(.secondary)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - Export

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mission-report.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
            model.flashSuccess(model.t("chat.fileSaved", "mission-report.md"))
            Analytics.log(.missionReportExported(kind: "markdown"))
        } catch {
            model.flashFailure(model.t("banner.writeFailed", error.localizedDescription))
        }
    }

    @MainActor private func exportImage() {
        let card = reportCard
            .frame(width: 560)
            .padding(Space.l)
            .background(Theme.appBg)
            .environment(model)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            model.flashFailure(model.t("report.imageFailed"))
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mission-report.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            model.flashSuccess(model.t("chat.fileSaved", "mission-report.png"))
            Analytics.log(.missionReportExported(kind: "image"))
        } catch {
            model.flashFailure(model.t("banner.writeFailed", error.localizedDescription))
        }
    }
}
