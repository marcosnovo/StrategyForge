//
//  SavedTeam.swift
//  StrategyForge
//
//  A named, reusable team preset. Users save a configured strategy (roles, models,
//  providers) under a friendly name ("My backend team") into a global library, then
//  apply it to any chat — or start a chat from one. Persisted alongside configurations.
//

import Foundation

struct SavedTeam: Codable, Identifiable, Hashable {
    var id: UUID
    /// The user-facing label for this preset (distinct from `strategy.name`, which
    /// is the topology's name, e.g. "Orchestrator + Workers").
    var name: String
    /// The captured topology: roles, models, providers, counts, tools, prompts.
    var strategy: Strategy
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         strategy: Strategy,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A fresh copy of the stored strategy with new identifiers, so applying the same
    /// preset to several chats never makes two configurations share role/strategy ids.
    func strategyCopy() -> Strategy {
        var s = strategy
        s.id = UUID()
        for i in s.roles.indices { s.roles[i].id = UUID() }
        return s
    }
}
