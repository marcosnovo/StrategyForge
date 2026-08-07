//
//  LaunchChecklist.swift
//  StrategyForge
//
//  A structured, checkable launch plan for a project — "empty repo → shipped", nothing
//  skipped. The boring parts (App Store Connect, purchases, ATT order, privacy) are where
//  launches actually go wrong, so Coral makes the checklist a first-class, trackable object
//  a team can work through, not a dead doc. Templates are curated; a checklist is a copy the
//  user owns and ticks off. Device-local, honest, Codable + tolerant decode.
//

import Foundation

struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var done: Bool = false
    /// Optional one-line hint shown under the item (the "why / gotcha").
    var hint: String = ""

    private enum CodingKeys: String, CodingKey { case id, title, done, hint }
    init(id: UUID = UUID(), title: String, done: Bool = false, hint: String = "") {
        self.id = id; self.title = title; self.done = done; self.hint = hint
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
    }
}

struct ChecklistSection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var items: [ChecklistItem]

    private enum CodingKeys: String, CodingKey { case id, title, items }
    init(id: UUID = UUID(), title: String, items: [ChecklistItem]) {
        self.id = id; self.title = title; self.items = items
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        items = try c.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
    }
}

struct LaunchChecklist: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// The code session this checklist belongs to (nil = standalone).
    var projectID: UUID?
    var sections: [ChecklistSection]
    var createdAt: Date = Date()

    var totalItems: Int { sections.reduce(0) { $0 + $1.items.count } }
    var doneItems: Int { sections.reduce(0) { $0 + $1.items.filter(\.done).count } }
    var fraction: Double { totalItems == 0 ? 0 : Double(doneItems) / Double(totalItems) }
    var isComplete: Bool { totalItems > 0 && doneItems == totalItems }

    private enum CodingKeys: String, CodingKey { case id, name, projectID, sections, createdAt }
    init(id: UUID = UUID(), name: String, projectID: UUID? = nil,
         sections: [ChecklistSection], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.projectID = projectID
        self.sections = sections; self.createdAt = createdAt
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        sections = try c.decodeIfPresent([ChecklistSection].self, forKey: .sections) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
