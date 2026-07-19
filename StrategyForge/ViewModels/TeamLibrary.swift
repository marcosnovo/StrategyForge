//
//  TeamLibrary.swift
//  StrategyForge
//
//  The team-preset collection, extracted from AppModel as phase 3 of the incremental
//  breakup (#35). It owns the saved teams plus the transient selection and unsaved draft.
//  AppModel forwards `savedTeams` / `selectedTeamID` / `draftTeam` here (get+set), so the
//  many team methods and the data.json round-trip keep working unchanged — the state
//  simply has one home now, independently observable and testable.
//
//  NOTE: the saved teams are still co-persisted with configurations in AppModel's
//  data.json (they share one store), so persistence stays in AppModel; this type is the
//  in-memory owner, not a separate on-disk store.
//

import Foundation

@Observable
@MainActor
final class TeamLibrary {
    /// Global library of named team presets, reusable across chats.
    var teams: [SavedTeam] = []
    /// The team currently open in the Team section (independent of the selected chat).
    var selectedID: SavedTeam.ID?
    /// A team being configured but NOT yet saved: picking a strategy opens this draft in
    /// the editor; it only joins `teams` when the user hits "Create".
    var draft: SavedTeam?
}
