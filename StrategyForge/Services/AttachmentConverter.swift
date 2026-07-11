//
//  AttachmentConverter.swift
//  StrategyForge
//
//  Makes attached files reviewable by Claude Code, whose Read tool handles text,
//  code, images and PDFs — but not Office binaries. Rich documents (.docx, .rtf,
//  .pptx, …) are converted to plain text in a temp folder; everything else is
//  passed through untouched. Requires no sandbox (runs `textutil` / `unzip`).
//

import Foundation
import PDFKit

enum AttachmentConverter {

    /// Token Saver opt-in: extract a PDF's plain text (a page costs 1.5–3k tokens
    /// as PDF; its text is ~10–20× cheaper). Not part of the automatic `convert`
    /// path — PDFs pass through by default so figures/layout stay reviewable —
    /// this runs only when the user taps the "convert to text" saver tip.
    /// Returns nil for non-PDFs, image-only PDFs, or extraction failures.
    static func extractPDFText(_ url: URL) async -> URL? {
        guard url.pathExtension.lowercased() == "pdf",
              let doc = PDFDocument(url: url),
              let text = doc.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return write(text, basename: url.deletingPathExtension().lastPathComponent)
    }

    /// Extensions the model reads fine as-is (no conversion).
    private static let passthrough: Set<String> = [
        "txt", "md", "markdown", "pdf", "csv", "json", "yaml", "yml", "xml",
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff",
        "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "c", "h",
        "cpp", "m", "sh", "html", "css", "sql", "log",
    ]

    /// Return a URL that Claude can read: the original for text/code/image/PDF,
    /// or a converted `.txt` in a temp folder for Office documents. Never throws —
    /// on any failure it returns the original so the attach still works.
    static func convert(_ url: URL) async -> URL {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty || passthrough.contains(ext) { return url }

        switch ext {
        case "doc", "docx", "rtf", "odt", "rtfd", "webarchive", "htm", "wordml":
            return convertWithTextutil(url) ?? url
        case "pptx":
            return convertPptx(url) ?? url
        default:
            // Unknown binary (e.g. .key, .xlsx, .pages) — pass through; Claude will
            // report if it can't read it. Conversion for these can be added later.
            return url
        }
    }

    // MARK: - Converters

    private static func convertWithTextutil(_ url: URL) -> URL? {
        guard let text = run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path]),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return write(text, basename: url.deletingPathExtension().lastPathComponent)
    }

    /// Extract slide text from a .pptx (a zip of XML) by stripping tags.
    private static func convertPptx(_ url: URL) -> URL? {
        guard let xml = run("/usr/bin/unzip", ["-p", url.path, "ppt/slides/slide*.xml"]),
              !xml.isEmpty else { return nil }
        // PowerPoint text lives in <a:t>…</a:t>. Pull those, then strip any tags.
        var text = ""
        var remainder = Substring(xml)
        while let open = remainder.range(of: "<a:t>"),
              let close = remainder.range(of: "</a:t>", range: open.upperBound..<remainder.endIndex) {
            text += remainder[open.upperBound..<close.lowerBound] + "\n"
            remainder = remainder[close.upperBound...]
        }
        let cleaned = decodeEntities(text.isEmpty ? stripTags(xml) : text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return write(cleaned, basename: url.deletingPathExtension().lastPathComponent)
    }

    // MARK: - Helpers

    private static func write(_ text: String, basename: String) -> URL? {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Coral-attachments/\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("\(basename).txt")
        do { try text.write(to: out, atomically: true, encoding: .utf8); return out }
        catch { return nil }
    }

    private static func run(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func stripTags(_ s: String) -> String {
        var out = ""; var inside = false
        for ch in s { if ch == "<" { inside = true } else if ch == ">" { inside = false } else if !inside { out.append(ch) } }
        return out
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
