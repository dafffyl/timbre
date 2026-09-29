import Testing
import Foundation
import TimbreTranscription

@testable import TimbreDiarization

private let speakerA = SpeakerID(rawValue: "A")
private let speakerB = SpeakerID(rawValue: "B")

@Test func wordFullyInsideOneSegmentIsAttributedToIt() {
    let word = TranscriptionWord(text: "bonjour", start: 1.0, end: 1.5)
    let segment = SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0)

    let result = SpeakerAlignment.align(words: [word], segments: [segment])

    #expect(result.map(\.speaker) == [speakerA])
}

@Test func wordStraddlingABoundaryGoesToTheSegmentWithMoreOverlap() {
    // Segment A : 0-4.0, segment B : 4.0-9.5. Mot 3.90-4.15 : 0.10s dans A,
    // 0.15s dans B — doit aller à B (ADR-0003, cas limite 2).
    let word = TranscriptionWord(text: "merci", start: 3.90, end: 4.15)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 4.0),
        SpeakerSegment(speaker: speakerB, start: 4.0, end: 9.5),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments)

    #expect(result.map(\.speaker) == [speakerB])
}

@Test func wordInAGapWithinToleranceGoesToTheNearestSegment() {
    let word = TranscriptionWord(text: "silence", start: 5.3, end: 5.6)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0),
        SpeakerSegment(speaker: speakerB, start: 7.0, end: 9.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments, gapTolerance: 1.0)

    // Distance à A : 0.3s. Distance à B : 1.4s. Le plus proche (A) est dans
    // la tolérance de 1.0s.
    #expect(result.map(\.speaker) == [speakerA])
}

@Test func wordExactlyAtToleranceBoundaryIsStillAttributed() {
    let word = TranscriptionWord(text: "lointain", start: 6.0, end: 6.3)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0),
        SpeakerSegment(speaker: speakerB, start: 8.0, end: 9.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments, gapTolerance: 1.0)

    // Distance à A : exactement 1.0s (la tolérance elle-même, incluse via
    // `<=`) ; distance à B : 1.7s. Cas limite de la borne, distinct du test
    // suivant qui vérifie le cas strictement au-delà des deux côtés.
    #expect(result.map(\.speaker) == [speakerA])
}

@Test func wordStrictlyBeyondToleranceOnBothSidesIsUnattributed() {
    let word = TranscriptionWord(text: "lointain", start: 6.6, end: 6.9)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0),
        SpeakerSegment(speaker: speakerB, start: 8.0, end: 9.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments, gapTolerance: 1.0)

    // Distance à A : 1.6s, distance à B : 1.1s — les deux au-delà de la
    // tolérance de 1.0s.
    #expect(result.map(\.speaker) == [nil])
}

@Test func tiedOverlapPrefersContinuityWithPreviousSpeaker() {
    // Segments adjacents (A finit pile où B commence) : le mot "alors"
    // (3.75-4.25, choisi pour être exactement représentable en binaire —
    // 3.9/4.1 ne le sont pas et donnaient une égalité seulement décimale,
    // pas bit à bit, faussant le test) a exactement 0.25s dans chacun —
    // égalité parfaite. `anchor` (placé avant dans la liste, pas
    // nécessairement avant dans le temps — seul l'ordre de traitement compte
    // pour `previousSpeaker`) ancre le locuteur B sans ambiguïté, ce qui
    // doit faire pencher l'égalité vers B plutôt que vers A (qui commence
    // pourtant plus tôt).
    let anchor = TranscriptionWord(text: "bon", start: 4.5, end: 4.75)
    let tied = TranscriptionWord(text: "alors", start: 3.75, end: 4.25)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 4.0),
        SpeakerSegment(speaker: speakerB, start: 4.0, end: 8.0),
    ]

    let result = SpeakerAlignment.align(words: [anchor, tied], segments: segments)

    #expect(result.map(\.speaker) == [speakerB, speakerB])
}

@Test func tiedOverlapWithoutPreviousSpeakerPrefersEarlierSegment() {
    // Même égalité parfaite (0.25s/0.25s, valeurs exactes en binaire — voir
    // le test précédent) que le test précédent, mais sans mot ancre avant :
    // doit retomber sur le segment qui commence le plus tôt (A, qui débute
    // à 0.0 contre 4.0 pour B) — volontairement donné dans l'ordre B puis A
    // pour vérifier que le choix suit `segment.start`, pas l'ordre du
    // tableau d'entrée.
    let word = TranscriptionWord(text: "alors", start: 3.75, end: 4.25)
    let segments = [
        SpeakerSegment(speaker: speakerB, start: 4.0, end: 8.0),
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 4.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments)

    #expect(result.map(\.speaker) == [speakerA])
}

@Test func zeroDurationWordInsideASegmentIsAttributedByContainment() {
    let word = TranscriptionWord(text: "hop", start: 2.0, end: 2.0)
    let segment = SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0)

    let result = SpeakerAlignment.align(words: [word], segments: [segment])

    #expect(result.map(\.speaker) == [speakerA])
}

@Test func zeroDurationWordInAGapFallsBackToNearestWithinTolerance() {
    let word = TranscriptionWord(text: "hop", start: 5.3, end: 5.3)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0),
        SpeakerSegment(speaker: speakerB, start: 7.0, end: 9.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments, gapTolerance: 1.0)

    #expect(result.map(\.speaker) == [speakerA])
}

@Test func noSegmentsLeavesEveryWordUnattributed() {
    let words = [
        TranscriptionWord(text: "un", start: 0.0, end: 0.3),
        TranscriptionWord(text: "deux", start: 0.3, end: 0.6),
    ]

    let result = SpeakerAlignment.align(words: words, segments: [])

    #expect(result.allSatisfy { $0.speaker == nil })
}

@Test func noWordsProducesAnEmptyResult() {
    let result = SpeakerAlignment.align(words: [], segments: [SpeakerSegment(speaker: speakerA, start: 0, end: 1)])

    #expect(result.isEmpty)
}

@Test func unsortedSegmentsInputIsHandledCorrectly() {
    let word = TranscriptionWord(text: "tard", start: 6.0, end: 6.5)
    // Volontairement dans le désordre — l'algorithme doit trier lui-même
    // (cas limite 9, ADR-0003), pas faire confiance à l'ordre d'entrée.
    let segments = [
        SpeakerSegment(speaker: speakerB, start: 5.0, end: 10.0),
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 5.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments)

    #expect(result.map(\.speaker) == [speakerB])
}

@Test func overlappingSegmentsPickTheOneWithMoreOverlapDeterministically() {
    // Parole superposée simulée : deux segments qui se chevauchent
    // franchement. Pas de "bonne" réponse sémantique (ADR-0003, cas limite
    // 4) — seulement une garantie que le choix est déterministe et suit la
    // règle documentée.
    let word = TranscriptionWord(text: "mélange", start: 2.0, end: 3.0)
    let segments = [
        SpeakerSegment(speaker: speakerA, start: 0.0, end: 2.8),
        SpeakerSegment(speaker: speakerB, start: 1.5, end: 4.0),
    ]

    let result = SpeakerAlignment.align(words: [word], segments: segments)

    // Overlap A = 0.8s (2.0–2.8), overlap B = 1.0s (2.0–3.0) -> B gagne.
    #expect(result.map(\.speaker) == [speakerB])
}
