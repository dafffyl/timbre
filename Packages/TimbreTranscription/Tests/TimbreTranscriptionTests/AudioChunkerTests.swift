import Testing
import Foundation

@testable import TimbreTranscription

@Test func totalDurationUnderMaxProducesASingleChunk() {
    let chunks = AudioChunker.plan(totalDuration: 300, maxChunkDuration: 600, overlap: 10)

    #expect(chunks == [AudioChunkPlan(start: 0, end: 300)])
}

@Test func zeroDurationProducesNoChunks() {
    let chunks = AudioChunker.plan(totalDuration: 0, maxChunkDuration: 600, overlap: 10)

    #expect(chunks.isEmpty)
}

@Test func longDurationIsSplitWithOverlap() {
    // 25 minutes, chunks de 10 minutes, recouvrement de 1 minute -> pas de
    // sur-longueur, dernier reste (5 min) plus long que l'overlap (1 min),
    // donc pas absorbé : 3 chunks pleins attendus.
    let chunks = AudioChunker.plan(totalDuration: 1500, maxChunkDuration: 600, overlap: 60)

    #expect(chunks == [
        AudioChunkPlan(start: 0, end: 600),
        AudioChunkPlan(start: 540, end: 1140),
        AudioChunkPlan(start: 1080, end: 1500),
    ])
}

@Test func tinyRemainderIsAbsorbedIntoThePreviousChunkInsteadOfItsOwnChunk() {
    // maxChunkDuration=600, overlap=60 -> step=540. Après un premier chunk
    // [0,600], il resterait 1500-2 secondes de moins que step... on choisit
    // une durée totale telle que le reste après un chunk plein serait plus
    // court que l'overlap (60s) : totalDuration=630 -> tentativeEnd=600,
    // reste=30s < overlap(60s) -> absorbé.
    let chunks = AudioChunker.plan(totalDuration: 630, maxChunkDuration: 600, overlap: 60)

    #expect(chunks == [AudioChunkPlan(start: 0, end: 630)])
}

@Test func lastChunkLandsExactlyOnTotalDurationViaTheNormalLoopPath() {
    // step=540. Choisi pour que le second chunk tombe pile sur
    // totalDuration via la branche `tentativeEnd >= totalDuration`, distinct
    // du raccourci "un seul chunk" (qui s'applique seulement quand
    // totalDuration <= maxChunkDuration, pas ici).
    let chunks = AudioChunker.plan(totalDuration: 1140, maxChunkDuration: 600, overlap: 60)

    #expect(chunks == [
        AudioChunkPlan(start: 0, end: 600),
        AudioChunkPlan(start: 540, end: 1140),
    ])
}

@Test func maxDurationDerivesFromBitrateAndSizeLimitWithSafetyMargin() {
    // AAC 32 kbps mono, limite Groq 25 Mo (ADR-0001 C4), marge par défaut
    // 0,9 -> ≈ 93,75 minutes (5625 s), chiffre cité dans ADR-0003.
    let duration = AudioChunker.maxDuration(forBitrateBitsPerSecond: 32_000, sizeLimitBytes: 25_000_000)

    #expect(abs(duration - 5625) < 0.01)
}

@Test func maxDurationWithoutSafetyMarginIsTheTheoreticalLimit() {
    let duration = AudioChunker.maxDuration(
        forBitrateBitsPerSecond: 8_000_000,
        sizeLimitBytes: 1_000_000,
        safetyMargin: 1.0
    )

    #expect(abs(duration - 1.0) < 0.0001)
}
