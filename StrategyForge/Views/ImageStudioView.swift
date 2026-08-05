//
//  ImageStudioView.swift
//  StrategyForge
//
//  Text-to-image generation — the one thing the coding CLIs can't do. Calls the providers'
//  IMAGE APIs (OpenAI gpt-image-1 / Google Imagen) with the API keys Coral already stores, shows
//  the result, and lets you save or copy it. Claude has no image-generation API, so it isn't an
//  option here (it can read images, not make them).
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageStudioView: View {
    @Environment(AppModel.self) private var model

    @State private var prompt = ""
    @State private var provider: AIProvider = .openai
    @State private var aspect: ImageAspect = .square
    @State private var isGenerating = false
    @State private var image: NSImage?
    @State private var lastData: Data?
    @State private var errorText: String?

    /// Image providers that actually have a usable key right now.
    private var readyProviders: [AIProvider] {
        ImageGenerator.supportedProviders.filter { keyFor($0) != nil }
    }
    private func keyFor(_ p: AIProvider) -> String? {
        switch p {
        case .openai: return model.openAIAPIKey
        case .gemini: return model.geminiAPIKey
        default:      return nil
        }
    }
    private var canGenerate: Bool {
        !isGenerating && !prompt.trimmingCharacters(in: .whitespaces).isEmpty && keyFor(provider) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if readyProviders.isEmpty { noKeyCard }
                    promptCard
                    if let errorText { errorCard(errorText) }
                    resultArea
                }
                .padding(Space.xl)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBg)
        .onAppear { if let first = readyProviders.first, keyFor(provider) == nil { provider = first } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 15)).foregroundStyle(Theme.coral)
            Text(model.t("images.title")).font(.sfCardTitle)
            Spacer()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    // MARK: Prompt

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FieldLabel(text: model.t("images.prompt"))
            TextField(model.t("images.prompt.placeholder"), text: $prompt, axis: .vertical)
                .textFieldStyle(.plain).font(.sfBodyM)
                .lineLimit(2...6)
                .padding(Space.m)
                .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
                .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner).strokeBorder(Theme.hairline, lineWidth: 1))

            HStack(spacing: Space.l) {
                // Provider — only those with a key.
                if readyProviders.count > 1 {
                    Picker(model.t("images.provider"), selection: $provider) {
                        ForEach(readyProviders, id: \.self) { p in Text(p.displayName).tag(p) }
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                Picker(model.t("images.aspect"), selection: $aspect) {
                    Text(model.t("images.aspect.square")).tag(ImageAspect.square)
                    Text(model.t("images.aspect.landscape")).tag(ImageAspect.landscape)
                    Text(model.t("images.aspect.portrait")).tag(ImageAspect.portrait)
                }
                .pickerStyle(.segmented).fixedSize()
                Spacer()
                if isGenerating {
                    WorkingLine(label: model.t("images.generating")).fixedSize()
                } else {
                    Button(model.t("images.generate")) { generate() }
                        .buttonStyle(.moon).disabled(!canGenerate)
                }
            }
        }
        .card()
    }

    // MARK: Result

    @ViewBuilder
    private var resultArea: some View {
        if let image {
            VStack(alignment: .leading, spacing: Space.m) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                HStack(spacing: Space.s) {
                    Button { save() } label: { Label(model.t("images.save"), systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered)
                    Button { copy() } label: { Label(model.t("images.copy"), systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button { generate() } label: { Label(model.t("images.regenerate"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).disabled(!canGenerate)
                }
            }
        } else if !isGenerating {
            VStack(spacing: Space.s) {
                Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text(model.t("images.empty")).font(.sfCallout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.xl * 2)
        }
    }

    private var noKeyCard: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "key").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.t("images.needKey.title")).font(.sfBodyM.weight(.semibold))
                Text(model.t("images.needKey.detail")).font(.sfCaption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(model.t("banner.fix")) { model.navSection = .services }
                .buttonStyle(.moon).controlSize(.small)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.corner).fill(Theme.accentSoft))
    }

    private func errorCard(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.sfCaption2).foregroundStyle(Theme.warningText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.warnStripFill))
    }

    // MARK: Actions

    private func generate() {
        guard let key = keyFor(provider) else { return }
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        errorText = nil
        isGenerating = true
        let prov = provider, asp = aspect
        Task {
            defer { isGenerating = false }
            do {
                let data = try await ImageGenerator.generate(prompt: p, provider: prov, aspect: asp, apiKey: key)
                if let img = NSImage(data: data) {
                    lastData = data
                    image = img
                } else {
                    errorText = model.t("images.error.decode")
                }
            } catch {
                errorText = (error as? ImageGenError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func save() {
        guard let data = lastData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "coral-image.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
