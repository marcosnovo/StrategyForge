//
//  LoopWebhookNotifierTests.swift
//  StrategyForgeTests
//
//  Pure-logic tests for the remote loop webhook: payload shape (multi-keyed for
//  Slack/Discord/ntfy/generic), status mapping, and URL validation. No network — the
//  POST itself is a thin best-effort wrapper over URLSession.
//

import Testing
import Foundation
@testable import Coral

struct LoopWebhookPayloadTests {

    private func summary(pass: Bool?, reason: String? = nil,
                         iterations: Int = 3, tokens: Int = 1200, cost: Double = 0.042) -> LoopRunSummary {
        LoopRunSummary(date: Date(timeIntervalSince1970: 0), pass: pass, reason: reason,
                       iterations: iterations, tokens: tokens, costUSD: cost)
    }

    @Test func statusMapsTriState() {
        #expect(LoopWebhookPayload.status(for: true) == "passed")
        #expect(LoopWebhookPayload.status(for: false) == "failed")
        #expect(LoopWebhookPayload.status(for: nil) == "unverified")
    }

    @Test func payloadCarriesMultiKeyBodyForCommonServices() {
        let p = LoopWebhookNotifier.payload(title: "Nightly refactor",
                                            body: "Nightly refactor passed",
                                            summary: summary(pass: true, reason: "all tests green"))
        // Structured fields.
        #expect(p.title == "Nightly refactor")
        #expect(p.message == "Nightly refactor passed")
        #expect(p.status == "passed")
        #expect(p.iterations == 3)
        #expect(p.tokens == 1200)
        #expect(p.reason == "all tests green")
        #expect(p.event == "loop.finished")
        // Slack (`text`) and Discord (`content`) both get the same one-liner.
        #expect(p.text == "Nightly refactor: Nightly refactor passed")
        #expect(p.content == p.text)
    }

    @Test func emptyReasonBecomesNil() {
        let p = LoopWebhookNotifier.payload(title: "L", body: "b", summary: summary(pass: false, reason: ""))
        #expect(p.reason == nil)
        #expect(p.status == "failed")
    }

    @Test func costIsRoundedButNeverDropsASubCentSpendToZero() {
        let rounded = LoopWebhookNotifier.payload(title: "L", body: "b",
                                                  summary: summary(pass: true, cost: 0.12345))
        #expect(rounded.costUSD == 0.12)
        // A tiny nonzero cost must survive rather than round to 0.
        let tiny = LoopWebhookNotifier.payload(title: "L", body: "b",
                                               summary: summary(pass: true, cost: 0.0003))
        #expect(tiny.costUSD == 0.0003)
    }

    @Test func payloadEncodesToJSONWithExpectedKeys() throws {
        let p = LoopWebhookNotifier.payload(title: "L", body: "done", summary: summary(pass: nil))
        let data = try JSONEncoder().encode(p)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["text"] as? String == "L: done")
        #expect(obj["content"] as? String == "L: done")
        #expect(obj["status"] as? String == "unverified")
        #expect(obj["event"] as? String == "loop.finished")
    }
}

struct LoopWebhookEndpointTests {

    @Test func acceptsHTTPAndHTTPSURLs() {
        #expect(LoopWebhookNotifier.endpoint(from: "https://ntfy.sh/my-topic") != nil)
        #expect(LoopWebhookNotifier.endpoint(from: "http://localhost:8080/hook") != nil)
        // Surrounding whitespace is trimmed.
        #expect(LoopWebhookNotifier.endpoint(from: "  https://example.com/x \n") != nil)
    }

    @Test func rejectsEmptyOrNonHTTPURLs() {
        #expect(LoopWebhookNotifier.endpoint(from: nil) == nil)
        #expect(LoopWebhookNotifier.endpoint(from: "") == nil)
        #expect(LoopWebhookNotifier.endpoint(from: "   ") == nil)
        #expect(LoopWebhookNotifier.endpoint(from: "ftp://example.com/x") == nil)
        #expect(LoopWebhookNotifier.endpoint(from: "not a url") == nil)
        #expect(LoopWebhookNotifier.endpoint(from: "mailto:me@example.com") == nil)
    }
}

struct LoopWebhookEncodingTests {

    private func summary(pass: Bool?) -> LoopRunSummary {
        LoopRunSummary(date: Date(timeIntervalSince1970: 0), pass: pass, reason: nil,
                       iterations: 1, tokens: 10, costUSD: 0.01)
    }

    @Test func ntfyHostsUseRawTextEncoding() throws {
        // A topic URL publishes its RAW body as the message, so JSON there would show the
        // literal blob — ntfy.sh must use plain text + headers instead.
        let topic = try #require(LoopWebhookNotifier.endpoint(from: "https://ntfy.sh/my-topic"))
        #expect(LoopWebhookNotifier.encoding(for: topic) == .ntfy)
        let selfHostedSub = try #require(LoopWebhookNotifier.endpoint(from: "https://push.ntfy.sh/topic"))
        #expect(LoopWebhookNotifier.encoding(for: selfHostedSub) == .ntfy)
    }

    @Test func slackDiscordAndGenericUseJSON() throws {
        for s in ["https://hooks.slack.com/services/T/B/x",
                  "https://discord.com/api/webhooks/1/abc",
                  "https://example.com/hook",
                  "https://notify.ntfy.example.com/topic"] {   // not an ntfy.sh host
            let url = try #require(LoopWebhookNotifier.endpoint(from: s))
            #expect(LoopWebhookNotifier.encoding(for: url) == .json)
        }
    }

    @Test func ntfyRequestIsPlainTextWithTitleAndOutcomeTag() throws {
        let url = try #require(LoopWebhookNotifier.endpoint(from: "https://ntfy.sh/my-topic"))
        let req = try #require(LoopWebhookNotifier.request(for: url, title: "Nightly",
                                                           body: "Nightly failed", summary: summary(pass: false)))
        #expect(req.contentType.hasPrefix("text/plain"))
        #expect(String(data: req.body, encoding: .utf8) == "Nightly failed")   // raw message, not JSON
        #expect(req.headers["Title"] == "Nightly")
        #expect(req.headers["Tags"] == "x")                                     // failed → ✗
    }

    @Test func ntfyTagReflectsOutcome() {
        #expect(LoopWebhookNotifier.ntfyTag(for: true) == "white_check_mark")
        #expect(LoopWebhookNotifier.ntfyTag(for: false) == "x")
        #expect(LoopWebhookNotifier.ntfyTag(for: nil) == "grey_question")
    }

    @Test func jsonRequestKeepsStructuredBody() throws {
        let url = try #require(LoopWebhookNotifier.endpoint(from: "https://hooks.slack.com/x"))
        let req = try #require(LoopWebhookNotifier.request(for: url, title: "L",
                                                           body: "done", summary: summary(pass: true)))
        #expect(req.contentType == "application/json")
        let obj = try #require(try JSONSerialization.jsonObject(with: req.body) as? [String: Any])
        #expect(obj["text"] as? String == "L: done")   // Slack-compatible field survives
    }
}
