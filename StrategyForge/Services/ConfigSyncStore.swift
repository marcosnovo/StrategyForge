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

/// CloudKit private-database sync. Native, backend-free, rides the user's iCloud
/// account. Requires the iCloud capability + container enabled in signing.
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
        _ = try await database.modifyRecords(saving: records, deleting: [],
                                             savePolicy: .allKeys, atomically: false)
    }

    func pull() async throws -> [PortableConfiguration] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (matches, _) = try await database.records(matching: query)
        return matches.compactMap { _, result in
            guard case .success(let record) = result else { return nil }
            return portable(from: record)
        }
    }

    func delete(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString) }
        _ = try await database.modifyRecords(saving: [], deleting: recordIDs,
                                             savePolicy: .allKeys, atomically: false)
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
