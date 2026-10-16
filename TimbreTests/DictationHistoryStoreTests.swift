//
//  DictationHistoryStoreTests.swift
//  TimbreTests
//

import Foundation
import Testing

@testable import Timbre

struct DictationHistoryStoreTests {
    private func makeStore() -> (DictationHistoryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (DictationHistoryStore(fileURL: directory.appendingPathComponent("dictations.json")), directory)
    }

    @Test func newestFirstAndDelete() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = DictationRecord(date: Date(timeIntervalSince1970: 100), text: "un")
        let second = DictationRecord(date: Date(timeIntervalSince1970: 200), text: "deux")
        store.add(first)
        store.add(second)
        #expect(store.loadAll().map(\.text) == ["deux", "un"])

        store.delete(id: second.id)
        #expect(store.loadAll().map(\.text) == ["un"])

        store.deleteAll()
        #expect(store.loadAll().isEmpty)
    }

    @Test func capsHistorySize() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<(DictationHistoryStore.maxRecords + 5) {
            store.add(DictationRecord(date: Date(timeIntervalSince1970: Double(index)), text: "\(index)"))
        }
        #expect(store.loadAll().count == DictationHistoryStore.maxRecords)
    }

    @Test func corruptFileIsQuarantined() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("dictations.json"))

        #expect(store.loadAll().isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("dictations.corrupt-") })
    }
}
