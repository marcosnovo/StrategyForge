//
//  Account.swift
//  StrategyForge
//
//  The signed-in identity. Purely optional: the app is fully functional without
//  one. An Account gates opt-in features (currently: CloudKit sync of the portable
//  part of your configurations). Tokens live in the Keychain, never here.
//

import Foundation

enum AuthProviderKind: String, Codable, Hashable {
    case apple
    case google

    var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .google: return "Google"
        }
    }
}

struct Account: Codable, Hashable, Identifiable {
    /// Stable provider-scoped subject id (Apple user id / Google `sub`).
    var id: String
    var provider: AuthProviderKind
    var displayName: String?
    var email: String?

    /// Whether this identity can drive iCloud/CloudKit sync. CloudKit is bound to
    /// the device's iCloud account, so a Google-only sign-in gives identity but not
    /// sync — an accepted v1 limitation.
    var supportsCloudSync: Bool { provider == .apple }

    var label: String {
        displayName ?? email ?? "\(provider.displayName) account"
    }
}
