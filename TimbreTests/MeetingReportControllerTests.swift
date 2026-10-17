//
//  MeetingReportControllerTests.swift
//  TimbreTests
//

import Foundation
import Testing
import TimbreDiarization
import TimbreTranscription

@testable import Timbre

private struct FakeSummarizer: MeetingSummaryProvider {
    let result: Result<String, SummaryError>
    func summarize(_ request: MeetingSummaryRequest) async throws -> String {
        try result.get()
    }
}

private final class FakeStore: MeetingHistoryStore, @unchecked Sendable {
    // Test uniquement : un seul accès à la fois depuis le test (MainActor).
    var updated: [MeetingRecord] = []
    func loadAll() -> [MeetingRecord] { [] }
    func save(_ record: MeetingRecord) {}
    func update(_ record: MeetingRecord) { updated.append(record) }
    func delete(id: MeetingRecord.ID) {}
}

@MainActor
struct MeetingReportControllerTests {
    private let record = MeetingRecord(turns: [SpeakerTurn(speaker: SpeakerID(rawValue: "S1"), text: "bonjour")])

    @Test func successStoresReportWithInstructions() async {
        let store = FakeStore()
        let controller = MeetingReportController(
            provider: { _ in FakeSummarizer(result: .success("## Rapport")) }, store: store)

        let updated = await controller.generate(for: record, instructions: "Court.")

        #expect(updated?.report?.text == "## Rapport")
        #expect(updated?.report?.instructions == "Court.")
        #expect(store.updated.count == 1)
        #expect(controller.state == .idle)
    }

    @Test func failureKeepsExistingReportAndReportsMessage() async {
        var withReport = record
        withReport.report = MeetingReport(text: "ancien", instructions: "")
        let store = FakeStore()
        let controller = MeetingReportController(
            provider: { _ in FakeSummarizer(result: .failure(.network("offline"))) }, store: store)

        let updated = await controller.generate(for: withReport, instructions: "x")

        #expect(updated == nil)
        #expect(store.updated.isEmpty)
        guard case .failed = controller.state else {
            Issue.record("État inattendu : \(controller.state)")
            return
        }
    }

    @Test func markdownLineParsing() {
        #expect(MarkdownReportText.heading(in: "## Décisions")?.level == 2)
        #expect(MarkdownReportText.heading(in: "##Pas un titre") == nil)
        #expect(MarkdownReportText.bullet(in: "- action")?.text == "action")
        #expect(MarkdownReportText.bullet(in: "2. deuxième")?.marker == "2.")
        #expect(MarkdownReportText.bullet(in: "2024 était bien") == nil)
    }
}
