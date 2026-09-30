import Foundation

/// Une réunion transcrite, persistée — voir `MeetingHistoryStore`. Ne garde
/// que le transcript (`turns`), jamais l'audio : ADR-0005 ne prévoit pas de
/// conserver l'enregistrement au-delà du pipeline, seulement son résultat.
public struct MeetingRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let recordedAt: Date
    public let turns: [SpeakerTurn]

    public init(id: UUID = UUID(), recordedAt: Date = Date(), turns: [SpeakerTurn]) {
        self.id = id
        self.recordedAt = recordedAt
        self.turns = turns
    }
}
