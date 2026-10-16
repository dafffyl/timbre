//
//  FileMeetingHistoryStoreTests.swift
//  TimbreTests
//

import Foundation
import Testing
import TimbreDiarization

@testable import Timbre

struct FileMeetingHistoryStoreTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func corruptFileIsQuarantinedNotOverwritten() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("meetings.json")
        try Data("pas du json".utf8).write(to: fileURL)

        let store = FileMeetingHistoryStore(fileURL: fileURL)
        #expect(store.loadAll().isEmpty)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains { $0.hasPrefix("meetings.corrupt-") })
    }

    @Test func missingFileIsEmptyWithoutQuarantine() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileMeetingHistoryStore(fileURL: directory.appendingPathComponent("meetings.json"))
        #expect(store.loadAll().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
