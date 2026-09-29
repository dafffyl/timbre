import Foundation

@testable import TimbreDiarization

/// `actor` : état mutable (compteurs d'appels, résultat configurable)
/// partagé entre le test et l'appel fait par `ModelProvisioningCoordinator`
/// — même raison que `FakeTranscriptionProvider` dans `TimbreTranscription`.
actor FakeDiarizationProvider: DiarizationProvider {
    enum PrepareResult {
        case success
        case failure(Error)
    }

    private var prepareResult: PrepareResult
    private(set) var prepareModelsCallCount = 0

    init(prepareResult: PrepareResult = .success) {
        self.prepareResult = prepareResult
    }

    func setPrepareResult(_ result: PrepareResult) {
        prepareResult = result
    }

    func prepareModels() async throws {
        prepareModelsCallCount += 1
        switch prepareResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func diarize(_ audioURL: URL) async throws -> [SpeakerSegment] {
        []
    }
}

/// `LocalizedError` : `ModelProvisioningCoordinator` capture les échecs via
/// `error.localizedDescription` — un `Error` simple sans cette conformance
/// renverrait un message générique Swift ("The operation couldn't be
/// completed…"), pas `message`, faussant les tests qui vérifient le message
/// affiché.
struct FakeError: Error, Equatable, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

actor FakeNetworkStatusProvider: NetworkStatusProvider {
    private var connectionType: NetworkConnectionType

    init(connectionType: NetworkConnectionType) {
        self.connectionType = connectionType
    }

    func setConnectionType(_ type: NetworkConnectionType) {
        connectionType = type
    }

    func currentConnectionType() async -> NetworkConnectionType {
        connectionType
    }
}

/// `final class` plutôt qu'`actor` : contrairement aux deux fakes
/// ci-dessus, `ModelProvisioningStateStore` n'a pas de méthodes `async` — un
/// verrou simple suffit et évite d'imposer `await` à chaque lecture dans les
/// tests, comme le ferait un `actor`.
final class FakeModelProvisioningStateStore: ModelProvisioningStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var consented = false
    private var completedBefore = false

    init(consented: Bool = false, completedBefore: Bool = false) {
        self.consented = consented
        self.completedBefore = completedBefore
    }

    func hasConsentedToDownload() -> Bool {
        withLocked { consented }
    }

    func recordConsent() {
        withLocked { consented = true }
    }

    func hasCompletedProvisioningBefore() -> Bool {
        withLocked { completedBefore }
    }

    func recordProvisioningCompleted() {
        withLocked { completedBefore = true }
    }

    private func withLocked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
