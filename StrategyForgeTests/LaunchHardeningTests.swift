//
//  LaunchHardeningTests.swift
//  StrategyForgeTests
//
//  Pure-core tests for the launch-hardening pass: update-version comparison, the
//  CloudKit batching + retry policy, and the HTTP cache key. Network/CloudKit I/O
//  is not exercised here.
//

import Testing
import Foundation
import CloudKit
@testable import StrategyForge

struct LaunchHardeningTests {

    // MARK: - Update version compare

    @Test func newerMinorIsDetected() {
        #expect(UpdateChecker.isVersion("1.2.0", olderThan: "1.3.0"))
    }

    @Test func numericNotLexicographicOrdering() {
        // The classic trap: "1.10" must be newer than "1.9".
        #expect(UpdateChecker.isVersion("1.9.0", olderThan: "1.10.0"))
        #expect(!UpdateChecker.isVersion("1.10.0", olderThan: "1.9.0"))
    }

    @Test func equalVersionsAreNotOlder() {
        #expect(!UpdateChecker.isVersion("2.0.1", olderThan: "2.0.1"))
    }

    @Test func shorterVersionZeroPads() {
        #expect(UpdateChecker.isVersion("1.2", olderThan: "1.2.1"))
        #expect(!UpdateChecker.isVersion("1.2.0", olderThan: "1.2"))
    }

    @Test func dormantWhenManifestUnset() async {
        let saved = UpdateChecker.manifestURLString
        UpdateChecker.manifestURLString = ""
        let update = await UpdateChecker.check(current: "1.0.0")
        #expect(update == nil)
        UpdateChecker.manifestURLString = saved
    }

    // MARK: - CloudKit batching

    @Test func chunkSplitsAtLimit() {
        let items = Array(0..<950)
        let batches = CloudKitRetry.chunk(items, size: 400)
        #expect(batches.count == 3)
        #expect(batches.map(\.count) == [400, 400, 150])
        #expect(batches.flatMap { $0 } == items)
    }

    @Test func chunkOfSmallListIsOneBatch() {
        #expect(CloudKitRetry.chunk([1, 2, 3], size: 400).count == 1)
    }

    @Test func chunkOfEmptyIsEmpty() {
        #expect(CloudKitRetry.chunk([Int](), size: 400).isEmpty)
    }

    // MARK: - CloudKit retry policy

    @Test func rateLimitedErrorIsRetriedWithServerDelay() {
        let err = CKError(_nsError: NSError(domain: CKErrorDomain,
                                            code: CKError.Code.requestRateLimited.rawValue,
                                            userInfo: [CKErrorRetryAfterKey: 5.0]))
        #expect(CloudKitRetry.retryDelay(for: err) == 5.0)
    }

    @Test func nonRetryableCloudKitErrorReturnsNil() {
        let err = CKError(_nsError: NSError(domain: CKErrorDomain,
                                            code: CKError.Code.internalError.rawValue))
        #expect(CloudKitRetry.retryDelay(for: err) == nil)
    }

    @Test func nonCloudKitErrorIsNotRetried() {
        #expect(CloudKitRetry.retryDelay(for: URLError(.timedOut)) == nil)
    }

    // MARK: - HTTP cache key

    @Test func cacheKeyIsStableAndURLSpecific() {
        let a = URL(string: "https://raw.githubusercontent.com/me/cat/main/x.sfstrategy")!
        let b = URL(string: "https://raw.githubusercontent.com/me/cat/main/y.sfstrategy")!
        #expect(HTTPCache.cacheKey(for: a) == HTTPCache.cacheKey(for: a))
        #expect(HTTPCache.cacheKey(for: a) != HTTPCache.cacheKey(for: b))
        #expect(HTTPCache.cacheKey(for: a).count == 64)   // sha256 hex
    }
}
