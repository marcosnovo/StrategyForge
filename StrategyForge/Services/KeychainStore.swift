//
//  KeychainStore.swift
//  StrategyForge
//
//  Minimal, dependency-free Keychain wrapper for the few small secrets auth needs
//  (the signed-in Account blob and any OAuth refresh token). App Sandbox permits
//  Keychain access; no keychain-access-group is required for single-app storage.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.marcosnovo.StrategyForge.auth"

    @discardableResult
    static func set(_ data: Data, for key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            // WhenUnlocked: these secrets are only ever read while the app is in use;
            // not accessible when the screen is locked.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        // Update in place when it exists — no delete→add gap that would lose the secret
        // if the process died in between.
        let updateStatus = SecItemUpdate(base as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            return SecItemAdd(base.merging(attrs) { $1 } as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // Convenience for Codable values.
    static func setCodable<T: Encodable>(_ value: T, for key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            if !set(data, for: key) { DiagnosticsLog.record("Keychain write failed for “\(key)”.") }
        } catch {
            DiagnosticsLog.record("Keychain encode failed for “\(key)”: \(error.localizedDescription)")
        }
    }

    static func codable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = data(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
