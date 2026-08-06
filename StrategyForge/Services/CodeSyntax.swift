//
//  CodeSyntax.swift
//  StrategyForge
//
//  A lightweight, dependency-free syntax highlighter for the Código diff viewer — the biggest
//  perceived-quality jump for the diff (SOTA tools all show syntax-coloured diffs, not flat green/
//  red text). Regex-tokenised per line into an AttributedString: comments, strings, numbers,
//  keywords, and Capitalised types, in a restrained coral-adjacent palette. Language-agnostic with
//  a shared keyword set (Swift/JS/TS/Python/JSON/…), keyed loosely by file extension. Pure, so it's
//  unit-testable and cheap enough to run per visible row.
//

import SwiftUI
import AppKit

enum CodeSyntax {
    // A restrained palette — code content may carry a few hues (unlike chrome, which stays
    // one-accent). Tuned to read on both the light paper and the dark ground.
    private static let base = NSColor(Theme.ink)
    private static let comment = NSColor(Color(hue: 0.33, saturation: 0.10, brightness: 0.55))
    private static let string = NSColor(Color(hue: 0.11, saturation: 0.85, brightness: 0.72))
    private static let number = NSColor(Color(hue: 0.55, saturation: 0.70, brightness: 0.70))
    private static let keyword = NSColor(Theme.coralDeep)
    private static let type = NSColor(Color(hue: 0.60, saturation: 0.55, brightness: 0.70))

    private static let keywordList = [
        "func", "let", "var", "if", "else", "for", "while", "repeat", "return", "struct", "class",
        "enum", "import", "guard", "switch", "case", "default", "break", "continue", "private",
        "public", "internal", "fileprivate", "open", "static", "self", "Self", "init", "deinit",
        "extension", "protocol", "typealias", "associatedtype", "async", "await", "throws", "throw",
        "rethrows", "try", "in", "do", "catch", "defer", "where", "as", "is", "some", "any", "weak",
        "unowned", "lazy", "final", "override", "mutating", "nonisolated", "actor", "true", "false",
        "nil", "null", "none", "const", "function", "def", "from", "export", "new", "void", "int",
        "string", "bool", "float", "double", "print", "then", "with", "yield", "lambda", "pass",
        "elif", "and", "or", "not", "type", "interface", "namespace", "using", "package",
    ]
    private static let keywordPattern = "\\b(?:" + keywordList.joined(separator: "|") + ")\\b"

    private struct Rule { let regex: NSRegularExpression; let color: NSColor }
    // Built once. Order matters: keywords/numbers/types first, then strings + comments LAST so
    // they override any keyword-looking token that lives inside a literal or comment.
    private static let rules: [Rule] = {
        func rule(_ p: String, _ c: NSColor, _ opts: NSRegularExpression.Options = []) -> Rule? {
            (try? NSRegularExpression(pattern: p, options: opts)).map { Rule(regex: $0, color: c) }
        }
        return [
            rule("\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", number),
            rule("\\b0[xX][0-9a-fA-F_]+\\b", number),
            rule(keywordPattern, keyword),
            rule("\\b[A-Z][A-Za-z0-9_]*\\b", type),
            rule("\"(?:[^\"\\\\]|\\\\.)*\"", string),
            rule("'(?:[^'\\\\]|\\\\.)*'", string),
            rule("`(?:[^`\\\\]|\\\\.)*`", string),
            rule("//.*$", comment),
            rule("#.*$", comment),
        ].compactMap { $0 }
    }()

    /// Highlight one line of code. `ext` is accepted for future per-language tuning; today the
    /// shared ruleset covers the common languages well enough for a diff row.
    static func highlight(_ text: String, ext: String = "") -> AttributedString {
        guard !text.isEmpty else { return AttributedString(text) }
        let s = NSMutableAttributedString(string: text, attributes: [.foregroundColor: base])
        let full = NSRange(location: 0, length: (text as NSString).length)
        for r in rules {
            for m in r.regex.matches(in: text, options: [], range: full) {
                s.addAttribute(.foregroundColor, value: r.color, range: m.range)
            }
        }
        return AttributedString(s)
    }

    /// Syntax-highlight a diff line and wash the word-level changed range (if any) a stronger
    /// green/red — shared by the unified and split diff views.
    static func diffLine(_ text: String, ext: String, emphasis: Range<Int>?, isDelete: Bool) -> AttributedString {
        var a = highlight(text, ext: ext)
        if let r = emphasis, !text.isEmpty {
            let chars = a.characters
            let lo = chars.index(chars.startIndex, offsetBy: min(r.lowerBound, chars.count))
            let hi = chars.index(chars.startIndex, offsetBy: min(r.upperBound, chars.count))
            if lo < hi {
                a[lo..<hi].backgroundColor = (isDelete ? Theme.danger : Theme.success).opacity(0.28)
            }
        }
        return a
    }
}

/// Word-level intraline diff: pair each run of deleted lines with the following run of added
/// lines and find the changed middle via a common prefix/suffix trim. Shared by both diff views.
enum DiffEmphasis {
    static func compute(_ lines: [DiffLine]) -> [DiffLine.ID: Range<Int>] {
        var map: [DiffLine.ID: Range<Int>] = [:]
        var i = 0
        while i < lines.count {
            guard lines[i].kind == .del else { i += 1; continue }
            var dels: [Int] = []; var j = i
            while j < lines.count, lines[j].kind == .del { dels.append(j); j += 1 }
            var adds: [Int] = []; var k = j
            while k < lines.count, lines[k].kind == .add { adds.append(k); k += 1 }
            for p in 0..<min(dels.count, adds.count) {
                if let (dr, ar) = wordDiff(lines[dels[p]].text, lines[adds[p]].text) {
                    map[lines[dels[p]].id] = dr; map[lines[adds[p]].id] = ar
                }
            }
            i = k
        }
        return map
    }

    static func wordDiff(_ old: String, _ new: String) -> (Range<Int>, Range<Int>)? {
        let o = Array(old), n = Array(new)
        guard o != n, !o.isEmpty, !n.isEmpty else { return nil }
        var p = 0
        while p < o.count, p < n.count, o[p] == n[p] { p += 1 }
        var s = 0
        while s < (o.count - p), s < (n.count - p), o[o.count - 1 - s] == n[n.count - 1 - s] { s += 1 }
        let oR = p..<(o.count - s), nR = p..<(n.count - s)
        if Double(oR.count) / Double(o.count) > 0.85, Double(nR.count) / Double(n.count) > 0.85 { return nil }
        return (oR, nR)
    }
}
