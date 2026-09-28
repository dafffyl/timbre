import Testing
import Foundation

@testable import TimbreTranscription

@Test func emptyChunksProduceAnEmptyResult() {
    #expect(TranscriptStitcher.stitch([]).isEmpty)
}

@Test func singleChunkIsOffsetButOtherwiseUnchanged() {
    let chunk = TranscribedChunk(
        plan: AudioChunkPlan(start: 100, end: 110),
        words: [TranscriptionWord(text: "bonjour", start: 0, end: 0.5)]
    )

    let result = TranscriptStitcher.stitch([chunk])

    #expect(result == [TranscriptionWord(text: "bonjour", start: 100, end: 100.5)])
}

@Test func chunkWithNoWordsContributesNothing() {
    let chunk = TranscribedChunk(plan: AudioChunkPlan(start: 0, end: 10), words: [])

    #expect(TranscriptStitcher.stitch([chunk]).isEmpty)
}

@Test func twoOverlappingChunksAreStitchedAtTheirOverlapMidpoint() {
    // Chunk A : [0,110], chunk B : [100,210] -> recouvrement [100,110],
    // milieu à 105 (temps global). Mots locaux à chaque chunk, décalés par
    // leur `plan.start` respectif avant comparaison.
    let chunkA = TranscribedChunk(
        plan: AudioChunkPlan(start: 0, end: 110),
        words: [
            TranscriptionWord(text: "avant", start: 50, end: 50.5),     // global 50
            TranscriptionWord(text: "frontiere-a", start: 103, end: 103.5), // global 103, < 105 -> gardé
            TranscriptionWord(text: "trop-tard", start: 107, end: 107.5),  // global 107, >= 105 -> écarté
        ]
    )
    let chunkB = TranscribedChunk(
        plan: AudioChunkPlan(start: 100, end: 210),
        words: [
            TranscriptionWord(text: "trop-tot", start: 2, end: 2.5),       // global 102, < 105 -> écarté
            TranscriptionWord(text: "frontiere-b", start: 6, end: 6.5),    // global 106, >= 105 -> gardé
            TranscriptionWord(text: "apres", start: 50, end: 50.5),        // global 150
        ]
    )

    let result = TranscriptStitcher.stitch([chunkA, chunkB])

    #expect(result.map(\.text) == ["avant", "frontiere-a", "frontiere-b", "apres"])
    #expect(result.map(\.start) == [50, 103, 106, 150])
}

@Test func threeChunksChainTheirCutoversCorrectly() {
    let chunkA = TranscribedChunk(
        plan: AudioChunkPlan(start: 0, end: 110),
        words: [TranscriptionWord(text: "un", start: 0, end: 0.5)]
    )
    let chunkB = TranscribedChunk(
        plan: AudioChunkPlan(start: 100, end: 210),
        // Milieu du recouvrement A/B (temps global [100,110]) = 105 ; milieu
        // du recouvrement B/C (temps global [200,210]) = 205. "deux" (global
        // 150) tombe confortablement dans la portion propre à B.
        words: [TranscriptionWord(text: "deux", start: 50, end: 50.5)]
    )
    let chunkC = TranscribedChunk(
        plan: AudioChunkPlan(start: 200, end: 300),
        words: [TranscriptionWord(text: "trois", start: 50, end: 50.5)] // global 250
    )

    let result = TranscriptStitcher.stitch([chunkA, chunkB, chunkC])

    #expect(result.map(\.text) == ["un", "deux", "trois"])
    #expect(result.map(\.start) == [0, 150, 250])
}
