import Foundation
import Testing

@testable import TimbreDiarization

private func voice(_ vector: [Float], seconds: TimeInterval = 60) -> SpeakerVoice {
    SpeakerVoice(embedding: VoiceMath.normalized(vector), seconds: seconds)
}

private let s1 = SpeakerID(rawValue: "S1")
private let s2 = SpeakerID(rawValue: "S2")

@Test func cosineOfIdenticalAndOrthogonalVectors() {
    #expect(abs(VoiceMath.cosine([1, 0], [1, 0]) - 1) < 1e-6)
    #expect(abs(VoiceMath.cosine([1, 0], [0, 1])) < 1e-6)
    #expect(VoiceMath.cosine([1, 0], [1, 0, 0]) == 0)
    #expect(VoiceMath.cosine([0, 0], [1, 0]) == 0)
}

@Test func matchNamesTheClosestKnownVoice() {
    let sophie = VoiceProfile(name: "Sophie", voice: voice([1, 0, 0]))
    let marc = VoiceProfile(name: "Marc", voice: voice([0, 1, 0]))
    let result = SpeakerMatcher.match(
        voices: [s1: voice([0.95, 0.1, 0]), s2: voice([0.05, 1, 0])],
        profiles: [sophie, marc])
    #expect(result[s1]?.name == "Sophie")
    #expect(result[s2]?.name == "Marc")
}

@Test func matchIgnoresUnknownVoices() {
    let sophie = VoiceProfile(name: "Sophie", voice: voice([1, 0, 0]))
    let result = SpeakerMatcher.match(voices: [s1: voice([0, 0, 1])], profiles: [sophie])
    #expect(result.isEmpty)
}

@Test func ambiguousVoiceBetweenTwoProfilesIsNotNamed() {
    let a = VoiceProfile(name: "A", voice: voice([1, 0.02, 0]))
    let b = VoiceProfile(name: "B", voice: voice([1, -0.02, 0]))
    let result = SpeakerMatcher.match(voices: [s1: voice([1, 0, 0])], profiles: [a, b])
    #expect(result.isEmpty)
}

@Test func aProfileIsAssignedToOnlyOneSpeaker() {
    let sophie = VoiceProfile(name: "Sophie", voice: voice([1, 0, 0]))
    let result = SpeakerMatcher.match(
        voices: [s1: voice([1, 0.05, 0]), s2: voice([0.9, 0.3, 0])],
        profiles: [sophie], threshold: 0.6)
    #expect(result.count == 1)
    #expect(result[s1]?.name == "Sophie")
}

@Test func noProfilesMeansNoMatches() {
    #expect(SpeakerMatcher.match(voices: [s1: voice([1, 0])], profiles: []).isEmpty)
}

@Test func mergeMovesProfileTowardNewObservationProportionally() {
    var profile = VoiceProfile(name: "Sophie", voice: voice([1, 0], seconds: 60))
    profile.merge(voice([0, 1], seconds: 60))
    // Poids égaux : à mi-chemin entre les deux directions.
    #expect(abs(VoiceMath.cosine(profile.embedding, [1, 1]) - 1) < 1e-5)
    #expect(profile.totalSeconds == 120)
}

@Test func mergeIgnoresDimensionMismatchAndZeroDuration() {
    var profile = VoiceProfile(name: "Sophie", voice: voice([1, 0], seconds: 60))
    let before = profile
    profile.merge(voice([1, 0, 0]))
    profile.merge(voice([0, 1], seconds: 0))
    #expect(profile == before)
}

@Test func weightedMeanIsNormalized() throws {
    let mean = try #require(VoiceMath.weightedMean([(embedding: [2, 0], weight: 3), (embedding: [0, 5], weight: 1)]))
    #expect(abs(mean.reduce(0) { $0 + $1 * $1 } - 1) < 1e-5)
    #expect(mean[0] > mean[1])
}

@Test func defaultDetailedDiarizationHasNoVoices() async throws {
    let output = try await FakeDiarizationProvider().diarizeDetailed(URL(fileURLWithPath: "/dev/null"))
    #expect(output.speakerVoices.isEmpty)
}
