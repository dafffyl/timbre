import Testing
import Foundation
import TimbreTranscription

@testable import TimbreDiarization

/// Scénario de bout en bout sur données JSON plutôt qu'assemblé en Swift
/// (contrairement aux tests unitaires de `SpeakerAlignmentTests`) — établit
/// le patron "fixtures JSON pures" annoncé pour ce package dans `CLAUDE.md`,
/// utile ici parce qu'une réunion réaliste (3 tours de parole, un trou de
/// silence) se lit plus clairement en données qu'en littéraux Swift imbriqués.
private struct MeetingFixture: Decodable {
    struct Segment: Decodable {
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
    }
    struct Word: Decodable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }
    struct ExpectedWord: Decodable {
        let text: String
        let speaker: String?
    }

    let segments: [Segment]
    let words: [Word]
    let expected: [ExpectedWord]
}

@Test func realisticMeetingFixtureMatchesExpectedAttribution() throws {
    let url = try #require(
        Bundle.module.url(forResource: "realistic-meeting", withExtension: "json", subdirectory: "Fixtures")
    )
    let fixture = try JSONDecoder().decode(MeetingFixture.self, from: Data(contentsOf: url))

    let words = fixture.words.map { TranscriptionWord(text: $0.text, start: $0.start, end: $0.end) }
    let segments = fixture.segments.map {
        SpeakerSegment(speaker: SpeakerID(rawValue: $0.speaker), start: $0.start, end: $0.end)
    }

    let result = SpeakerAlignment.align(words: words, segments: segments)

    #expect(result.count == fixture.expected.count)
    for (attributed, expected) in zip(result, fixture.expected) {
        #expect(attributed.word.text == expected.text)
        #expect(attributed.speaker?.rawValue == expected.speaker)
    }
}
