import Foundation

/// Une tranche de temps continue attribuée à un locuteur par le moteur de
/// diarisation (FluidAudio) — `start`/`end` dans le même référentiel de
/// temps que les horodatages mot par mot de `TranscriptionWord` (secondes
/// depuis le début de l'enregistrement).
public struct SpeakerSegment: Sendable, Equatable {
    public let speaker: SpeakerID
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speaker: SpeakerID, start: TimeInterval, end: TimeInterval) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}
