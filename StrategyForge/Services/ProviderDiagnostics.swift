//
//  ProviderDiagnostics.swift
//  StrategyForge
//
//  A small self-diagnosis engine so users don't have to read logs or a Terminal to
//  recover a broken provider. It runs the same end-to-end check the test button does
//  (resolve the CLI → one real one-shot) and CLASSIFIES any failure into a known
//  cause with a one-click fix: a stale sign-in (→ re-connect), a missing CLI
//  (→ install & connect), a model unsupported on a ChatGPT account (→ guidance), or
//  something unexpected (→ export the log). The classifier is pure and shared, so the
//  same friendly message appears at the failure site (chat, meta-orchestrator) too.
//

import Foundation

enum ProviderDiagnostics {

    /// The concrete cause of a provider failure.
    enum Issue: String, Sendable, Equatable {
        case notInstalled        // the CLI binary can't be found
        case notSignedIn         // 401 / "failed to authenticate" / "set an auth method"
        case modelUnsupported    // ChatGPT-account login rejects an explicit model
        case migrateAntigravity  // Google retired the free Gemini CLI → Antigravity (agy)
        case invalidKey          // a Gemini API key was set but the REST check rejected it
        case unknown             // anything else — surface raw + offer the log
    }

    /// The recommended one-click remedy for an issue.
    enum Fix: Sendable, Equatable {
        case connect        // open the install → web sign-in flow (fixes notInstalled + notSignedIn)
        case useAPIKey      // Codex model choice needs an API key (or just drop the model)
        case addGeminiKey   // Google retired the free Gemini CLI → paste a GEMINI_API_KEY (the one path that runs)
        case getAntigravity // open antigravity.google (the GUI IDE successor — not a headless CLI Coral can drive)
        case exportLog      // last resort: hand the user the full log
        case none
    }

    /// Where to send a user to install Antigravity (the successor to the free Gemini CLI).
    static let antigravityURL = URL(string: "https://antigravity.google")!
    /// Where to mint a Gemini API key — the working headless path now that the free CLI is gone.
    static let geminiKeyURL = URL(string: "https://aistudio.google.com/apikey")!

    /// The outcome of a check: healthy, or an issue with its raw detail + remedy.
    struct Finding: Sendable, Equatable {
        var issue: Issue
        var raw: String       // the underlying CLI/error text (shown under "Details")
        var fix: Fix
    }

    /// Run a full health check for one provider: resolve the CLI, then do one real
    /// one-shot. Returns nil when healthy, or a classified `Finding` when it fails.
    /// `greeting` is returned on success so the caller can show the live reply.
    static func check(
        provider: AIProvider,
        binary: String,
        modelID: String,
        apiKeys: [AIProvider: String],
        reasoningEffort: String
    ) async -> (finding: Finding?, greeting: String) {
        // Gemini with an API key: verify the KEY directly against the REST API. This is the only
        // working Gemini path, and it's independent of the retired `gemini` CLI — so the diagnosis
        // tests the key and NEVER mentions a CLI (the founder's "sigue hablando de CLI" bug).
        if provider == .gemini, let key = apiKeys[.gemini], !key.isEmpty {
            return await verifyGeminiKey(key)
        }
        // 1. Is the CLI even there? (resolveBinary validates it's executable — and for Gemini
        // it also tries the `agy` fallback.) For Gemini, "not found" now means the free CLI is
        // gone → point at Antigravity, not a futile reinstall of the retired `gemini`.
        guard CLIOneShotRunner.resolveBinary(binary, provider: provider) != nil else {
            if provider == .gemini {
                return (Finding(issue: .migrateAntigravity, raw: "", fix: .addGeminiKey), "")
            }
            return (Finding(issue: .notInstalled, raw: "", fix: .connect), "")
        }
        // Gemini with an API key set: skip the Google-login freshness gate entirely — the key is
        // its own auth path (GEMINI_API_KEY), so a missing/dead CLI login is irrelevant. Go
        // straight to the real round-trip, which exercises the key.
        let hasGeminiKey = provider == .gemini && (apiKeys[.gemini]?.isEmpty == false)
        // 1b. A missing/expired stored login makes the real round-trip HANG (Gemini especially)
        // — the "diagnóstico se queda pensando" bug. Short-circuit to "not signed in" instantly
        // from the on-disk creds instead of waiting out a stall.
        let fresh = ProviderAuth.freshness(provider)
        if !hasGeminiKey, fresh == .missing || fresh == .expired {
            let raw = "Saved \(provider.displayName) login looks \(fresh == .expired ? "expired" : "missing")."
            return (Finding(issue: .notSignedIn, raw: raw, fix: .connect), "")
        }
        // 2. One real round-trip — the honest end-to-end test.
        let runner = CLIOneShotRunner(binaries: [provider: binary],
                                      apiKeys: apiKeys, reasoningEffort: reasoningEffort)
        do {
            let r = try await runner.run(prompt: "Reply with a short one-line greeting.",
                                         provider: provider, model: modelID, cwd: nil)
            return (nil, r.text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (classify(error: error, provider: provider), "")
        }
    }

    /// Validate a Gemini API key by listing models over REST (a light, auth-only round-trip) —
    /// no CLI, no interactive login. 200 ⇒ healthy; anything else ⇒ the key is bad/expired.
    private static func verifyGeminiKey(_ key: String) async -> (finding: Finding?, greeting: String) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            return (Finding(issue: .invalidKey, raw: "", fix: .addGeminiKey), "")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")   // key in a header, never logged in the URL
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return (nil, "") }                    // healthy → view shows the localized OK
            let body = String(data: data, encoding: .utf8) ?? ""
            return (Finding(issue: .invalidKey, raw: "HTTP \(code): \(body.prefix(240))", fix: .addGeminiKey), "")
        } catch {
            return (Finding(issue: .unknown, raw: error.localizedDescription, fix: .exportLog), "")
        }
    }

    /// Map a run error to a concrete issue + remedy. Pure and shared with the failure
    /// sites so the chat / meta-orchestrator show the same actionable diagnosis.
    static func classify(error: Error, provider: AIProvider) -> Finding {
        if case OneShotError.notInstalled = error {
            return Finding(issue: .notInstalled, raw: error.localizedDescription, fix: .connect)
        }
        // A silent stall is almost always a stuck/expired login → treat as "sign in again".
        if case OneShotError.stalled = error {
            return Finding(issue: .notSignedIn, raw: error.localizedDescription, fix: .connect)
        }
        let raw = (error as? OneShotError)?.errorDescription ?? error.localizedDescription
        return classify(message: raw, provider: provider)
    }

    /// Classify a raw CLI/error message (used when we only have text, e.g. a parsed
    /// `result` line). Keyword-based and tolerant of wording changes across versions.
    static func classify(message raw: String, provider: AIProvider) -> Finding {
        let m = raw.lowercased()
        // Google retired the free `gemini` CLI (IneligibleTier / unsupported client) — a stale-
        // login reconnect can't fix it; the user must move to Antigravity. Check FIRST because
        // the message also contains "authenticate" and would otherwise read as "not signed in".
        if provider == .gemini, CLIOneShotRunner.isAntigravityMigration(raw) {
            return Finding(issue: .migrateAntigravity, raw: raw, fix: .addGeminiKey)
        }
        let authy = m.contains("401") || m.contains("invalid authentication")
            || m.contains("failed to authenticate") || m.contains("authenticate")
            || m.contains("please set an auth method") || m.contains("credentials")
            || m.contains("unauthorized") || m.contains("not logged in")
        if authy {
            return Finding(issue: .notSignedIn, raw: raw, fix: .connect)
        }
        if m.contains("not supported when using codex with a chatgpt account")
            || (m.contains("model") && m.contains("not supported")) {
            return Finding(issue: .modelUnsupported, raw: raw, fix: .useAPIKey)
        }
        if m.contains("couldn't find") && m.contains("cli") {
            return Finding(issue: .notInstalled, raw: raw, fix: .connect)
        }
        return Finding(issue: .unknown, raw: raw, fix: .exportLog)
    }
}
