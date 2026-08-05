//
//  ProviderAuth.swift
//  StrategyForge
//
//  A cheap, no-subprocess, no-Keychain check that a provider's stored login looks USABLE —
//  a credentials file exists and, where the format exposes an expiry, hasn't lapsed. This is
//  stronger than ProviderRegistry's "the CLI is installed": it's why Gemini could show as
//  "Conectado" while its login had actually expired (the run then failed with authRequired).
//  Best-effort by design: an unknown/opaque format returns .ok so we never cry wolf, and we
//  deliberately do NOT read the Keychain here (that would prompt at launch on a debug build).
//

import Foundation

// Pure, stateless disk checks. Members are explicitly `nonisolated` so they run OFF the main
// actor (file I/O) and compose in a task group without main-actor hops.
enum ProviderAuth {

    /// The result of a startup liveness check for one provider.
    enum State: Equatable {
        case ok            // a token exists and isn't known-expired
        case expired       // a token exists but its expiry has passed
        case missing       // installed, but no stored login found
        case unknown       // can't tell cheaply (e.g. Keychain-only) — treat as fine
    }

    /// Check every connected provider's login freshness, concurrently, off the main thread.
    nonisolated static func verify(_ providers: Set<AIProvider>) async -> [AIProvider: State] {
        await withTaskGroup(of: (AIProvider, State).self) { group in
            for p in providers { group.addTask { (p, freshness(p)) } }
            var out: [AIProvider: State] = [:]
            for await (p, s) in group { out[p] = s }
            return out
        }
    }

    /// One provider's login freshness from its on-disk credentials (never the Keychain).
    nonisolated static func freshness(_ provider: AIProvider) -> State {
        switch provider {
        case .claude:
            // Claude usually stores its OAuth in the Keychain (which we must not touch at
            // launch), so only the plain credentials file is a cheap signal. Absent → unknown
            // (likely Keychain-backed and fine), never "missing".
            let home = NSHomeDirectory()
            let path = "\(home)/.claude/.credentials.json"
            return FileManager.default.fileExists(atPath: path)
                ? expiryState(fileAt: path, keyPath: ["claudeAiOauth", "expiresAt"], unit: .millis)
                : .unknown
        case .gemini:
            // `gemini` / `agy` write this on a successful Google login.
            let path = "\(NSHomeDirectory())/.gemini/oauth_creds.json"
            guard FileManager.default.fileExists(atPath: path) else { return .missing }
            return expiryState(fileAt: path, keyPath: ["expiry_date"], unit: .millis)
        case .openai:
            // `codex login` writes a ChatGPT token here; format is opaque enough that mere
            // presence is the honest signal (its own run-time auth check catches expiry).
            let path = "\(NSHomeDirectory())/.codex/auth.json"
            return FileManager.default.fileExists(atPath: path) ? .ok : .missing
        }
    }

    // MARK: - Helpers

    private enum Unit { case millis, seconds }

    /// Read a nested numeric expiry from a JSON credentials file and compare to now. If the
    /// field is absent we can't judge → .ok (token present, unknown lifetime).
    nonisolated private static func expiryState(fileAt path: String, keyPath: [String], unit: Unit) -> State {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unknown }
        var node: Any? = root
        for key in keyPath { node = (node as? [String: Any])?[key] }
        guard let raw = node else { return .ok }   // present but no expiry field
        let value: Double
        if let d = raw as? Double { value = d }
        else if let i = raw as? Int { value = Double(i) }
        else { return .ok }
        let divisor: Double
        switch unit { case .millis: divisor = 1000; case .seconds: divisor = 1 }
        return Date(timeIntervalSince1970: value / divisor) > Date() ? .ok : .expired
    }
}
