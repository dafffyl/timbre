//
//  ReportCategoryStoreTests.swift
//  TimbreTests
//

import Foundation
import Testing
import TimbreTranscription

@testable import Timbre

struct ReportCategoryStoreTests {
    /// `UserDefaults` isolé : jamais les vrais réglages de l'app.
    private func makeStore() -> (ReportCategoryStore, UserDefaults) {
        let suite = "tests.report-categories.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ReportCategoryStore(defaults: defaults), defaults)
    }

    @Test func startsWithStructuredAndShortCategories() {
        let (store, _) = makeStore()
        #expect(store.categories.map(\.format) == [.structured, .short])
        #expect(store.selected.id == ReportCategoryStore.structuredID)
    }

    @Test func customLegacyInstructionsAreMigratedButTheOldDefaultIsNot() {
        let (untouched, untouchedDefaults) = makeStore()
        untouchedDefaults.set(
            ReportCategoryStore.legacyDefaultInstructions, forKey: "fr.dafffyl.timbre.summary.instructions")
        #expect(untouched.categories.count == 2)

        let (custom, customDefaults) = makeStore()
        customDefaults.set("Toujours tutoyer.", forKey: "fr.dafffyl.timbre.summary.instructions")
        let migrated = custom.categories.last
        #expect(custom.categories.count == 3)
        #expect(migrated?.instructions == "Toujours tutoyer.")
        #expect(migrated?.format == .free)
    }

    @Test func updateAddsOrReplacesAndPersists() {
        let (store, defaults) = makeStore()
        var client = ReportCategory(name: "Client", format: .free, instructions: "Note les engagements.")
        store.update(client)
        client.name = "Réunion client"
        store.update(client)

        let reloaded = ReportCategoryStore(defaults: defaults).categories
        #expect(reloaded.filter { $0.id == client.id }.map(\.name) == ["Réunion client"])
        #expect(reloaded.count == 3)
    }

    @Test func lastCategoryCannotBeDeleted() {
        let (store, _) = makeStore()
        #expect(store.delete(id: ReportCategoryStore.shortID))
        #expect(!store.delete(id: ReportCategoryStore.structuredID))
        #expect(store.categories.count == 1)
    }

    @Test func selectionFallsBackWhenTheSelectedCategoryIsDeleted() {
        let (store, _) = makeStore()
        store.select(ReportCategoryStore.shortID)
        #expect(store.selected.id == ReportCategoryStore.shortID)
        store.delete(id: ReportCategoryStore.shortID)
        #expect(store.selected.id == ReportCategoryStore.structuredID)
    }
}
