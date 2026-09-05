/// Erreurs typées — jamais de `try?` silencieux côté appelant (convention du
/// projet). Chaque cas porte ce qu'il faut pour décider d'un retry ou d'un
/// message utilisateur, sans avoir à inspecter une `NSError` générique.
public enum TranscriptionError: Error, Sendable, Equatable {
    case missingAPIKey
    case fileTooLarge(maxBytes: Int)
    case network(String)
    case invalidResponse
    case rateLimited(retryAfter: Double?)
    case server(statusCode: Int, message: String?)
    case decoding(String)
    case cancelled
}
