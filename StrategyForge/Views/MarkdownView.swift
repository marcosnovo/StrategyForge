//
//  MarkdownView.swift
//  StrategyForge
//
//  A lightweight block-level Markdown renderer for chat replies. SwiftUI's
//  AttributedString(markdown:) only does inline styling and collapses structure,
//  so this splits the text into blocks — headings, paragraphs, lists, fenced code
//  and tables — and renders each properly (real bullets, monospaced code with a
//  copy button, and grid tables).
//

import SwiftUI
import AppKit

struct MarkdownView: View {
    let text: String

    /// Parsed blocks are memoized by their source text, so re-renders (streaming,
    /// hover, scroll) don't re-parse the whole markdown of every message — only a
    /// changed/streaming message misses the cache. This was the main cause of chat
    /// sluggishness in long transcripts.
    private static let cache = NSCache<NSString, BlockBox>()
    private final class BlockBox { let blocks: [MarkdownBlock]; init(_ b: [MarkdownBlock]) { blocks = b } }

    private var blocks: [MarkdownBlock] {
        let key = text as NSString
        if let hit = Self.cache.object(forKey: key) { return hit.blocks }
        let parsed = MarkdownParser.blocks(from: text)
        Self.cache.countLimit = 400
        Self.cache.setObject(BlockBox(parsed), forKey: key)
        return parsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: [20, 17, 15][min(level - 1, 2)], weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(inline(text))
                .font(.sfBodyM)
                .foregroundStyle(Theme.ink)
                .lineSpacing(Theme.bodyLineSpacing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("•").foregroundStyle(Theme.accent)
                        Text(inline(item)).font(.sfBodyM).foregroundStyle(Theme.ink).lineSpacing(Theme.bodyLineSpacing).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(i + 1).").foregroundStyle(Theme.accent).monospacedDigit()
                        Text(inline(item)).font(.sfBodyM).foregroundStyle(Theme.ink).lineSpacing(Theme.bodyLineSpacing).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .code(let code, let lang):
            codeBlock(code, lang: lang)
        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        }
    }

    private func codeBlock(_ code: String, lang: String) -> some View {
        CodeBlockView(code: code, lang: lang)
    }

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        return Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: 6) {
            GridRow {
                ForEach(0..<columns, id: \.self) { c in
                    Text(inline(c < headers.count ? headers[c] : ""))
                        .font(.sfCaption2.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            Divider().gridCellColumns(columns)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(inline(c < row.count ? row[c] : "")).font(.sfCaption2).foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner).fill(Theme.insetBg))
    }

    /// Inline markdown (bold/italic/code/links) with newlines preserved.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

// MARK: - Parsing

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case code(String, lang: String)
    case table(headers: [String], rows: [[String]])
}

enum MarkdownParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        func cells(_ line: String) -> [String] {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("|") { l.removeFirst() }
            if l.hasSuffix("|") { l.removeLast() }
            return l.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isSeparator(_ line: String) -> Bool {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains("-"), t.contains("|") || t.hasPrefix("-") else { return false }
            return t.allSatisfy { "|-: ".contains($0) }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code. The info string after ``` is the language (e.g. ```swift).
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(code.joined(separator: "\n"), lang: lang))
                continue
            }

            // Table: a header row followed by a |---| separator.
            if trimmed.contains("|"), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                let headers = cells(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[i])); i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Heading.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                let content = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(hashes, content)); i += 1
                continue
            }

            // Bulleted list.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("- ") || t.hasPrefix("* ") else { break }
                    items.append(String(t.dropFirst(2))); i += 1
                }
                blocks.append(.bullet(items)); continue
            }

            // Ordered list.
            if let r = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let rr = t.range(of: #"^\d+\.\s"#, options: .regularExpression) else { break }
                    items.append(String(t[rr.upperBound...])); i += 1
                }
                _ = r
                blocks.append(.ordered(items)); continue
            }

            // Paragraph: gather consecutive plain lines.
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("```") || t.hasPrefix("#")
                    || t.hasPrefix("- ") || t.hasPrefix("* ")
                    || t.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    || (t.contains("|") && i + 1 < lines.count && isSeparator(lines[i + 1])) {
                    break
                }
                para.append(lines[i]); i += 1
            }
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))) }
        }
        return blocks
    }
}

/// A premium fenced-code block: a header bar with the language label + a copy button that
/// confirms, over a hairline-separated code surface (design review, wave B). For an app
/// whose whole point is code, the code block should be one of the nicest elements.
private struct CodeBlockView: View {
    let code: String
    let lang: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Text(lang.isEmpty ? "code" : lang.lowercased())
                    .font(.sfFieldLabel).foregroundStyle(.tertiary).tracking(0.6)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.sfCaption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? AnyShapeStyle(Theme.success) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.sfCode)
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(Space.m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous).fill(Theme.insetBg))
        .overlay(RoundedRectangle(cornerRadius: Theme.innerCorner, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
