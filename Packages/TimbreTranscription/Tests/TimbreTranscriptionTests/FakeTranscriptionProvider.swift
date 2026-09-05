import Foundation

@testable import TimbreTranscription

/// Provider factice — la preuve que l'abstraction se suffit à elle-même
/// avant que Groq n'existe. Tout code écrit contre `any TranscriptionProvider`
/// doit fonctionner identiquement avec celui-ci ou avec un vrai provider.
///
/// `actor` plutôt que `class` : `receivedRequests` est un état mutable, et
/// le protocole exige `Sendable` — un `actor` le garantit sans verrou manuel.
/// `identifier`/`capabilities` sont `nonisolated` : immuables après l'init,
/// donc sûrs à lire de façon synchrone comme l'exige le protocole.
actor FakeTranscriptionProvider: TranscriptionProvider {
    nonisolated let identifier = ProviderIdentifier(rawValue: "fake")
    nonisolated let capabilities: ProviderCapabilities

    private let result: Result<TranscriptionResult, TranscriptionError>
    private(set) var receivedRequests: [TranscriptionRequest] = []

    init(
        capabilities: ProviderCapabilities = ProviderCapabilities(
            supportsNativeDiarization: false,
            supportsStreaming: false,
            wordTimestamps: true
        ),
        result: Result<TranscriptionResult, TranscriptionError>
    ) {
        self.capabilities = capabilities
        self.result = result
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        receivedRequests.append(request)
        return try result.get()
    }
}
