//
//  ChatListStore.swift
//  StrategyForge
//
//  The chat collection (configurations) + the current selection, extracted from AppModel
//  as phase 5 of the incremental breakup (#35). AppModel forwards `configurations` /
//  `selectedConfigID` here (get+set), so every call site — including `configurations[i].x
//  = y` mutations, @Bindable bindings, and the data.json round-trip — keeps working.
//
//  NOTE: the chats are co-persisted with saved teams in AppModel's data.json (they share
//  one store), and their sync tombstones/baseline stay in AppModel with the merge logic;
//  this type is the in-memory owner, not a separate on-disk store.
//

import Foundation

@Observable
@MainActor
final class ChatListStore {
    /// Every chat/configuration the user has.
    var configurations: [Configuration] = []
    /// The chat currently open in the Chats section.
    var selectedID: Configuration.ID?
}
