import Testing
import Foundation

@testable import TimbreDiarization

@Test func meetingRecordRoundTripsThroughJSON() throws {
    let original = MeetingRecord(
        recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
        turns: [
            SpeakerTurn(speaker: SpeakerID(rawValue: "S1"), text: "bonjour à tous"),
            SpeakerTurn(speaker: nil, text: "silence lointain"),
        ]
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MeetingRecord.self, from: data)

    #expect(decoded == original)
}

@Test func arrayOfMeetingRecordsRoundTripsThroughJSON() throws {
    let records = [
        MeetingRecord(turns: [SpeakerTurn(speaker: SpeakerID(rawValue: "S1"), text: "un")]),
        MeetingRecord(turns: [SpeakerTurn(speaker: SpeakerID(rawValue: "S2"), text: "deux")]),
    ]

    let data = try JSONEncoder().encode(records)
    let decoded = try JSONDecoder().decode([MeetingRecord].self, from: data)

    #expect(decoded == records)
}
