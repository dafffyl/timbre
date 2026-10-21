import Foundation
import Testing

@testable import TimbreDiarization

private let sophie = SpeakerID(rawValue: "S1")
private let marc = SpeakerID(rawValue: "S2")
private let lea = SpeakerID(rawValue: "S3")

private func turn(_ speaker: SpeakerID?, _ words: Int, _ start: TimeInterval, _ end: TimeInterval) -> SpeakerTurn {
    SpeakerTurn(speaker: speaker, text: Array(repeating: "mot", count: words).joined(separator: " "), start: start, end: end)
}

@Test func emptyTranscriptHasNoStats() {
    #expect(MeetingStats.compute(turns: []) == nil)
    #expect(MeetingStats.compute(turns: [SpeakerTurn(speaker: sophie, text: "  ")]) == nil)
}

@Test func speakingSharesAndTotalsFollowTurnDurations() throws {
    // Sophie 30 s, Marc 10 s sur 60 s de réunion.
    let stats = try #require(
        MeetingStats.compute(turns: [
            turn(sophie, 60, 0, 30), turn(marc, 20, 40, 50), turn(nil, 5, 55, 60),
        ]))
    #expect(stats.hasTimings)
    #expect(stats.totalDuration == 60)
    #expect(stats.speakingTime == 45)
    #expect(stats.speechRatio == 0.75)
    #expect(stats.participants.map(\.speaker) == [sophie, marc])
    #expect(stats.participants[0].share == 0.75)
    #expect(stats.participants[1].share == 0.25)
    #expect(stats.participants[0].wordsPerMinute == 120)
    #expect(stats.wordCount == 85)
}

@Test func balanceScoreIsHundredWhenEvenAndZeroWhenOneSpeaker() {
    #expect(MeetingStats.balanceScore(shares: [0.5, 0.5]) == 100)
    #expect(MeetingStats.balanceScore(shares: [1.0 / 3, 1.0 / 3, 1.0 / 3]) == 100)
    #expect(MeetingStats.balanceScore(shares: [1, 0]) == 0)
    #expect(MeetingStats.balanceScore(shares: [1]) == nil)
    let skewed = MeetingStats.balanceScore(shares: [0.9, 0.1]) ?? -1
    #expect(skewed > 0 && skewed < 60)
}

@Test func quickSpeakerChangeCountsAsInterruption() throws {
    let stats = try #require(
        MeetingStats.compute(turns: [
            turn(sophie, 10, 0, 10),
            turn(marc, 5, 10.1, 14),  // 0,1 s : coupure
            turn(sophie, 5, 16, 20),  // 2 s : simple réponse
        ]))
    #expect(stats.interruptionCount == 1)
    let marcStats = try #require(stats.participants.first { $0.speaker == marc })
    let sophieStats = try #require(stats.participants.first { $0.speaker == sophie })
    #expect(marcStats.interruptionsMade == 1)
    #expect(sophieStats.interruptionsReceived == 1)
    #expect(sophieStats.interruptionsMade == 0)
}

@Test func reactionDelayIgnoresLongPauses() throws {
    let stats = try #require(
        MeetingStats.compute(turns: [
            turn(sophie, 5, 0, 10), turn(marc, 5, 11, 20),  // 1 s
            turn(sophie, 5, 23, 30),  // 3 s
            turn(marc, 5, 60, 70),  // 30 s : pause, pas une réaction
        ]))
    let marcStats = try #require(stats.participants.first { $0.speaker == marc })
    let sophieStats = try #require(stats.participants.first { $0.speaker == sophie })
    #expect(marcStats.averageReactionDelay == 1)
    #expect(marcStats.reactionCount == 1)
    #expect(sophieStats.averageReactionDelay == 3)
}

@Test func longestMonologueIsTheLongestAttributedTurn() throws {
    let stats = try #require(
        MeetingStats.compute(turns: [turn(sophie, 5, 0, 10), turn(nil, 50, 10, 100), turn(marc, 5, 100, 140)]))
    #expect(stats.longestMonologue == Monologue(speaker: marc, start: 100, duration: 40))
}

@Test func rhythmSplitsWordsAcrossBuckets() throws {
    // 120 s, tranches de 30 s (≤ 12 tranches) ; 60 mots répartis sur 0-60 s.
    let stats = try #require(MeetingStats.compute(turns: [turn(sophie, 60, 0, 60), turn(marc, 1, 119, 120)]))
    #expect(stats.rhythm.count == 4)
    #expect(stats.rhythm[0].length == 30)
    #expect(stats.rhythm[0].wordsPerMinute == 60)  // 30 mots en 30 s
    #expect(stats.rhythm[2].wordsPerMinute == 0)
    #expect(stats.rhythm.reduce(0) { $0 + $1.exchanges } == 1)
}

@Test func shareByThirdTracksWhoSpeaksWhen() throws {
    let stats = try #require(MeetingStats.compute(turns: [turn(sophie, 5, 0, 30), turn(marc, 5, 30, 90)]))
    let sophieStats = try #require(stats.participants.first { $0.speaker == sophie })
    let marcStats = try #require(stats.participants.first { $0.speaker == marc })
    #expect(sophieStats.shareByThird == [1, 0, 0])
    #expect(marcStats.shareByThird == [0, 1, 1])
}

@Test func titlesAreUniqueAndNeedTwoParticipants() throws {
    let solo = try #require(MeetingStats.compute(turns: [turn(sophie, 10, 0, 10)]))
    #expect(solo.participants.allSatisfy { $0.title == nil })
    #expect(solo.balanceScore == nil)

    // Sophie parle le plus ; Marc coupe deux fois la parole ; Léa a les plus longs tours.
    let stats = try #require(
        MeetingStats.compute(turns: [
            turn(sophie, 100, 0, 40),
            turn(marc, 4, 40.1, 43),
            turn(sophie, 100, 43.5, 80),
            turn(marc, 4, 80.2, 83),
            turn(lea, 60, 90, 120),
        ]))
    func title(_ speaker: SpeakerID) -> ParticipantTitle? { stats.participants.first { $0.speaker == speaker }?.title }
    #expect(title(sophie) == .chatterbox)
    #expect(title(marc) == .interrupter)
    #expect(title(lea) == .strategist)
    let awarded = stats.participants.compactMap(\.title)
    #expect(Set(awarded).count == awarded.count)
}

@Test func lightningNeedsEnoughReactions() throws {
    var turns: [SpeakerTurn] = []
    var clock = 0.0
    // Marc répond 4 fois en 1 s, Sophie parle plus longtemps et plus vite à la reprise.
    for _ in 0..<4 {
        turns.append(turn(sophie, 30, clock, clock + 10))
        clock += 11
        turns.append(turn(marc, 3, clock, clock + 2))
        clock += 4
    }
    let stats = try #require(MeetingStats.compute(turns: turns))
    let marcStats = try #require(stats.participants.first { $0.speaker == marc })
    #expect(marcStats.reactionCount == 4)
    let sophieStats = try #require(stats.participants.first { $0.speaker == sophie })
    // Sophie reprend après 2 s de silence, Marc après 1 s : l'éclair, c'est Marc.
    #expect(marcStats.title == .lightning)
    #expect(sophieStats.title == .chatterbox)
}

@Test func legacyTurnsWithoutTimingFallBackToWords() throws {
    let stats = try #require(
        MeetingStats.compute(turns: [
            SpeakerTurn(speaker: sophie, text: "un deux trois"),
            SpeakerTurn(speaker: marc, text: "quatre"),
        ]))
    #expect(!stats.hasTimings)
    #expect(stats.totalDuration == nil)
    #expect(stats.speakingTime == nil)
    #expect(stats.timeline.isEmpty)
    #expect(stats.rhythm.isEmpty)
    #expect(stats.interruptionCount == 0)
    #expect(stats.participants[0].share == 0.75)
    #expect(stats.participants[0].shareByThird == nil)
    #expect(stats.participants[0].wordsPerMinute == nil)
    #expect(stats.balanceScore != nil)
}

@Test func missingTranscriptionMarkerIsNotCountedAsSpeech() throws {
    let stats = try #require(
        MeetingStats.compute(turns: [
            SpeakerTurn(speaker: sophie, text: "bonjour [transcription indisponible]", start: 0, end: 5)
        ]))
    #expect(stats.wordCount == 1)
}

@Test func keywordsSkipStopWordsAndFoldAccents() throws {
    let text = "le budget budget Budget équipe équipe equipe planning avec pour avec planning something"
    let stats = try #require(MeetingStats.compute(turns: [SpeakerTurn(speaker: sophie, text: text)]))
    #expect(stats.keywords.map(\.word) == ["budget", "équipe", "planning"])
    #expect(stats.keywords.map(\.count) == [3, 3, 2])
}
