import Foundation
import Testing

@testable import TimbreDiarization

private let sophie = SpeakerID(rawValue: "S1")

@Test func markdownHasTitleAndBoldSpeakers() {
    let turns = [
        SpeakerTurn(speaker: sophie, text: "bonjour"),
        SpeakerTurn(speaker: nil, text: "merci"),
    ]
    let output = TranscriptExporter.markdown(turns: turns, labels: ["Sophie", "Non identifié"], title: "Réunion")
    #expect(output == "# Réunion\n\n**Sophie** :\nbonjour\n\n**Non identifié** :\nmerci\n")
}

@Test func srtSplitsLongTurnsProportionally() {
    let turns = [SpeakerTurn(speaker: sophie, text: "un deux trois quatre", start: 0, end: 4)]
    let output = TranscriptExporter.srt(turns: turns, labels: ["Sophie"], maxWordsPerCue: 2)
    #expect(output == """
        1
        00:00:00,000 --> 00:00:02,000
        Sophie : un deux

        2
        00:00:02,000 --> 00:00:04,000
        trois quatre

        """)
}

@Test func srtSkipsTurnsWithoutTimingAndReportsAvailability() {
    let legacy = [SpeakerTurn(speaker: sophie, text: "ancien")]
    #expect(!TranscriptExporter.canExportSRT(turns: legacy))
    #expect(TranscriptExporter.srt(turns: legacy, labels: ["Sophie"]).isEmpty)
}

@Test func timestampFormatsHoursMinutesMillis() {
    #expect(TranscriptExporter.timestamp(3_661.5) == "01:01:01,500")
}

@Test func searchIgnoresCaseAndAccents() {
    let record = MeetingRecord(
        turns: [SpeakerTurn(speaker: sophie, text: "Réunion budget")],
        speakerNames: ["S1": "Élodie"]
    )
    #expect(record.matches(searchQuery: "reunion"))
    #expect(record.matches(searchQuery: "ELODIE"))
    #expect(record.matches(searchQuery: "  "))
    #expect(!record.matches(searchQuery: "planning"))
}

@Test func legacyTurnWithoutTimingStillDecodes() throws {
    let json = Data(#"{"speaker":"S1","text":"ancien"}"#.utf8)
    let turn = try JSONDecoder().decode(SpeakerTurn.self, from: json)
    #expect(turn.start == nil && turn.end == nil)
}
