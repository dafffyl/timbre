import Foundation

/// État d'un cycle de dictée, du point de vue des deux côtés du canal
/// App Group. `.pending` : le clavier attend, l'app n'a pas encore répondu.
/// `.ready` : la réponse est là. `.failed` : l'app a explicitement renoncé.
public enum DictationStatus: String, Sendable, Codable {
    case pending
    case ready
    case failed
}

/// Un cycle de dictée identifié par un jeton unique (`id`). Le jeton est ce
/// qui empêche un résultat périmé (annulé, expiré, d'une requête précédente)
/// de s'insérer par erreur dans une session sans rapport — le clavier ne
/// consomme jamais un `DictationRequest` dont l'id ne correspond pas à celui
/// qu'il attend.
public struct DictationRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let requestedAt: Date
    public var status: DictationStatus
    public var resultText: String?

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        status: DictationStatus = .pending,
        resultText: String? = nil
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.status = status
        self.resultText = resultText
    }
}
