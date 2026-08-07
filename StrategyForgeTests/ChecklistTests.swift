//
//  ChecklistTests.swift
//  StrategyForgeTests
//
//  Launch checklist: template instantiation, progress math, and store toggle/persistence.
//

import Testing
import Foundation
@testable import Coral

@MainActor
struct ChecklistTests {

    private func freshStore() -> ChecklistStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ChecklistStore(storeDirectory: dir)
    }

    @Test func iosTemplateHasSectionsAllUndone() {
        let list = ChecklistLibrary.make(.iosApp, projectID: UUID(), es: false)
        #expect(list.sections.count >= 6)
        #expect(list.totalItems > 20)
        #expect(list.doneItems == 0)
        #expect(list.fraction == 0)
        #expect(!list.isComplete)
        #expect(list.name == "Ship an iOS app")
    }

    @Test func templateNameLocalizes() {
        let es = ChecklistLibrary.make(.webApp, projectID: nil, es: true)
        #expect(es.name == "Publicar una app web")
    }

    @Test func toggleFlipsItemAndUpdatesProgress() {
        let store = freshStore()
        let project = UUID()
        store.add(ChecklistLibrary.make(.webApp, projectID: project, es: false))
        let list = try! #require(store.checklist(forProject: project))
        let firstItem = list.sections[0].items[0]
        #expect(store.checklist(forProject: project)?.doneItems == 0)
        store.toggle(checklist: list.id, item: firstItem.id)
        #expect(store.checklist(forProject: project)?.doneItems == 1)
        store.toggle(checklist: list.id, item: firstItem.id)
        #expect(store.checklist(forProject: project)?.doneItems == 0)
    }

    @Test func completingEveryItemMarksComplete() {
        let store = freshStore()
        let project = UUID()
        store.add(ChecklistLibrary.make(.webApp, projectID: project, es: false))
        let list = try! #require(store.checklist(forProject: project))
        for s in list.sections { for i in s.items { store.toggle(checklist: list.id, item: i.id) } }
        #expect(store.checklist(forProject: project)?.isComplete == true)
    }

    @Test func persistsAcrossReload() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = UUID()
        do {
            let store = ChecklistStore(storeDirectory: dir)
            store.add(ChecklistLibrary.make(.iosApp, projectID: project, es: false))
        }
        let reloaded = ChecklistStore(storeDirectory: dir)
        #expect(reloaded.checklist(forProject: project) != nil)
    }
}
