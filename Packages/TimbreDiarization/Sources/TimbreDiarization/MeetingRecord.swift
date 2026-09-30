import Foundation

/// Une réunion transcrite, persistée — voir `MeetingHistoryStore`. Ne garde
/// que le transcript (`turns`), jamais l'audio : ADR-0005 ne prévoit pas de
/// conserver l'enregistrement au-delà du pipeline, seulement son résultat.
public struct MeetingRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let recordedAt: Date
    public let turns: [SpeakerTurn]

    /// Noms personnalisés donnés par l'utilisateur ("Locuteur 1" → "Sophie"),
    /// indexés par `SpeakerID.rawValue`. Propre à cette réunion : les
    /// identifiants de FluidAudio ne sont cohérents qu'au sein d'un seul
    /// appel `process()` (ADR-0005) — le "S1" d'une réunion n'a aucun lien
    /// garanti avec le "S1" d'une autre, donc pas de mapping global entre
    /// réunions, seulement par réunion.
    public var speakerNames: [String: String]

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        turns: [SpeakerTurn],
        speakerNames: [String: String] = [:]
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.turns = turns
        self.speakerNames = speakerNames
    }
}
