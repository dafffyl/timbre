import Foundation

/// État d'un cycle de dictée, du point de vue des deux côtés du canal
/// App Group. `.pending` : le clavier a écrit la requête, l'app n'a pas
/// encore confirmé l'avoir prise en charge. `.recording` : l'app enregistre
/// activement, y compris en arrière-plan (ADR-0002) — pas de timeout
/// applicatif, l'utilisateur contrôle la durée (l'app applique elle-même
/// une durée maximale de sécurité). `.transcribing` : l'enregistrement est
/// terminé, l'appel réseau est en cours. `.ready`/`.failed` : terminal.
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
/// qu'il attend, et l'app (ADR-0002) traite la disparition/le remplacement
/// de son id comme une annulation.
///
/// `statusUpdatedAt` (distinct de `requestedAt`) permet un timeout par
/// phase plutôt qu'un délai unique depuis le tap initial — un enregistrement
/// long n'est pas une erreur, un `.pending` qui traîne depuis 20s l'est.
///
/// `stopRequested` : signal du clavier vers l'app pendant `.recording`
/// (ADR-0002) — l'app le lit à chaque bloc audio traité (toutes les
/// ~90ms) pendant qu'elle est en arrière-plan, pas besoin d'une Darwin
/// notification séparée pour un signal aussi fréquent.
///
/// `audioLevel` : niveau audio courant (0...1, échelle dB normalisée),
/// mis à jour par l'app pendant `.recording` pour que le clavier — qui n'a
/// et n'aura jamais accès au micro (C1) — puisse quand même afficher une
/// onde qui réagit réellement à la voix, comme Wispr Flow.
public struct DictationRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let requestedAt: Date
    public var status: DictationStatus
    public var statusUpdatedAt: Date
    public var stopRequested: Bool
    public var audioLevel: Float
    public var resultText: String?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        status: DictationStatus = .pending,
        statusUpdatedAt: Date? = nil,
        stopRequested: Bool = false,
        audioLevel: Float = 0,
        resultText: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt ?? requestedAt
        self.stopRequested = stopRequested
        self.audioLevel = audioLevel
        self.resultText = resultText
        self.errorMessage = errorMessage
    }
}
