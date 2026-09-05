/// Interface commune à tous les moteurs de transcription. L'app ne doit
/// jamais dépendre d'un provider concret — seulement de ce protocole —
/// pour que l'ajout d'un nouveau provider reste un fichier isolé.
public protocol TranscriptionProvider: Sendable {
    var identifier: ProviderIdentifier { get }
    var capabilities: ProviderCapabilities { get }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
