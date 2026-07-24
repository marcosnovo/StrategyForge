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
