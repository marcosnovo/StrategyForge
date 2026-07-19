//
//  ProviderRegistry.swift
//  StrategyForge
//
//  Which provider CLIs are currently installed/detected — extracted from AppModel as
//  phase 4 of the incremental breakup (#35). This is the one piece of OWNED provider
//  state (the rest — plans, API keys, deprioritized/model-locked — is derived from
//  settings/Keychain/usage and stays in AppModel). Transient (re-detected each launch),
//  so nothing here is persisted. AppModel forwards `connectedProviders` here.
//

import Foundation

@Observable
@MainActor
final class ProviderRegistry {
    /// Providers whose CLI is installed/detected. Drives locked vs selectable state in the
    /// model/provider pickers. Defaults to Claude (the always-present primary).
    var connected: Set<AIProvider> = [.claude]

    /// Whether a provider can be selected right now (its CLI is installed).
    func isConnected(_ provider: AIProvider) -> Bool { connected.contains(provider) }

    /// Re-detect which provider CLIs resolve, off the main thread. `binaryFor` yields the
    /// configured binary name/path per provider (from AppSettings).
    func refresh(binaryFor: @escaping (AIProvider) -> String) async {
        var found: Set<AIProvider> = []
        for p in AIProvider.allCases {
            let name = binaryFor(p)
            if await Task.detached(operation: { ClaudeRunner.resolveBinary(name) }).value != nil {
                found.insert(p)
            }
        }
        connected = found
    }
}
