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
            .padding(Space.m)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    reportCard
                    MarkdownView(text: markdown)
                }
                .padding(Space.l)
            }

            Divider()
            HStack(spacing: Space.s) {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: { Label(model.t("report.copy"), systemImage: "doc.on.doc") }
                Button {
                    exportMarkdown()
                } label: { Label(model.t("report.exportMd"), systemImage: "arrow.down.doc") }
                Button {
                    exportImage()
                } label: { Label(model.t("report.saveImage"), systemImage: "photo") }
                .buttonStyle(.moon)
            }
            .padding(Space.m)
        }
        .frame(width: 640, height: 640)
        .background(.regularMaterial)
    }

    /// The punchy summary card — this is what renders to a shareable PNG.
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(MissionReport.headline(agentCount: actedCount, costUSD: costUSD, tokens: tokens))
                .font(.sfDisplay).fixedSize(horizontal: false, vertical: true)
            Text("\(strategyName) · \(title.isEmpty ? model.t("report.aTask") : title)")
                .font(.sfCallout).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: Space.l) {
                stat("person.2.fill", "\(agents.count)", model.t("report.agents"))
                stat("circle.hexagongrid", formatTokens(tokens), model.t("report.tokens"))
                if costUSD > 0 { stat("dollarsign.circle", String(format: "%.2f", costUSD), model.t("report.cost")) }
                if !elapsed.isEmpty { stat("clock", elapsed, model.t("report.time")) }
            }
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill").foregroundStyle(Theme.accent)
                Text("StrategyForge").font(.sfCaption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.cardBg)
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(value, systemImage: icon).font(.sfCardTitle)
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
        try? markdown.data(using: .utf8)?.write(to: url, options: .atomic)
        Analytics.log(.missionReportExported(kind: "markdown"))
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
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mission-report.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url, options: .atomic)
        Analytics.log(.missionReportExported(kind: "image"))
    }
}
