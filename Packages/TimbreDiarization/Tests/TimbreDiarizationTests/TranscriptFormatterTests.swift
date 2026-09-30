import Testing
import Foundation
import TimbreTranscription

@testable import TimbreDiarization

private let speakerA = SpeakerID(rawValue: "A")
private let speakerB = SpeakerID(rawValue: "B")

private func word(_ text: String, speaker: SpeakerID?) -> AttributedWord {
    AttributedWord(word: TranscriptionWord(text: text, start: 0, end: 1), speaker: speaker)
}

@Test func emptyInputProducesNoTurns() {
    #expect(TranscriptFormatter.groupIntoTurns([]).isEmpty)
}

@Test func allWordsFromOneSpeakerFormASingleTurn() {
    let words = [
        word("bonjour", speaker: speakerA),
        word("à", speaker: speakerA),
        word("tous", speaker: speakerA),
    ]

    let turns = TranscriptFormatter.groupIntoTurns(words)

    #expect(turns == [SpeakerTurn(speaker: speakerA, text: "bonjour à tous")])
}

@Test func speakerChangeStartsANewTurn() {
    let words = [
        word("bonjour", speaker: speakerA),
        word("merci", speaker: speakerB),
        word("prends", speaker: speakerB),
    ]

    let turns = TranscriptFormatter.groupIntoTurns(words)

    #expect(turns == [
        SpeakerTurn(speaker: speakerA, text: "bonjour"),
        SpeakerTurn(speaker: speakerB, text: "merci prends"),
    ])
}

@Test func unattributedWordsFormTheirOwnTurnRatherThanMergingWithNeighbors() {
    let words = [
        word("bonjour", speaker: speakerA),
        word("silence", speaker: nil),
        word("lointain", speaker: nil),
        word("reprenons", speaker: speakerA),
    ]

    let turns = TranscriptFormatter.groupIntoTurns(words)

    #expect(turns == [
        SpeakerTurn(speaker: speakerA, text: "bonjour"),
        SpeakerTurn(speaker: nil, text: "silence lointain"),
        SpeakerTurn(speaker: speakerA, text: "reprenons"),
    ])
}

@Test func alternatingSpeakersProduceOneTurnPerWord() {
    let words = [
        word("un", speaker: speakerA),
        word("deux", speaker: speakerB),
        word("trois", speaker: speakerA),
    ]

    let turns = TranscriptFormatter.groupIntoTurns(words)

    #expect(turns.count == 3)
    #expect(turns.map(\.speaker) == [speakerA, speakerB, speakerA])
}
