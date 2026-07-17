//
//  AuthModel.swift
//  StrategyForge
//
//  Opt-in identity + iCloud sync coordinator. The app is fully usable signed-out;
//  this only powers "keep my strategy library across my Macs". Sign in with Apple
//  enables CloudKit sync; Google provides identity only (CloudKit is Apple-account
//  bound). Never gates generation, file writing, Terminal launch, or downloads.
//

import Foundation
import Observation

@MainActor
@Observable
final class AuthModel {
    private(set) var account: Account?
    var isBusy = false
    var lastError: String?
    var lastSyncMessage: String?

    @ObservationIgnored private let auth: AuthenticationService = AuthService()
    @ObservationIgnored private var syncStore: ConfigSyncStore = LocalOnlySyncStore()
    private static let accountKey = "account"

    var isSignedIn: Bool { account != nil }
    /// Whether this identity can drive iCloud sync (Apple only).
    var canSync: Bool { account?.supportsCloudSync == true }

    init() {
        account = KeychainStore.codable(Account.self, for: Self.accountKey)
        refreshStore()
    }

    // MARK: - Identity

    func signIn(_ kind: AuthProviderKind) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let acc = try await auth.signIn(with: kind)
            account = acc
            KeychainStore.setCodable(acc, for: Self.accountKey)
            refreshStore()
        } catch AuthError.cancelled {
            // User backed out — not an error worth surfacing.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        account = nil
        lastSyncMessage = nil
        KeychainStore.delete(Self.accountKey)
        KeychainStore.delete("google.refreshToken")
        refreshStore()
    }

    private func refreshStore() {
        syncStore = canSync ? CloudKitSyncStore() : LocalOnlySyncStore()
    }

    // MARK: - Sync

    /// Two-way merge with iCloud: pull remote, last-writer-wins into local, push back.
    func sync(_ appModel: AppModel) async {
        guard canSync else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            guard await syncStore.isAvailable else {
                lastError = appModel.t("sync.unavailable")
                return
            }
            let remote = try await syncStore.pull()
            let merged = appModel.mergeRemote(remote)
            try await syncStore.push(merged)
            lastSyncMessage = appModel.t("sync.done", merged.count)
        } catch {
            lastError = appModel.t("sync.failed", error.localizedDescription)
        }
    }
}
