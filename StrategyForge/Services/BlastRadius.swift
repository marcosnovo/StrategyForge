//
//  BlastRadius.swift
//  StrategyForge
//
//  "Open the gate on blast radius, not on confidence" (Eval Engineering, 2026). What matters
//  for letting a change through isn't how sure the model is — it's how expensive the mistake is
//  to undo. This pure classifier reads a git diff and sorts it into a lane:
//
//    • contained    — reversible + isolated (a revert fixes it): safe to auto-merge on a clean check
//    • wide         — reversible but many callers / shared surface: gate on checks + a clean trajectory
//    • irreversible — migrations, deletions, prod/secrets, money: never auto-merge, a human must look
//
//  The model's own assessment is deliberately NOT an input here — it's the one signal the model
//  can influence. Pure + tested; the UI turns the lane into a merge affordance.
//

import Foundation

enum BlastRadius: String, Sendable, Equatable {
    case contained, wide, irreversible

    /// Ordering so we can take the worst lane across many signals.
    var severity: Int { self == .irreversible ? 2 : (self == .wide ? 1 : 0) }
    var labelKey: String { "blast.\(rawValue)" }
}

struct BlastAssessment: Sendable, Equatable {
    var radius: BlastRadius
    var reasons: [String]     // human signals ("touches a database migration", "deletes files")
    var filesChanged: Int
    /// May this lane ever auto-merge (without a human reading it)? Irreversible never can.
    var canAutoMerge: Bool { radius == .contained }
}

enum BlastRadiusClassifier {
    /// How many changed files count as a "wide" surface even without a specific risky signal.
    static let wideFileThreshold = 8

    /// Classify a unified git diff into a blast-radius lane. Conservative: any irreversible
    /// signal wins; when unsure it errs wider, never narrower.
    static func classify(diff: String) -> BlastAssessment {
        let lower = diff.lowercased()
        let files = changedFiles(diff)
        var reasons: [String] = []
        var radius: BlastRadius = .contained

        func bump(_ r: BlastRadius, _ why: String) {
            if r.severity > radius.severity { radius = r }
            if !reasons.contains(why) { reasons.append(why) }
        }

        // --- Irreversible signals ---
        if files.contains(where: { isMigrationPath($0) }) { bump(.irreversible, "database migration") }
        if lower.contains("drop table") || lower.contains("drop column")
            || lower.contains("delete from") || lower.contains("truncate ") { bump(.irreversible, "destructive SQL") }
        if files.contains(where: { isSecretPath($0) }) || lower.contains("secret_key") || lower.contains("private_key") {
            bump(.irreversible, "secrets / credentials")
        }
        if files.contains(where: { isMoneyPath($0) }) || lower.contains("stripe") || lower.contains("charge(")
            || lower.contains("refund") || lower.contains("payout") { bump(.irreversible, "payments / money") }
        if files.contains(where: { isProdConfigPath($0) }) { bump(.irreversible, "production config") }
        if diff.range(of: #"(?m)^rm -rf|--force\b|git push --force"#, options: .regularExpression) != nil {
            bump(.irreversible, "force / destructive command")
        }
        if deletesWholeFiles(diff) { bump(.irreversible, "deletes files") }

        // --- Wide signals ---
        if files.count >= wideFileThreshold { bump(.wide, "touches \(files.count) files") }
        if files.contains(where: { isSharedSurfacePath($0) }) { bump(.wide, "shared / core surface") }
        if files.contains(where: { isLockfilePath($0) }) { bump(.wide, "dependency lockfile") }
        if lower.contains("public ") && (lower.contains("func ") || lower.contains("class ") || lower.contains("struct ")) {
            // A public API change ripples to callers.
            bump(.wide, "public API change")
        }

        return BlastAssessment(radius: radius, reasons: reasons, filesChanged: files.count)
    }

    // MARK: - Diff parsing

    /// Changed file paths from a unified git diff (`diff --git a/… b/…` and `+++ b/…`).
    static func changedFiles(_ diff: String) -> [String] {
        var out: [String] = []
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(line)
            if l.hasPrefix("+++ ") {
                var p = String(l.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if p == "/dev/null" { continue }
                if p.hasPrefix("a/") || p.hasPrefix("b/") { p = String(p.dropFirst(2)) }
                if !p.isEmpty, !out.contains(p) { out.append(p) }
            } else if l.hasPrefix("diff --git ") {
                // Fallback: "diff --git a/x b/x" — take the b/ path.
                if let r = l.range(of: " b/") {
                    let p = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty, !out.contains(p) { out.append(p) }
                }
            }
        }
        return out
    }

    /// True if the diff deletes at least one file whole (`+++ /dev/null` with a `deleted file` header).
    static func deletesWholeFiles(_ diff: String) -> Bool {
        diff.contains("deleted file mode") || diff.range(of: #"(?m)^\+\+\+ /dev/null"#, options: .regularExpression) != nil
    }

    // MARK: - Path heuristics

    private static func isMigrationPath(_ p: String) -> Bool {
        let l = p.lowercased()
        return l.contains("/migrations/") || l.hasPrefix("migrations/") || l.hasSuffix(".sql")
            || l.contains("schema.rb") || l.contains("schema.prisma")
    }
    private static func isSecretPath(_ p: String) -> Bool {
        let l = (p as NSString).lastPathComponent.lowercased()
        return l == ".env" || l.hasPrefix(".env") || l.contains("secret") || l.contains("credentials")
            || l.hasSuffix(".pem") || l.hasSuffix(".p12") || l.hasSuffix(".key")
    }
    private static func isMoneyPath(_ p: String) -> Bool {
        let l = p.lowercased()
        return l.contains("payment") || l.contains("billing") || l.contains("checkout") || l.contains("invoice")
    }
    private static func isProdConfigPath(_ p: String) -> Bool {
        let l = p.lowercased()
        return l.contains("prod") && (l.hasSuffix(".yml") || l.hasSuffix(".yaml") || l.hasSuffix(".toml")
            || l.hasSuffix(".json") || l.contains("config") || l.contains("deploy"))
    }
    private static func isSharedSurfacePath(_ p: String) -> Bool {
        let l = p.lowercased()
        return l.contains("/shared/") || l.contains("/common/") || l.contains("/core/") || l.contains("/utils/")
            || l.contains("/lib/") || (l as NSString).lastPathComponent.hasPrefix("constants")
    }
    private static func isLockfilePath(_ p: String) -> Bool {
        let l = (p as NSString).lastPathComponent.lowercased()
        return l == "package-lock.json" || l == "yarn.lock" || l == "pnpm-lock.yaml"
            || l == "package.resolved" || l == "cargo.lock" || l == "podfile.lock" || l == "gemfile.lock"
    }
}
