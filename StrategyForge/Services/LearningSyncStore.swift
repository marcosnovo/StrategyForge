//
//  LearningSyncStore.swift
//  StrategyForge
//
//  CloudKit sync of the cross-project knowledge base across a user's own Macs — the
//  learnings roam so a lesson learned on one machine feeds teams on another. Mirrors
//  ConfigSyncStore: a protocol with a LocalOnly default (offline / signed-out / testable)
//  and a CloudKit implementation reusing CloudKitRetry (batching + backoff).
//
//  Dormant by default (MemoryStore ships with the LocalOnly store) until the CloudKit
//  "Learning" record type is added in the container's schema and verified on a real
//  device — same pending capability as config sync. The merge itself is pure + tested.
//

import Foundation
import CloudKit

protocol LearningSyncStore {
    var isAvailable: Bool { get async }
    func push(_ learnings: [Learning]) async throws
    func pull() async throws -> [Learning]
    func delete(ids: [UUID]) async throws
}

/// No-op store used when signed-out, offline, or before CloudKit is set up.
struct LocalOnlyLearningSync: LearningSyncStore {
    var isAvailable: Bool { get async { false } }
    func push(_ learnings: [Learning]) async throws {}
    func pull() async throws -> [Learning] { [] }
    func delete(ids: [UUID]) async throws {}
}

/// Pure, unit-testable reconciliation of a local + remote learning set. Union by id,
/// last-writer-wins by `updatedAt` — no repo bindings to preserve (unlike configs), so
/// no conflict copies are needed for these small knowledge entries.
enum LearningMerge {
    static func merge(local: [Learning], remote: [Learning]) -> [Learning] {
        var result = local
        for r in remote {
            if let i = result.firstIndex(where: { $0.id == r.id }) {
                if r.updatedAt > result[i].updatedAt { result[i] = r }   // remote newer wins
            } else {
                result.append(r)                                          // remote-only → adopt
            }
        }
        return result
    }
}

/// CloudKit private-database sync for learnings. Stores each learning as one record
/// carrying its JSON blob + `updatedAt` (the LWW key). Backend-free, rides the user's
/// iCloud account. Requires the iCloud capability + a "Learning" record type.
struct CloudKitLearningSync: LearningSyncStore {
    private let recordType = "Learning"
    private var database: CKDatabase {
        CKContainer(identifier: Constants.Auth.iCloudContainer).privateCloudDatabase
    }

    var isAvailable: Bool {
        get async {
            let status = try? await CKContainer(identifier: Constants.Auth.iCloudContainer).accountStatus()
            return status == .available
        }
    }

    func push(_ learnings: [Learning]) async throws {
        guard !learnings.isEmpty else { return }
        let records = try learnings.map(record(from:))
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

    func pull() async throws -> [Learning] {
        var out: [Learning] = []
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?
        var more = true
        while more {
            var attempt = 0
            while true {
                do {
                    let page = try await (cursor == nil
                        ? database.records(matching: query)
                        : database.records(continuingMatchFrom: cursor!))
                    for (_, result) in page.matchResults {
                        if case .success(let record) = result, let l = learning(from: record) { out.append(l) }
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

    private func record(from l: Learning) throws -> CKRecord {
        let record = CKRecord(recordType: recordType,
                              recordID: CKRecord.ID(recordName: l.id.uuidString))
        record["payload"] = try JSONEncoder().encode(l) as CKRecordValue
        record["updatedAt"] = l.updatedAt as CKRecordValue   // queryable LWW key
        return record
    }

    private func learning(from record: CKRecord) -> Learning? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(Learning.self, from: data)
    }
}
