import Foundation

/// Une réunion transcrite, persistée — voir `MeetingHistoryStore`. Ne garde
/// que le transcript (`turns`), jamais l'audio : ADR-0005 ne prévoit pas de
/// conserver l'enregistrement au-delà du pipeline, seulement son résultat.
/// Compte rendu généré par un LLM à partir du transcript. On garde les
/// instructions utilisées pour que « régénérer » parte de la même base, et
/// pour que le lecteur sache comment le rapport a été produit.
public struct MeetingReport: Sendable, Equatable, Codable {
    public var text: String
    public let generatedAt: Date
    public let instructions: String
    /// Catégorie et service/modèle utilisés (ADR-0009). `nil` pour les
    /// rapports générés avant leur introduction (décodage JSON tolérant).
    public let categoryName: String?
    public let serviceLabel: String?

    public init(
        text: String, generatedAt: Date = Date(), instructions: String,
        categoryName: String? = nil, serviceLabel: String? = nil
    ) {
        self.text = text
        self.generatedAt = generatedAt
        self.instructions = instructions
        self.categoryName = categoryName
        self.serviceLabel = serviceLabel
    }
}

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

    /// `nil` tant qu'aucun rapport n'a été généré — et pour les réunions
    /// enregistrées avant l'introduction des rapports (décodage JSON tolérant).
    public var report: MeetingReport?

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        turns: [SpeakerTurn],
        speakerNames: [String: String] = [:],
        report: MeetingReport? = nil
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.turns = turns
        self.speakerNames = speakerNames
        self.report = report
    }
}
