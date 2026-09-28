/// Distinct de `TranscriptionError` plutôt que réutilisé tel quel : les deux
/// étapes (transcription audio, nettoyage texte) sont des appels réseau
/// différents avec des échecs à distinguer côté appelant (ex. le texte brut
/// de la transcription reste utilisable même si le nettoyage échoue — voir
/// `DictationController`) — un type d'erreur partagé aurait rendu cette
/// distinction ambiguë. Pas de cas `fileTooLarge` : non pertinent pour du
/// texte.
public enum TextCleanupError: Error, Sendable, Equatable {
    case missingAPIKey
    case network(String)
    case invalidResponse
    case rateLimited(retryAfter: Double?)
    case server(statusCode: Int, message: String?)
    case decoding(String)
    case cancelled
}
