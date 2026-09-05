import Foundation

/// État d'un cycle de dictée, du point de vue des deux côtés du canal
/// App Group. `.pending` : le clavier a écrit la requête, l'app n'a pas
/// encore confirmé l'avoir prise en charge. `.recording` : l'app enregistre
/// activement — pas de timeout applicable, l'utilisateur contrôle la durée.
/// `.transcribing` : l'enregistrement est terminé, l'appel réseau est en
/// cours. `.ready`/`.failed` : terminal.
public enum DictationStatus: String, Sendable, Codable {
    case pending
    case recording
    case transcribing
    case ready
    case failed
}

/// Un cycle de dictée identifié par un jeton unique (`id`). Le jeton est ce
/// qui empêche un résultat périmé (annulé, expiré, d'une requête précédente)
/// de s'insérer par erreur dans une session sans rapport — le clavier ne
/// consomme jamais un `DictationRequest` dont l'id ne correspond pas à celui
/// qu'il attend.
///
/// `statusUpdatedAt` (distinct de `requestedAt`) permet un timeout par
/// phase plutôt qu'un délai unique depuis le tap initial — un enregistrement
/// long n'est pas une erreur, un `.pending` qui traîne depuis 20s l'est.
public struct DictationRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let requestedAt: Date
    public var status: DictationStatus
    public var statusUpdatedAt: Date
    public var resultText: String?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        status: DictationStatus = .pending,
        statusUpdatedAt: Date? = nil,
        resultText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt ?? requestedAt
        self.resultText = resultText
        self.errorMessage = errorMessage
    }
}
