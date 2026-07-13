//
//  ConfigSyncStore.swift
//  StrategyForge
//
//  Sync of the PORTABLE part of configurations across a user's own Macs. The
//  store only ever sees PortableConfiguration, so repo paths / security-scoped
//  bookmarks can never leave the device. Behind a protocol with a LocalOnly
//  default (offline / signed-out / testable) and a CloudKit implementation.
//

import Foundation
import CloudKit

protocol ConfigSyncStore {
    /// Whether syncing is currently possible (signed into iCloud + container ok).
    var isAvailable: Bool { get async }
    func push(_ configs: [PortableConfiguration]) async throws
    func pull() async throws -> [PortableConfiguration]
    func delete(ids: [UUID]) async throws
}

/// No-op store used when signed-out, offline, or on a Google-only identity.
struct LocalOnlySyncStore: ConfigSyncStore {
    var isAvailable: Bool { get async { false } }
    func push(_ configs: [PortableConfiguration]) async throws {}
    func pull() async throws -> [PortableConfiguration] { [] }
    func delete(ids: [UUID]) async throws {}
}

/// Retry + batching helpers for CloudKit, kept pure where possible so the policy is
/// unit-testable without hitting the network.
enum CloudKitRetry {
    /// CloudKit caps a single modify to 400 records; split larger writes.
    static let batchLimit = 400
    static let maxAttempts = 4

    /// The server-suggested backoff for a *retryable* CloudKit error, else nil (don't
    /// retry). Rate-limit / busy / temporary-unavailable are retryable; the rest fail fast.
    static func retryDelay(for error: Error) -> Double? {
        guard let ck = error as? CKError else { return nil }
        switch ck.code {
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            return (ck.userInfo[CKErrorRetryAfterKey] as? Double) ?? 2
        default:
            return nil
        }
    }

    /// Split items into batches of at most `size`.
    static func chunk<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0, items.count > size else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

/// CloudKit private-database sync. Native, backend-free, rides the user's iCloud
/// account. Requires the iCloud capability + container enabled in signing.
///
/// Hardened for scale: writes/deletes are chunked to CloudKit's 400-record limit,
/// reads follow the query cursor (so a user with >100 configs doesn't silently lose
/// the tail), and rate-limit / busy errors are retried honoring the server's
/// suggested backoff.
struct CloudKitSyncStore: ConfigSyncStore {
    private let recordType = "PortableConfiguration"
    private var database: CKDatabase {
        CKContainer(identifier: Constants.Auth.iCloudContainer).privateCloudDatabase
    }

    var isAvailable: Bool {
        get async {
            let status = try? await CKContainer(identifier: Constants.Auth.iCloudContainer).accountStatus()
            return status == .available
        }
    }

    func push(_ configs: [PortableConfiguration]) async throws {
        guard !configs.isEmpty else { return }
        let records = try configs.map(record(from:))
        // .allKeys = last-writer-wins; AppModel already decided these should win.
        for batch in CloudKitRetry.chunk(records, size: CloudKitRetry.batchLimit) {
            var attempt = 0
            while true {
                do {
                    _ = try await database.modifyRecords(saving: batch, deleting: [],
                                                         savePolicy: .allKeys, atomically: false)
                    break
                } catch {
                    attempt += 1
                    guard attempt < CloudKitRetry.maxAttempts,
                          let delay = CloudKitRetry.retryDelay(for: error) else { throw error }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    func pull() async throws -> [PortableConfiguration] {
        var out: [PortableConfiguration] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?
        var more = true
        while more {
            var attempt = 0
            while true {
                do {
                    // Let the tuple type infer (labels/error type come from CloudKit).
                    let page = try await (cursor == nil
                        ? database.records(matching: query)
                        : database.records(continuingMatchFrom: cursor!))
                    for (_, result) in page.matchResults {
                        if case .success(let record) = result, let p = portable(from: record) { out.append(p) }
                    }
                    cursor = page.queryCursor
                    more = (cursor != nil)
                    break
                } catch {
                    attempt += 1
                    guard attempt < CloudKitRetry.maxAttempts,
                          let delay = CloudKitRetry.retryDelay(for: error) else { throw error }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        return out
    }

    func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        for batch in CloudKitRetry.chunk(recordIDs, size: CloudKitRetry.batchLimit) {
            var attempt = 0
            while true {
                do {
                    _ = try await database.modifyRecords(saving: [], deleting: batch,
                                                         savePolicy: .allKeys, atomically: false)
                    break
                } catch {
                    attempt += 1
                    guard attempt < CloudKitRetry.maxAttempts,
                          let delay = CloudKitRetry.retryDelay(for: error) else { throw error }
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    // MARK: Mapping

    private func record(from p: PortableConfiguration) throws -> CKRecord {
        let record = CKRecord(recordType: recordType,
                              recordID: CKRecord.ID(recordName: p.id.uuidString))
        record["name"] = p.name as CKRecordValue
        record["strategy"] = try JSONEncoder().encode(p.strategy) as CKRecordValue
        record["schemaVersion"] = p.schemaVersion as CKRecordValue
        record["updatedAt"] = p.updatedAt as CKRecordValue
        return record
    }

    private func portable(from record: CKRecord) -> PortableConfiguration? {
        guard let name = record["name"] as? String,
              let data = record["strategy"] as? Data,
              let strategy = try? JSONDecoder().decode(Strategy.self, from: data),
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        return PortableConfiguration(
            id: id,
            name: name,
            strategy: strategy,
            updatedAt: record["updatedAt"] as? Date ?? .distantPast,
            schemaVersion: record["schemaVersion"] as? Int ?? PortableConfiguration.currentSchemaVersion
        )
    }
}
