//
//  LoopWebhookNotifier.swift
//  StrategyForge
//
//  Remote (off-the-Mac) notification for finished loop runs. `LoopNotifier` posts a
//  LOCAL macOS notification — great while you're at the Mac, useless when you've walked
//  away. This POSTs a small JSON payload to a webhook URL the user pastes in Settings, so
//  a finished/failed loop can reach a phone (ntfy), a Slack/Discord channel, or any
//  generic endpoint — with NO backend of our own, no account, and no stored credentials
//  (the URL itself is the only secret, and it rides in the user's own settings).
//
//  The JSON payload carries the same field under several well-known keys (`text` for
//  Slack, `content` for Discord, `message`/`title` for generic consumers) so one body
//  works across services without asking the user which they use. ntfy.sh topic URLs are
//  special-cased: they publish the RAW request body as the message, so they get a
//  plain-text body + ntfy's Title/Tags headers instead of the JSON (see `encoding`/
//  `request`). It's best-effort: a bad URL or a network failure is swallowed (the local
//  notification already fired), never surfaced as a loop error.
//

import Foundation

/// The JSON body POSTed to the user's webhook when a loop run finishes. Multi-keyed for
/// broad compatibility; pure/Codable so it's unit-tested without any network.
struct LoopWebhookPayload: Codable, Equatable {
    /// Stable event name so a generic consumer can route on it.
    var event: String = "loop.finished"
    /// The loop's name (or a localized "Untitled loop").
    var title: String
    /// The human one-liner ("<loop> passed" / "failed" / "done, unverified").
    var message: String
    /// Slack incoming-webhook field (Slack renders `text`).
    var text: String
    /// Discord webhook field (Discord renders `content`).
    var content: String
    /// "passed" | "failed" | "unverified" — machine-readable outcome.
    var status: String
    var iterations: Int
    var tokens: Int
    var costUSD: Double
    /// The verifier's one-line reason or the run's error, if any.
    var reason: String?

    /// Map a run's tri-state pass flag to a stable status string.
    static func status(for pass: Bool?) -> String {
        switch pass {
        case .some(true): return "passed"
        case .some(false): return "failed"
        case .none: return "unverified"
        }
    }
}

enum LoopWebhookNotifier {

    /// Build the payload for a finished run. `title` is the loop name, `body` the human
    /// message already localized by the caller (kept identical to the local notification
    /// so both channels read the same). Pure — no I/O.
    static func payload(title: String, body: String, summary: LoopRunSummary) -> LoopWebhookPayload {
        let line = "\(title): \(body)"
        return LoopWebhookPayload(
            title: title,
            message: body,
            text: line,
            content: line,
            status: LoopWebhookPayload.status(for: summary.pass),
            iterations: summary.iterations,
            tokens: summary.tokens,
            costUSD: summary.costRounded,
            reason: summary.reason?.isEmpty == true ? nil : summary.reason)
    }

    /// Validate a user-entered webhook URL: non-empty and an absolute http(s) URL. Returns
    /// the URL to POST to, or nil if it isn't usable (so callers no-op silently).
    static func endpoint(from urlString: String?) -> URL? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    /// How to encode the POST body for a given endpoint. ntfy topic URLs
    /// (`https://ntfy.sh/<topic>`) publish the RAW request body as the notification
    /// message — sending them our JSON would show the literal JSON blob on the phone. So
    /// ntfy.sh gets a plain-text body + ntfy's own headers; everyone else (Slack, Discord,
    /// generic) gets the multi-keyed JSON.
    enum BodyEncoding: Equatable { case json, ntfy }

    /// ntfy.sh is detected by host (the public service — the exact URL our Settings copy
    /// suggests). Self-hosted ntfy on an arbitrary host isn't auto-detected; for those the
    /// JSON path still delivers (ntfy accepts JSON publishes to its ROOT url, and a topic
    /// URL there would show the JSON as text — an acceptable, documented fallback).
    static func encoding(for url: URL) -> BodyEncoding {
        let host = url.host?.lowercased() ?? ""
        return (host == "ntfy.sh" || host.hasSuffix(".ntfy.sh")) ? .ntfy : .json
    }

    /// ntfy tag (an emoji shortname) for a run outcome — a nice status glyph on the phone.
    static func ntfyTag(for pass: Bool?) -> String {
        switch pass {
        case .some(true): return "white_check_mark"
        case .some(false): return "x"
        case .none: return "grey_question"
        }
    }

    /// The concrete request pieces for an endpoint — pure, so encoding choice + headers are
    /// unit-tested without a network. nil if the JSON body can't be encoded.
    struct WebhookRequest: Equatable {
        var contentType: String
        var body: Data
        var headers: [String: String]   // extra headers beyond Content-Type (e.g. ntfy's)
    }

    static func request(for url: URL, title: String, body: String,
                        summary: LoopRunSummary) -> WebhookRequest? {
        switch encoding(for: url) {
        case .ntfy:
            // Raw message text + ntfy's Title/Tags headers → a clean phone notification.
            return WebhookRequest(
                contentType: "text/plain; charset=utf-8",
                body: Data(body.utf8),
                headers: ["Title": title, "Tags": ntfyTag(for: summary.pass)])
        case .json:
            guard let data = try? JSONEncoder().encode(payload(title: title, body: body, summary: summary)) else {
                return nil
            }
            // Title header is harmless for Slack/Discord/generic and helps ntfy-on-root.
            return WebhookRequest(contentType: "application/json", body: data, headers: ["Title": title])
        }
    }

    /// POST the finished-run notification to the configured webhook. Best-effort: an
    /// invalid URL or any network/encoding failure is swallowed (the local notification
    /// already covered the at-the-Mac case). Never throws.
    static func notify(urlString: String?, title: String, body: String,
                       summary: LoopRunSummary, session: URLSession = .shared) async {
        guard let url = endpoint(from: urlString),
              let spec = request(for: url, title: title, body: body, summary: summary) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(spec.contentType, forHTTPHeaderField: "Content-Type")
        for (k, v) in spec.headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = spec.body
        request.timeoutInterval = 12
        _ = try? await session.data(for: request)
    }
}

private extension LoopRunSummary {
    /// Cost rounded to cents for the payload, but never below a real sub-cent spend —
    /// keeps the JSON tidy without dropping a tiny nonzero cost to 0.
    var costRounded: Double {
        let cents = (costUSD * 100).rounded() / 100
        return (cents == 0 && costUSD > 0) ? costUSD : cents
    }
}
