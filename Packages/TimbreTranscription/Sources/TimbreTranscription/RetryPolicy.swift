import Foundation

/// Backoff exponentiel + jitter — le jitter évite que plusieurs requêtes
/// échouées au même instant (ex. panne réseau générale) ne retentent toutes
/// exactement en même temps ("thundering herd").
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8.0) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = RetryPolicy()

    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        let capped = min(exponential, maxDelay)
        return capped + Double.random(in: 0...(capped * 0.3))
    }
}

/// Rejoue `operation` selon `policy` tant que `shouldRetry` accepte l'erreur
/// rencontrée. Générique et sans dépendance réseau : testable avec
/// n'importe quelle opération asynchrone qui échoue.
public func withRetry<T: Sendable>(
    policy: RetryPolicy = .default,
    shouldRetry: @Sendable (Error) -> Bool = { _ in true },
    operation: @Sendable () async throws -> T
) async throws -> T {
    var lastError: Error!

    for attempt in 1...policy.maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            guard shouldRetry(error), attempt < policy.maxAttempts else {
                throw error
            }
            try await Task.sleep(for: .seconds(policy.delay(forAttempt: attempt)))
        }
    }

    throw lastError
}
